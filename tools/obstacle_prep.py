# -*- coding: utf-8 -*-
"""障碍素材处理：分镜图 → 可用的透明 PNG 障碍贴图。

为什么要单独一个脚本（而不是直接用 png_alpha_key.py）
------------------------------------------------------
现有抠图管线只有「黑底」和「白底」两条。障碍素材的底色是**深蓝 RGB(15,33,57)**，
两条都不适用（黑底管线假设背景 max RGB ≈ 0，深蓝的最大通道 57 会被判成前景）。

切图也不能按象限 / 等宽硬切
--------------------------
素材里每个障碍是**十几块散件**（木板 / 石头 / 海草 / 小花全都各自连通，
实测全图 622 个连通块）。按几何区域切会把相邻两组切开、互相串味。
正解：**取面积前 N 的主轴块 bbox** —— 实测每组的散件全都落在其主轴块 bbox 之内。

用法
----
    python tools/obstacle_prep.py --src 源图.jpg --out-dir sprites/hazard \\
        --prefix hazard_low --names shiprib,anchor,barrels,crate --height 64

    python tools/obstacle_prep.py --src 源图.jpg --probe

`--probe` 只打印检测结果（背景色 / 各组 bbox / 尺寸），不写任何文件。

已知可用记录
------------
| 参数 | 值 |
|---|---|
| 输出高度 | 矮障碍 = 1 格 = **64px** |
| 输出宽度 | 按原图宽高比，实测 61 / 89 / 107 / 142 px（**会超过 64px 的碰撞盒**，
这是有意的：视觉大、碰撞小是安全方向，见 docs/交接说明.md 11.0 方案 a） |
| 输出位置 | `sprites/hazard/`，由 `TerrainChunk` 用 `draw_texture_rect` 贴图，底边对齐地面 |
"""
import argparse
import os
import sys
from collections import deque

from PIL import Image, ImageChops, ImageDraw

# 与背景色的最大通道差 <= 它 就算背景候选。
# JPG 噪声实测 ±7，取 20 留足余量。边缘过渡带的后半段会被算作前景保留下来 ——
# 但源图底色 RGB(15,33,57) 与游戏水体色 RGB(14,32,56) 几乎一样，
# 那圈深蓝调在实机上天然融合，所以**不需要反预乘**。
T_BG = 20
# 分组用的**严格**阈值。必须比 T_BG 大：
# 分组只关心「哪些像素明显是障碍」，阈值越松越容易把素材自带的地平线条
# 和障碍连成同一个连通块（实测 T_BG=20 时锚那组的 bbox 从 375px 宽涨到 488px，
# 就是因为地平线条并进来了）。抠图和分组用同一张距离图、两个不同阈值。
T_GRP = 40
GROUP_PAD = 4          # 分组 bbox 外扩，保证宽松抠图的边缘不被切掉
# 宽高比超过它、且很薄的块 = 素材自带的地平线条，不参与分组
FLAT_RATIO = 4.0
FLAT_H = 80
# 参与聚类的块的最小面积。更小的当噪声/碎屑（海草末梢、JPG 噪点）
MIN_BLOCK = 200
# ---- 向上延伸段（悬顶专用，见 build_upfill）----
# 平铺样本的高度候选，从大到小试。越短重复感越强，但绳子本身就是重复的
UPFILL_BANDS = (16, 12, 8, 6, 4)
UPFILL_MIN_SOLID = 6      # 一行至少这么多实心像素，才算「这一行有绳子」
UPFILL_SOLID = 170        # 算「实心」的 alpha 阈值（滤掉半透明的边缘与末端）
# ---- 碎块清理（见 drop_specks）----
# 「与主体不相连、面积又不到最大块这个比例」的块一律删掉。
# 用比例而不是绝对像素数：矮障碍整张只有 64px 高、悬顶有 240px，同一绝对阈值两边含义不同。
SPECKS_FRAC = 0.03
SPECKS_ABS = 24           # 面积下限，避免主体很小的图上把该留的部件当碎块
SPECKS_ALPHA = 16         # 算「不透明」的 alpha 阈值
# ---- 造型内部残留的底色（见 unfill_enclosed_bg）----
BG_UNFILL_TOL = 14        # 与背景色的最大通道差
BG_UNFILL_MIN = 40        # 小于它的连通块不动，避免在造型上打出小孔


