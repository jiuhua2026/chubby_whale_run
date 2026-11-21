#!/usr/bin/env python3
"""分镜图 → 透明的逐帧 PNG（专治「中灰底 + Q 版角色」这类素材）。

## 为什么不能直接用 `png_alpha_key.py`
那个工具是给「黑底」「白底」写的。黑鲸娘这套是**中灰底（≈#707070）**，而她的头发/裙子里
有大量**接近背景灰的中间调**（阴影、发丝高光）——用"离背景色的距离"当 alpha 判据，
会在角色身上挖出一堆透明的洞。

## 四段流程（顺序不能换）
① **从画面四边 BFS 找"真正的背景"**：只有能从边框连通过的近背景色才算背景
   ⇒ 角色**内部**被围住的灰色自动算前景，不会被挖洞。
② **只在每一格内部**做连通块过滤：
   · 丢掉碎点（远小于该格主体）
   · 丢掉**完全落在主体下沿之下**的块 = 地面阴影
   ⚠ 判据只能用**位置**：实测阴影的平均色离背景 34，和角色本体**一模一样**（也是 34），
     任何颜色阈值都区分不了。
   ⚠ 也别"取质心那一个像素的颜色"：质心可能恰好落在头发高光上，会误杀整块（实测 47601px）。
   ⚠ 过滤必须**按格**做：在整张图上"只留最大块"会把其他角色全部杀掉（实测 8 帧只剩 4 帧）。
③ 只在**贴着背景的 2px 边带**上按覆盖率给半透明 ⇒ 保留抗锯齿，同时把 JPEG 振铃判成背景。
④ 统一画布：**按"格心 x + 底边 y"对齐**（素材是等距格排的，格心对齐保留它自己设计的相对位移；
   底边对齐保证每帧站在同一基线上，不会上下抖）；再按**中位内容高**统一缩放到目标高度
   ⇒ 不同素材（追2.jpg / 咬击.png）各自归一，切换时不会一大一小。

用法：
  python tools/chaser_prep.py --in a.jpg --out sprites/chaser_run --prefix chaser_run \
      --mode auto --target-h 165 --contact out.png
"""
import argparse, json, os
from collections import deque, Counter
import numpy as np
from PIL import Image
from scipy import ndimage


def bg_color(im):
    w, h = im.size
    px = im.load()
    c = Counter()
    step = max(1, min(w, h) // 200)
    for x in range(0, w, step):
        c[px[x, 0]] += 1; c[px[x, h - 1]] += 1
    for y in range(0, h, step):
        c[px[0, y]] += 1; c[px[w - 1, y]] += 1
    return c.most_common(1)[0][0]


def dist(c, bg):
    return max(abs(c[0] - bg[0]), abs(c[1] - bg[1]), abs(c[2] - bg[2]))


def build_outside(im, bg, tol=10):
    """① 从四边 BFS：只有连得通边框的近背景色才算背景（向量化连通实现）。"""
    w, h = im.size
    arr = np.asarray(im, dtype=np.int16)
    bg_arr = np.array(bg, dtype=np.int16)[None, None, :]
    bgish = np.max(np.abs(arr - bg_arr), axis=2) <= tol
    lbl, _ = ndimage.label(bgish)  # 4-连通匹配边框连通背景
    border_labels = np.unique(np.concatenate([
        lbl[0, :], lbl[h - 1, :], lbl[:, 0], lbl[:, w - 1]
    ]))
    border_labels = border_labels[border_labels > 0]
    outside_mask = np.isin(lbl, border_labels)
    return bytearray(outside_mask.astype(np.uint8).tobytes())


def raw_alpha(im, outside, bg, w, h, edge_full=22):
    """③ 前景全不透明；贴着背景的 2px 边带按覆盖率给半透明。"""
    arr = np.asarray(im, dtype=np.int16)
    bg_arr = np.array(bg, dtype=np.int16)[None, None, :]
    outside_mask = np.frombuffer(outside, dtype=np.uint8).reshape(h, w).astype(bool)
    op = np.pad(outside_mask, 2, mode="constant", constant_values=False)
    edge = (~outside_mask) & (
        op[1:-3, 2:-2] | op[3:-1, 2:-2] | op[2:-2, 1:-3] | op[2:-2, 3:-1] |
        op[0:-4, 2:-2] | op[4:, 2:-2] | op[2:-2, 0:-4] | op[2:-2, 4:]
    )
    d = np.max(np.abs(arr - bg_arr), axis=2).astype(np.float32)
    alpha = np.where(outside_mask, 0, 255).astype(np.uint8)
    edge_a = np.clip(np.round(255.0 * np.minimum(1.0, d / float(edge_full))), 0, 255).astype(np.uint8)
    alpha[edge] = edge_a[edge]
    return bytearray(alpha.tobytes())


def find_cells(alpha, w, h, cols, rows, min_gap=12):
    """切格：指定 cols/rows 就用等分网格；否则按列空隙自动切。"""
    if cols and rows:
        out = []
        cw, ch = w // cols, h // rows
        for r in range(rows):
            for c in range(cols):
                out.append((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
        return out
    col_has = []
    for x in range(w):
        n = 0
        for y in range(0, h, 2):
            if alpha[y * w + x] > 64:
                n += 1
                if n >= 3:
                    break
        col_has.append(n >= 3)
    out = []
    run = None; gap = 0
    for x in range(w):
        if col_has[x]:
            run = [x, x] if run is None else [run[0], x]
            gap = 0
        elif run is not None:
            gap += 1
            if gap > min_gap:
                out.append((run[0], 0, run[1] + 1, h)); run = None
    if run is not None:
        out.append((run[0], 0, run[1] + 1, h))
    return [c for c in out if c[2] - c[0] > 60]


def filter_cell(alpha, w, h, rect, min_frac=0.002):
    """② 在**一格内部**过滤连通块：丢碎点 + 丢掉完全在主体下方的块（阴影）。"""
    x0, y0, x1, y1 = rect
    seen = bytearray(w * h)
    blobs = []
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            st = yy * w + xx
            if seen[st] or alpha[st] == 0:
                continue
            dq = deque([st]); seen[st] = 1
            cells = []
            while dq:
                i = dq.popleft(); cells.append(i)
                y, x = divmod(i, w)
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if x0 <= nx < x1 and y0 <= ny < y1:
                        j = ny * w + nx
                        if not seen[j] and alpha[j] > 0:
                            seen[j] = 1; dq.append(j)
            blobs.append(cells)
    if not blobs:
        return None, 0
    blobs.sort(key=len, reverse=True)
    big = len(blobs[0])
    main_bottom = max(i // w for i in blobs[0])
    keep = bytearray(w * h)
    for i in blobs[0]:
        keep[i] = 1
    dropped = 0
    for cells in blobs[1:]:
        top = min(i // w for i in cells)
        if top > main_bottom + 4 or len(cells) < max(48, big * min_frac):
            dropped += 1
            continue
        for i in cells:
            keep[i] = 1
    return keep, dropped


def _extract_frames_components(rgb_arr, alpha_arr, bg, w, h, cols, rows, clean_edge):
    """按整张图的 2D 连通域提取各角色帧，杜绝等分竖切把邻格尾巴切进来。"""
    fg_mask = alpha_arr > 0
    lbl, n = ndimage.label(fg_mask, structure=np.ones((3, 3), dtype=int))
    if n == 0:
        return [], 0
    counts = np.bincount(lbl.ravel())
    counts[0] = 0
    slices = ndimage.find_objects(lbl)
    max_area = int(counts.max())
    anchor_thresh = max(1000, int(max_area * 0.25))

    anchors = []
    secondary = []
    dropped = 0
    for cid in range(1, n + 1):
        area = int(counts[cid])
        sl = slices[cid - 1]
        if sl is None:
            continue
        ys_sl, xs_sl = sl
        y0, y1 = ys_sl.start, ys_sl.stop - 1
        x0, x1 = xs_sl.start, xs_sl.stop - 1
        if area >= anchor_thresh:
            anchors.append({
                "id": cid, "area": area,
                "y0": y0, "y1": y1, "x0": x0, "x1": x1,
                "cy": 0.5 * (y0 + y1), "cx": 0.5 * (x0 + x1),
                "extra": [],
            })
        elif area >= 48:
            secondary.append({
                "id": cid, "area": area,
                "y0": y0, "y1": y1, "x0": x0, "x1": x1,
                "cy": 0.5 * (y0 + y1), "cx": 0.5 * (x0 + x1),
            })
        else:
            dropped += 1

    if not anchors:
        return [], dropped

    # 为非主体块归属到最近主体，或当作地面阴影丢弃
    for sb in secondary:
        best_a = min(
            anchors,
            key=lambda a: (sb["cx"] - a["cx"]) ** 2 + (sb["cy"] - a["cy"]) ** 2,
        )
        if sb["y0"] > best_a["y1"] + 4:
            dropped += 1  # 脚下独立地面阴影
            continue
        dx = max(0, best_a["x0"] - sb["x1"], sb["x0"] - best_a["x1"])
        dy = max(0, best_a["y0"] - sb["y1"], sb["y0"] - best_a["y1"])
        if dx <= 24 and dy <= 24:
            best_a["extra"].append(sb["id"])
        else:
            dropped += 1

    # 按行（rows）与从左到右排列
    med_h = sorted(a["y1"] - a["y0"] + 1 for a in anchors)[len(anchors) // 2]
    if rows > 1:
        row_bands = [[] for _ in range(rows)]
        for a in anchors:
            ri = min(rows - 1, max(0, int(a["cy"] * rows // h)))
            row_bands[ri].append(a)
        row_bands = [sorted(rb, key=lambda a: a["cx"]) for rb in row_bands if rb]
    else:
        sorted_y = sorted(anchors, key=lambda a: a["cy"])
        row_bands = []
        for a in sorted_y:
            if not row_bands or (a["cy"] - row_bands[-1][0]["cy"]) > med_h * 0.45:
                row_bands.append([a])
            else:
                row_bands[-1].append(a)
        row_bands = [sorted(rb, key=lambda a: a["cx"]) for rb in row_bands]

    ordered = []
    for rb in row_bands:
        n_cols = cols if cols > 0 else len(rb)
        for ci, a in enumerate(rb):
            slot = min(n_cols - 1, max(0, int(a["cx"] * n_cols // w))) if cols > 0 else ci
            cell_cx = (slot + 0.5) * (w / float(max(1, n_cols)))
            ordered.append((a, cell_cx))

    bg_f = np.array(bg, dtype=np.float32)[None, None, :]
    frames = []
    for a, cell_cx in ordered:
        ids = [a["id"]] + a["extra"]
        x0 = min([a["x0"]] + [s["x0"] for s in secondary if s["id"] in a["extra"]])
        y0 = min([a["y0"]] + [s["y0"] for s in secondary if s["id"] in a["extra"]])
        x1 = max([a["x1"]] + [s["x1"] for s in secondary if s["id"] in a["extra"]])
        y1 = max([a["y1"]] + [s["y1"] for s in secondary if s["id"] in a["extra"]])

        sub_lbl = lbl[y0:y1 + 1, x0:x1 + 1]
        sub_fg = np.isin(sub_lbl, ids)
        sub_a = np.where(sub_fg, alpha_arr[y0:y1 + 1, x0:x1 + 1], 0).astype(np.float32)
        sub_rgb = rgb_arr[y0:y1 + 1, x0:x1 + 1].astype(np.float32)

        if clean_edge:
            fg_pad = np.pad(sub_fg, 2, mode="constant", constant_values=False)
            dil_out = ndimage.binary_dilation(~fg_pad, structure=np.ones((3, 3)), iterations=2)[2:-2, 2:-2]
            deep = sub_fg & (~dil_out) & (sub_a >= 240.0)
            if deep.any():
                _, idx = ndimage.distance_transform_edt(~deep, return_indices=True)
                core_rgb = sub_rgb[idx[0], idx[1]]
                rim = sub_fg & (sub_a < 255.0)
                if rim.any():
                    a_f = np.maximum(sub_a / 255.0, 0.22)[..., None]
                    unmix = np.clip((sub_rgb - (1.0 - a_f) * bg_f) / a_f, 0.0, 255.0)
                    mix_core = np.clip((0.82 - (sub_a / 255.0)) / 0.58, 0.0, 1.0)[..., None]
                    sub_rgb[rim] = (unmix * (1.0 - mix_core) + core_rgb * mix_core)[rim]

        out_rgba = np.zeros((y1 - y0 + 1, x1 - x0 + 1, 4), dtype=np.uint8)
        out_rgba[sub_fg, :3] = np.clip(np.round(sub_rgb[sub_fg]), 0, 255).astype(np.uint8)
        out_rgba[:, :, 3] = np.clip(np.round(sub_a), 0, 255).astype(np.uint8)
        out = Image.fromarray(out_rgba, mode="RGBA")

        bw = x1 - x0 + 1
        sw = float(sub_a.sum())
        if sw > 0.0:
            xs_grid = np.arange(bw, dtype=np.float32)[None, :]
            cx = float((sub_a * xs_grid).sum() / sw)
        else:
            cx = bw * 0.5
        frames.append((out, (x0, y0, x1, y1), cell_cx, cx))

    return frames, dropped


def _clean_scaled_rgba(im_rgba, min_island=24):
    """缩微后收紧外沿极淡灰雾并清掉离散小碎点（杜绝重采样产生的 1~21px 噪点）。"""
    arr = np.asarray(im_rgba, dtype=np.float32).copy()
    a = arr[:, :, 3]
    new_a = np.where(a < 80.0, 0.0, np.clip((a - 72.0) * (255.0 / 145.0), 0.0, 255.0))
    arr[:, :, 3] = new_a

    nz = new_a > 0.0
    if nz.any():
        lbl, _ = ndimage.label(nz, structure=np.ones((3, 3), dtype=int))
        counts = np.bincount(lbl.ravel())
        counts[0] = 0
        keep_ids = np.where(counts >= min_island)[0]
        keep_mask = np.isin(lbl, keep_ids)
        arr[~keep_mask, 3] = 0.0
        nz = keep_mask

    solid = arr[:, :, 3] >= 250.0
    semi = nz & (~solid)
    if solid.any() and semi.any():
        _, idx = ndimage.distance_transform_edt(~solid, return_indices=True)
        arr[semi, :3] = arr[idx[0][semi], idx[1][semi], :3]

    return Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8), mode="RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--mode", default="auto", choices=["auto", "grid4x2", "grid4x1"])
    ap.add_argument("--segment", default="components", choices=["components", "grid"],
                    help="components=全图2D连通域提取（不切尾巴，默认）；grid=旧等分格子切法")
    ap.add_argument("--target-h", type=float, default=165.0)
    ap.add_argument("--tol", type=int, default=10)
    ap.add_argument("--edge-full", type=float, default=26.0)
    ap.add_argument("--clean-edge", dest="clean_edge", action="store_true", default=True)
    ap.add_argument("--no-clean-edge", dest="clean_edge", action="store_false")
    ap.add_argument("--contact", default="")
    ap.add_argument("--align", default="cell", choices=["cell", "centroid"],
                    help="cell=按格心对齐（保留动作位移，默认）；"
                         "centroid=按身体形心对齐（消掉逐帧左右漂移，跑动循环用）")
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGB")
    w, h = im.size
    bg = bg_color(im)
    print("图 %dx%d  背景 %s" % (w, h, bg))

    outside = build_outside(im, bg, tol=args.tol)
    alpha = raw_alpha(im, outside, bg, w, h, edge_full=args.edge_full)

    cols, rows = (0, 0)
    if args.mode == "grid4x2":
        cols, rows = 4, 2
    elif args.mode == "grid4x1":
        cols, rows = 4, 1

    if args.segment == "components":
        rgb_arr = np.asarray(im, dtype=np.uint8)
        alpha_arr = np.frombuffer(alpha, dtype=np.uint8).reshape(h, w)
        frames, dropped_total = _extract_frames_components(
            rgb_arr, alpha_arr, bg, w, h, cols, rows, args.clean_edge
        )
        print("2D连通域提取 %d 帧（丢掉 %d 个阴影/碎块）" % (len(frames), dropped_total))
    else:
        cells = find_cells(alpha, w, h, cols, rows)
        print("切出 %d 格" % len(cells))

        frames = []
        dropped_total = 0
        for rect in cells:
            keep, dropped = filter_cell(alpha, w, h, rect)
            dropped_total += dropped
            if keep is None:
                print("   ⚠ 空格 %s" % (rect,))
                continue
            bx0, by0, bx1, by1 = rect[2], rect[3], rect[0], rect[1]
            for yy in range(rect[1], rect[3]):
                for xx in range(rect[0], rect[2]):
                    if keep[yy * w + xx]:
                        bx0 = min(bx0, xx); bx1 = max(bx1, xx)
                        by0 = min(by0, yy); by1 = max(by1, yy)
            if bx1 <= bx0:
                print("   ⚠ 空帧 %s" % (rect,))
                continue
            bw, bh = bx1 - bx0 + 1, by1 - by0 + 1
            out = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
            op = out.load(); sp = im.load()
            sw = sx = 0.0
            for yy in range(bh):
                for xx in range(bw):
                    gi = (by0 + yy) * w + (bx0 + xx)
                    if keep[gi] and alpha[gi]:
                        c = sp[bx0 + xx, by0 + yy]
                        op[xx, yy] = (c[0], c[1], c[2], alpha[gi])
                        sw += alpha[gi]; sx += xx * alpha[gi]
            frames.append((out, (bx0, by0, bx1, by1), (rect[0] + rect[2]) * 0.5,
                           (sx / sw) if sw > 0 else bw * 0.5))
        print("有效帧 %d（丢掉 %d 个阴影/碎块）" % (len(frames), dropped_total))
    if not frames:
        raise SystemExit("没有切出任何帧")

    margin = 4
    if args.align == "centroid":
        # **按身体形心水平对齐**（跑动循环用）：把素材自带的逐帧"身体左右漂移"消掉。
        # ⚠ 咬击**不能用这个** —— 前扑那帧本来就该往前探，按形心对齐会把动作抹平。
        half = 0.0
        for f, _, _, cx in frames:
            half = max(half, cx, f.width - cx)
        cw = int(round(half * 2)) + margin * 2
    else:
        cw = max(f.width for f, _, _, _ in frames) + margin * 2
    chh = max(f.height for f, _, _, _ in frames) + margin
    canvases = []
    for f, (bx0, by0, bx1, by1), cell_cx, cx in frames:
        frame_cx = (bx0 + bx1 + 1) * 0.5
        if args.align == "centroid":
            dx = int(round(cw * 0.5 - cx))
        else:
            dx = int(round(cw * 0.5 + (frame_cx - cell_cx) - f.width * 0.5))
        dy = chh - margin - f.height
        c = Image.new("RGBA", (cw, chh), (0, 0, 0, 0))
        c.alpha_composite(f, (dx, dy))
        canvases.append(c)

    cont = sorted(f.height for f, _, _, _ in frames)
    med = cont[len(cont) // 2]
    scale = args.target_h / float(med)
    tw, th = max(1, int(round(cw * scale))), max(1, int(round(chh * scale)))
    print("内容中位高 %d → 缩放 %.3f → 每帧 %dx%d" % (med, scale, tw, th))

    os.makedirs(args.out, exist_ok=True)
    rendered = []
    for i, c in enumerate(canvases, 1):
        rc = c.resize((tw, th), Image.LANCZOS)
        if args.clean_edge:
            rc = _clean_scaled_rgba(rc)
        rendered.append(rc)
        rc.save(os.path.join(args.out, "%s_%02d.png" % (args.prefix, i)))
    with open(os.path.join(args.out, "%s.json" % args.prefix), "w", encoding="utf-8") as fp:
        json.dump({"count": len(rendered), "frame_w": tw, "frame_h": th,
                   "anchor": "bottom-center-of-cell", "target_h": args.target_h,
                   "source": os.path.basename(args.src)}, fp, ensure_ascii=False, indent=2)
    print("→ %d 帧 %dx%d 写入 %s" % (len(rendered), tw, th, args.out))

    if args.contact:
        pad = 8
        sheet = Image.new("RGB", (tw * len(rendered) + pad * (len(rendered) + 1), th + pad * 2),
                          (18, 24, 36))
        for i, c2 in enumerate(rendered):
            sheet.paste(c2, (pad + i * (tw + pad), pad), c2)
        sheet.save(args.contact)
        print("拼图 →", args.contact)


if __name__ == "__main__":
    main()