def sample_bg(im):
    """从四边采样背景主色。"""
    px = im.load()
    w, h = im.size
    votes = {}
    for x in range(0, w, 3):
        for y in (3, h - 4):
            votes[px[x, y]] = votes.get(px[x, y], 0) + 1
    for y in range(0, h, 3):
        for x in (3, w - 4):
            votes[px[x, y]] = votes.get(px[x, y], 0) + 1
    return max(votes.items(), key=lambda kv: kv[1])[0]


def bg_distance(im, bg):
    """每个像素与背景色的最大通道差。用于**抠图**。

    比 L 加权（convert("L")）更适合深蓝底：加权的蓝通道系数只有 0.114，
    蓝色通道上的差异会被严重低估。
    """
    d3 = ImageChops.difference(im, Image.new("RGB", im.size, bg))
    r, g, b = d3.split()
    return ImageChops.lighter(ImageChops.lighter(r, g), b)


def bg_distance_l(im, bg):
    """与背景色的 L 加权灰度差。用于**分组**。

    必须和抠图用不同的度量：最大通道差在深蓝底上过于灵敏，
    会把地平线条和障碍之间的过渡像素也算成前景，导致两组粘成一块
    （实测锚那组的 bbox 会从 375px 宽涨到 495px）。
    """
    return ImageChops.difference(im, Image.new("RGB", im.size, bg)).convert("L")


def horizon_mask(im):
    """素材自带的「地平线条」。

    实测颜色特征（四组造型一致，与障碍本体分离度极大）：
        地平线  B-R 97~121，G-R 74~89，且 B > G
        锚      B-R 47~53， G-R 7~8
        船肋/木桶 B-R 为负
    判据取 `B > G 且 B-R >= 80`，两边都留了大余量。
    不剔掉的话，它会跟着障碍一起被贴到游戏地面上（悬顶障碍更离谱 —— 空中挂条地平线）。
    """
    r, g, b = im.split()
    b_gt_g = ImageChops.subtract(b, g).point(bytes([0] + [255] * 255))
    b_minus_r = ImageChops.subtract(b, r).point(bytes([0] * 80 + [255] * 176))
    return ImageChops.multiply(b_gt_g, b_minus_r)


def background_mask(d, w, h):
    """与图像四边连通的「低差异」区域 = 真背景。

    必要性：障碍内部的暗部颜色可能和背景接近，只用阈值会把障碍挖出洞。
    从四边灌水，只有**与边缘连通**的才算背景。
    """
    lut = bytes([1] * (T_BG + 1) + [0] * (256 - T_BG - 1))
    m = d.point(lut)                       # 1 = 可能是背景, 0 = 明显前景
    seeds = []
    for x in range(0, w, max(1, w // 24)):
        seeds += [(x, 1), (x, h - 2)]
    for y in range(0, h, max(1, h // 24)):
        seeds += [(1, y), (w - 2, y)]
    for s in seeds:
        if m.getpixel(s) == 1:
            ImageDraw.floodfill(m, s, 255, thresh=0)
    # 现在 m: 255 = 真背景 / 1 = 非背景（含障碍内部的暗部）/ 0 = 明显前景
    return m.point(bytes([0] * 255 + [255]))


def blocks_of(binary, w, h):
    """8 邻域连通块。binary 里非 0 视为前景。"""
    seen = bytearray(w * h)
    out = []
    nb = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
    for i in range(w * h):
        if not binary[i] or seen[i]:
            continue
        q = deque([i]); seen[i] = 1; n = 0
        x0 = x1 = i % w; y0 = y1 = i // w
        while q:
            j = q.popleft(); n += 1
            x, y = j % w, j // w
            if x < x0: x0 = x
            if x > x1: x1 = x
            if y < y0: y0 = y
            if y > y1: y1 = y
            for dx, dy in nb:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    k = ny * w + nx
                    if binary[k] and not seen[k]:
                        seen[k] = 1; q.append(k)
        out.append({"n": n, "b": (x0, y0, x1, y1)})
    return out


def cluster_blocks(blocks, k, w, h, iters=16):
    """把碎块聚成 k 组（k-means：按块质心、以面积加权）。

    ⚠ 为什么不能「取面积前 k 大的块」当 k 个造型
    --------------------------------------------------
    悬垂型这组素材里，**一个造型本身就被拆成好几块**：右上「船体横撑」的 4 根
    弯曲肋骨互不相连、底梁也独立成块，左上桅杆的破帆布同样单独成块 ——
    面积前 4 名里有 3 个都是左上造型的不同部件。

    ⚠ 为什么也不能用 bbox 邻近 / 形态学膨胀聚类
    --------------------------------------------------
    组内间隙（肋骨之间 20~40px）和组间距（上下两组之间只隔 25~30px）**量级相同**，
    膨胀半径取大了两组粘一起、取小了组内拆不开 —— 没有能用的半径。

    ✅ 按「块的质心分布」聚类就没这个问题：2x2 版面下每个造型的碎块天然聚在
    各自中心附近，而**组间距再小也远大于组内碎块到中心的距离**。

    初始中心取四个象限的中心，迭代到稳定（面积加权）。
    """
    if len(blocks) < k:
        return []
    centers = [(w * 0.25, h * 0.25), (w * 0.75, h * 0.25),
               (w * 0.25, h * 0.75), (w * 0.75, h * 0.75)]
    if k != 4:
        raise ValueError("当前只支持 4 组（素材按 2x2 版面绘制）")
    groups = []
    for _ in range(iters):
        groups = [[] for _ in range(k)]
        for b in blocks:
            x0, y0, x1, y1 = b["b"]
            cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
            i = min(range(k), key=lambda j: (cx - centers[j][0]) ** 2
                    + (cy - centers[j][1]) ** 2)
            groups[i].append(b)
        moved = 0.0
        for i, g in enumerate(groups):
            if not g:
                continue
            tot = float(sum(x["n"] for x in g))
            mx = sum((x["b"][0] + x["b"][2]) * 0.5 * x["n"] for x in g) / tot
            my = sum((x["b"][1] + x["b"][3]) * 0.5 * x["n"] for x in g) / tot
            moved = max(moved, abs(mx - centers[i][0]), abs(my - centers[i][1]))
            centers[i] = (mx, my)
        if moved < 1.0:
            break
    out = []
    for g in groups:
        if not g:
            out.append(None)
            continue
        out.append({
            "n": sum(x["n"] for x in g),
            "parts": len(g),
            "b": (min(x["b"][0] for x in g), min(x["b"][1] for x in g),
                  max(x["b"][2] for x in g), max(x["b"][3] for x in g)),
        })
    return out


def drop_specks(tex, alpha_t=SPECKS_ALPHA, frac=SPECKS_FRAC, abs_min=SPECKS_ABS):
    """删掉「和主体不相连、又明显偏小」的碎块。返回 (图像, 被删块面积列表)。

    ⚠ 为什么必须做
    --------------------------------------------------
    源图里障碍旁边常有零散杂物 —— 实测「断裂桅杆」底部有一小卷绳圈（109px）、
    「船体横撑」底部有一个小绳梯（525px）。它们**落在分组的 bbox 之内**
    （而分组 bbox 里的前景像素是整片裁下来的，不按连通块过滤），
    所以会被一起吃进贴图；但它们和主体**不相连**，贴到游戏里就是悬在
    净空线上方的几个噪点 —— 用户 2026-09-27 圈出来的正是这两处。

    缩放本身也会制造碎块：源图里只有 1~2px 宽的连接，按 0.35 倍缩完就断了，
    于是障碍边缘的一小条变成孤立块（矮障碍四张的底边都有 1~12px 这种残渣）。

    ⚠ 判据为什么用「最大块的比例」而不是绝对像素数
    --------------------------------------------------
    矮障碍整张只有 64px 高（主体 4000~6000px），悬顶主体 2~3 万 px，
    同一个绝对阈值在两边含义完全不同。实测被删的块都 ≤ 最大块的 2.4%，
    而**该保留的部件**（船体横撑的 4 根独立肋骨、各造型的海草小花）都 ≥ 10%，
    中间空得很开，阈值取 3% 很安全。
    """
    w, h = tex.size
    px = tex.load()
    seen = bytearray(w * h)
    comps = []
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0 * w + x0] or px[x0, y0][3] <= alpha_t:
                continue
            stack = [(x0, y0)]
            seen[y0 * w + x0] = 1
            pts = []
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] \
                                and px[nx, ny][3] > alpha_t:
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
            comps.append(pts)
    if len(comps) < 2:
        return tex, []
    comps.sort(key=len, reverse=True)
    cut = max(abs_min, int(len(comps[0]) * frac))
    out = tex.copy()
    op = out.load()
    dropped = []
    for pts in comps[1:]:
        if len(pts) < cut:
            dropped.append(len(pts))
            for (x, y) in pts:
                op[x, y] = (0, 0, 0, 0)
    dropped.sort(reverse=True)
    return out, dropped


def unfill_enclosed_bg(tex, bg, tol=BG_UNFILL_TOL, min_area=BG_UNFILL_MIN,
                       alpha_t=SPECKS_ALPHA):
    """把「被造型围住的底色区域」也抹成透明。返回 (图像, 被抹掉的块面积列表)。

    ⚠ 为什么不能只靠 background_mask
    --------------------------------------------------
    `background_mask` 的判据是「**从四边连通**到画面边缘的才算背景」。
    这条判据对「造型外面的底」有效，但**造型自己围出来的封闭区域**连不到边缘：
      · 悬挂锚链的 A 形内部（链子 + 横梁 + 吊环围成）
      · 吊货滑车绳子围出的那片三角区
      · 链环中间的孔
    这些区域于是被当前景留下，贴到游戏里就是一块**比背景略亮的蓝斑**
    （用户 2026-09-27：「感觉应该是空的，但现在有点泛蓝」）。

    判据：不透明 + 颜色接近底色 + 连通块面积 ≥ min_area。
    实测残留块的色散很小（众数 (12,36,60)，与底色 (14,32,56) 最大通道差 ≤14），
    而**造型自己的深色部分**（紫色阴影、木箱暗部、锁链锈色）色相差得远，不会被误伤 ——
    实测四款悬顶各只清掉 12~17 块，全是该空的区域。
    """
    w, h = tex.size
    px = tex.load()
    hit = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > alpha_t and max(abs(r - bg[0]), abs(g - bg[1]),
                                   abs(b - bg[2])) <= tol:
                hit[y * w + x] = 1
    seen = bytearray(w * h)
    out = tex.copy()
    op = out.load()
    killed = []
    for y0 in range(h):
        for x0 in range(w):
            i = y0 * w + x0
            if seen[i] or not hit[i]:
                continue
            stack = [(x0, y0)]
            seen[i] = 1
            pts = []
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] \
                                and hit[ny * w + nx]:
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
            if len(pts) >= min_area:
                killed.append(len(pts))
                for (x, y) in pts:
                    op[x, y] = (0, 0, 0, 0)
    killed.sort(reverse=True)
    return out, killed


def build_upfill(tex, height):
    """生成向上延伸段（宽 = tex 宽，高 = height）。返回 (图像, 采样起点 y) 或 (None, -1)。

    ⚠ 为什么不能拿贴图最上面 1~2 行来拉伸
    --------------------------------------------------
    贴图的顶边就是造型的最高点，也就是绳子的**顶端末端**：渐细、而且大量像素是
    半透明的（抗锯齿）。拉出来是细如蛛丝的线，和下方的粗绳完全接不上 ——
    视觉上非常突兀（用户原话「空中连接点很奇怪」）。

    ⚠ 为什么要检查「形状稳定」
    --------------------------------------------------
    像「悬挂锚链」那种顶部是吊环的造型，行与行之间形状在变，
    随便取一段平铺会重复出弧线。只在**像素数与 x 范围都稳定**的区间里取样，
    才是真正竖直的绳段。

    ⚠ 这个判据**只对「绳子」成立，对「链条」是错的**（2026-09-27）
    --------------------------------------------------
    「链环」只有中段那一小段侧面宽度是恒定的，所以这里能挑到的只是**链环的一个切片**
    （实测 8px），平铺出来是一条细密棱纹带，完全不像链子；
    「吊货滑车」更糟：它顶部那段链子往下 8px 就被滑轮挡住，采到的是链节端部/滑轮轮缘，
    平铺出来是木纹斜格带。
    → 链条类的材质请用 `tools/hazard_upfill.py`：取**一整节链环**为材质块，
      并且平铺步长 < 块高（链环要互相扣住，首尾相接会读成「一串断开的珠子」）。

    找不到稳定段时返回 None —— 这时**宁可不延伸**，也不要补出怪东西。
    """
    a = tex.getchannel("A")
    w, h = tex.size
    scan = min(h, 90)
    rows = []
    for y in range(scan):
        rows.append([x for x in range(w) if a.getpixel((x, y)) > UPFILL_SOLID])

    # 收集候选，最后取 y0 最小的那个。
    # ⚠ 必须优先选**靠上**的绳段：越靠上越接近贴图顶边，延伸段和本体接得越顺。
    #   如果按「先试长样本」的顺序直接返回，会优先选中靠下的粗段（例如桅杆
    #   y=40 处「绳子缠绕桅杆」的粗节），接缝处就会粗细突变。
    best = None
    for band in UPFILL_BANDS:
        if band >= scan:
            continue
        for y0 in range(0, scan - band):
            c0 = rows[y0]
            if len(c0) < UPFILL_MIN_SOLID:
                continue
            ok = True
            for k in range(y0 + 1, y0 + band):
                c = rows[k]
                if not c or abs(len(c) - len(c0)) > max(2, len(c0) * 0.25):
                    ok = False
                    break
                if abs(c[0] - c0[0]) > 3 or abs(c[-1] - c0[-1]) > 3:
                    ok = False
                    break
            if not ok:
                continue
            if best is None or y0 < best[0]:
                best = (y0, band, max(0, c0[0] - 2), min(w - 1, c0[-1] + 2))
    if best is None:
        return None, -1
    y0, band, x0, x1 = best
    # 取整块（含中间透明部分，这样两根绳会一起被平铺）
    tile = tex.crop((x0, y0, x1 + 1, y0 + band))
    out = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    k = 0
    while k * band < height:
        out.paste(tile, (x0, height - (k + 1) * band), tile)
        k += 1
    return out, y0


def resize_rgba(img, size):
    """预乘 alpha 重采样（和 slice_spritesheet.resize_rgba 同一套，防暗边）。

    预乘 → LANCZOS → 反预乘。少了预乘这一步，边缘的半透明像素会和黑混合成暗边。
    返回 (图像, 半透明像素数)。
    """
    a = img.getchannel("A")
    r, g, b, _ = img.split()
    pre = Image.merge("RGB", (
        ImageChops.multiply(r, a),
        ImageChops.multiply(g, a),
        ImageChops.multiply(b, a),
    )).resize(size, Image.LANCZOS)
    a2 = a.resize(size, Image.LANCZOS)

    w, h = size
    src = pre.tobytes()        # RGB：每像素 3 字节
    ab = a2.tobytes()
    out = bytearray(w * h * 4)  # RGBA：每像素 4 字节
    n_partial = 0
    for i in range(w * h):
        p = i * 4
        q = i * 3
        al = ab[i]
        out[p + 3] = al
        if al == 0:
            continue
        if al == 255:
            out[p] = src[q]; out[p + 1] = src[q + 1]; out[p + 2] = src[q + 2]
            continue
        n_partial += 1
        f = al / 255.0
        for c in range(3):
            v = int(round(src[q + c] / f))
            out[p + c] = 255 if v > 255 else (0 if v < 0 else v)
    return Image.frombytes("RGBA", (w, h), bytes(out)), n_partial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out-dir", default="sprites/hazard")
    ap.add_argument("--prefix", default="hazard_low")
    ap.add_argument("--names", default="", help="逗号分隔，按「先上后下、各自从左到右」")
    ap.add_argument("--height", type=int, default=64,
                    help="输出高度。矮障碍 = 1 格 = 64")
    ap.add_argument("--count", type=int, default=4, help="切几组")
    ap.add_argument("--probe", action="store_true", help="只检测不写文件")
    ap.add_argument("--upfill", type=int, default=0,
                    help="在贴图上方再合成这么高的「向上延伸段」（悬顶专用，见 build_upfill）")
    args = ap.parse_args()

    if not os.path.isfile(args.src):
        sys.exit("找不到源图：%s" % args.src)

    im = Image.open(args.src).convert("RGB")
    w, h = im.size
    bg = sample_bg(im)
    print("源图 %dx%d   背景色 RGB%s" % (w, h, str(bg)))

    d = bg_distance(im, bg)
    # 抠图：宽松阈值 + 边缘连通判定，再剔掉素材自带的地平线条
    alpha = ImageChops.invert(background_mask(d, w, h))
    hz = horizon_mask(im)
    alpha = ImageChops.subtract(alpha, hz)
    ab = alpha.tobytes()
    n_hz = sum(1 for v in hz.tobytes() if v)
    print("前景 %.1f%%   剔除地平线条 %d px" % (100.0 * ab.count(255) / (w * h), n_hz))

    # 分组：用 L 加权度量 + 严格阈值（把四组干净地分开）
    grp = bg_distance_l(im, bg).point(bytes([0] * (T_GRP + 1) + [255] * (256 - T_GRP - 1)))
    blocks = blocks_of(grp.tobytes(), w, h)
    print("连通块 %d 个（分组阈值 %d，L 加权）" % (len(blocks), T_GRP))

    ok = [b for b in blocks
          if b["n"] >= MIN_BLOCK
          and not ((b["b"][2] - b["b"][0] + 1) / float(b["b"][3] - b["b"][1] + 1) > FLAT_RATIO
                   and (b["b"][3] - b["b"][1] + 1) < FLAT_H)]
    picked = [g for g in cluster_blocks(ok, args.count, w, h) if g is not None]
    if len(picked) != args.count:
        sys.exit("聚类失败：只得到 %d 组（期望 %d），检查素材版面是不是 2x2"
                 % (len(picked), args.count))

    names = [s.strip() for s in args.names.split(",") if s.strip()]
    if len(names) != len(picked):
        names = ["ob%02d" % i for i in range(len(picked))]

    print("\n切出 %d 组：" % len(picked))
    if not args.probe:
        os.makedirs(args.out_dir, exist_ok=True)
    for name, b in zip(names, picked):
        x0, y0, x1, y1 = b["b"]
        box = (max(0, x0 - GROUP_PAD), max(0, y0 - GROUP_PAD),
               min(w, x1 + 1 + GROUP_PAD), min(h, y1 + 1 + GROUP_PAD))
        sub_a = alpha.crop(box).tobytes()
        inside = sum(1 for v in sub_a if v)
        rgba = im.crop(box).convert("RGBA")
        rgba.putalpha(alpha.crop(box))
        # 收紧到 alpha 的实际边界。
        # GROUP_PAD 只用来保证「宽松抠图的边缘不被切掉」，**不能留在成品里** ——
        # 留着的话贴图上下各带几像素透明，障碍贴到地面上会看起来悬空一条缝。
        tight = rgba.getchannel("A").getbbox()
        trimmed = ""
        if tight:
            trimmed = " 收紧(%d,%d,-%d,-%d)" % (
                tight[0], tight[1], rgba.width - tight[2], rgba.height - tight[3])
            rgba = rgba.crop(tight)
        tw = max(1, int(round(rgba.width * args.height / float(rgba.height))))
        small, npart = resize_rgba(rgba, (tw, args.height))
        # 造型**内部**残留的底色（被链子/绳子围住的封闭区域）→ 抹掉，见 unfill_enclosed_bg
        small, unfilled = unfill_enclosed_bg(small, bg)
        # 清掉与主体不相连的小碎块（源图里挨着的杂物 + 缩放掐断的边缘残渣，见 drop_specks）
        small, specks = drop_specks(small)
        # 清完再收紧一次：**贴图底边必须正好落在净空线（悬顶）或地面（矮障碍）上**。
        # 第一次收紧在缩放之前，只保证边缘不被切掉；清掉底部碎块后可能空出若干行，
        # 不收的话障碍的可见下沿会比碰撞盒高一截（实测横撑差 23px，玩家看不出该在哪滑进去）。
        #
        # ⚠ bbox 必须按 SPECKS_ALPHA 阈值算，**不能用 getbbox() 默认的「>0」**：
        #   删掉碎块只是把它的像素清零，周围那圈 alpha 1~16 的淡光环还在，
        #   默认口径会把它算进来 → bbox 一点没变 → 等于没裁（这个坑踩过一次）。
        mask = small.getchannel("A").point(lambda v: 255 if v > SPECKS_ALPHA else 0)
        bb = mask.getbbox()
        if bb and bb != (0, 0, small.width, small.height):
            small = small.crop(bb)
        cov = sum(1 for v in small.getchannel("A").tobytes() if v) \
            / float(small.width * small.height)
        print("  %-9s bbox=(%4d,%4d)-(%4d,%4d) %d块/%-6dpx%s → %dx%d  覆盖率 %.2f%s%s"
              % (name, x0, y0, x1, y1, b["parts"], inside, trimmed,
                 small.width, small.height, cov,
                 ("  ← 清底色 %d 块 %s" % (len(unfilled), unfilled[:5])) if unfilled else "",
                 ("  ← 清碎块 %d 个 %s" % (len(specks), specks[:5])) if specks else ""))
        if args.probe:
            continue
        final = small
        note = ""
        if args.upfill > 0:
            up, src_y = build_upfill(small, args.upfill)
            if up is None:
                note = "  ← 顶部不是绳子（找不到稳定绳段），未延伸"
            else:
                final = Image.new("RGBA", (small.width, small.height + args.upfill), (0, 0, 0, 0))
                final.paste(up, (0, 0))
                final.paste(small, (0, args.upfill))
                note = "  + 延伸 %dpx（绳段采样自 y=%d）" % (args.upfill, src_y)
        out = os.path.join(args.out_dir, "%s_%s.png" % (args.prefix, name))
        final.save(out)
        print("            → %s%s" % (out, note))
    if args.probe:
        print("\n（--probe：未写任何文件）")


if __name__ == "__main__":
    main()
