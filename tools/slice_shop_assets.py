#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 Phase 2 生成的 6 张深海鲸堡小店美术图自动切分、去灰底、对齐锚点并保存为独立透明 PNG 到 sprites/shop/。
同时在 scratch 目录输出一张棋盘格拼图预览以便逐个核对抠图质量（无灰边、无破洞、无裁切）。
"""

import os
import sys
from collections import deque
from statistics import median

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("需要 Pillow: pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART_DIR = r"C:\Users\25941\.gemini\antigravity\brain\402921d3-5f6d-4dac-b32d-fc51335c5273"
OUT_DIR = os.path.join(ROOT, "sprites", "shop")
PREVIEW_PATH = os.path.join(ART_DIR, "scratch", "shop_cut_preview.png")

NEI8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
NEI4 = ((0, -1), (-1, 0), (1, 0), (0, 1))


def find_grid_splits(im: Image.Image, cols: int, rows: int):
    """通过投影能量在预期网格线 ±12% 范围内寻找最干净的中灰分隔槽位。"""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()

    # 用四周边界中位值估算纯底灰
    samples = []
    for x in range(w):
        samples.append(px[x, 2])
        samples.append(px[x, h - 3])
    for y in range(h):
        samples.append(px[2, y])
        samples.append(px[w - 3, y])
    bg = tuple(int(median(c[i] for c in samples)) for i in range(3))

    def col_energy(x: int) -> int:
        tot = 0
        for y in range(h):
            r, g, b = px[x, y]
            d = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            if d > 22:
                tot += d
        return tot

    def row_energy(y: int) -> int:
        tot = 0
        for x in range(w):
            r, g, b = px[x, y]
            d = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            if d > 22:
                tot += d
        return tot

    xs = [0]
    for ci in range(1, cols):
        nom = int(w * ci / cols)
        lo = max(1, nom - int(w * 0.12))
        hi = min(w - 1, nom + int(w * 0.12))
        best_x = min(range(lo, hi + 1), key=lambda x: (col_energy(x), abs(x - nom)))
        xs.append(best_x)
    xs.append(w)

    ys = [0]
    for ri in range(1, rows):
        nom = int(h * ri / rows)
        lo = max(1, nom - int(h * 0.12))
        hi = min(h - 1, nom + int(h * 0.12))
        best_y = min(range(lo, hi + 1), key=lambda y: (row_energy(y), abs(y - nom)))
        ys.append(best_y)
    ys.append(h)

    return xs, ys


def remove_gray_bg(cell: Image.Image, bg_tol: int = 22, chroma_tol: int = 18,
                   internal_tol: int = 10, internal_min_area: int = 24) -> Image.Image:
    """
    对单个格子执行四边连通 BFS 抠中灰背景 + 内部闭合灰洞检查 + 1~2px 边缘去灰晕。
    """
    src = cell.convert("RGB")
    w, h = src.size
    data = src.tobytes()

    # 估计本地中灰底色（只采集接近灰色的边缘像素，以防个别边缘碰到前景）
    border_pts = []
    for x in range(w):
        border_pts.append((x, 0))
        border_pts.append((x, h - 1))
    for y in range(h):
        border_pts.append((0, y))
        border_pts.append((w - 1, y))
    gray_samples = []
    for x, y in border_pts:
        j = (y * w + x) * 3
        r, g, b = data[j], data[j + 1], data[j + 2]
        if max(r, g, b) - min(r, g, b) <= 18 and 60 <= r <= 155:
            gray_samples.append((r, g, b))
    if not gray_samples:
        gray_samples = [(106, 106, 106)]
    bgr = int(median(c[0] for c in gray_samples))
    bgg = int(median(c[1] for c in gray_samples))
    bgb = int(median(c[2] for c in gray_samples))

    def is_bg_candidate(idx: int, tol: int, ctol: int) -> bool:
        j = idx * 3
        r, g, b = data[j], data[j + 1], data[j + 2]
        chroma = max(r, g, b) - min(r, g, b)
        if chroma > ctol:
            return False
        dist = max(abs(r - bgr), abs(g - bgg), abs(b - bgb))
        return dist <= tol

    bg = bytearray(w * h)
    dq = deque()
    # 从四边所有符合灰底条件的像素出发
    for x, y in border_pts:
        idx = y * w + x
        if not bg[idx] and is_bg_candidate(idx, bg_tol, chroma_tol):
            bg[idx] = 1
            dq.append(idx)

    while dq:
        i = dq.popleft()
        y, x = divmod(i, w)
        for dx, dy in NEI4:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                n = ny * w + nx
                if not bg[n] and is_bg_candidate(n, bg_tol, chroma_tol):
                    bg[n] = 1
                    dq.append(n)

    # 第二遍：清理面积较小、高度贴近纯背景灰的小镂空洞（如臂弯间隙、尾鳍与风衣夹角）
    seen = bytearray(bg)
    for start in range(w * h):
        if seen[start] or not is_bg_candidate(start, internal_tol, 10):
            continue
        comp = [start]
        seen[start] = 1
        cdq = deque([start])
        while cdq:
            i = cdq.popleft()
            y, x = divmod(i, w)
            for dx, dy in NEI4:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    n = ny * w + nx
                    if not seen[n] and is_bg_candidate(n, internal_tol, 10):
                        seen[n] = 1
                        comp.append(n)
                        cdq.append(n)
        # 镂空面积适中且大部分周围是暗色描边时才视为背景洞（防误伤纯灰大色块）
        if internal_min_area <= len(comp) <= (w * h) // 16:
            border_dark = 0
            border_tot = 0
            comp_set = set(comp)
            for i in comp:
                y, x = divmod(i, w)
                for dx, dy in NEI4:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        n = ny * w + nx
                        if n not in comp_set and not bg[n]:
                            border_tot += 1
                            j = n * 3
                            if max(data[j], data[j + 1], data[j + 2]) <= 78:
                                border_dark += 1
            if border_tot > 0 and (border_dark / float(border_tot)) >= 0.55:
                for i in comp:
                    bg[i] = 1

    # 去除脱离主体、面积极小的孤立噪点岛（<14px，防止背景灰噪点残留），保留较大闪烁星星
    fg_seen = bytearray(w * h)
    for start in range(w * h):
        if bg[start] or fg_seen[start]:
            continue
        comp = [start]
        fg_seen[start] = 1
        fdq = deque([start])
        while fdq:
            i = fdq.popleft()
            y, x = divmod(i, w)
            for dx, dy in NEI8:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    n = ny * w + nx
                    if not bg[n] and not fg_seen[n]:
                        fg_seen[n] = 1
                        comp.append(n)
                        fdq.append(n)
        if len(comp) < 14:
            for i in comp:
                bg[i] = 1

    # 构建 RGBA 并做 1px 边缘柔和反混合
    buf = bytearray(w * h * 4)
    for i in range(w * h):
        if bg[i]:
            continue
        j = i * 3
        r, g, b = data[j], data[j + 1], data[j + 2]
        y, x = divmod(i, w)
        touches_bg = False
        for dx, dy in NEI4:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and bg[ny * w + nx]:
                touches_bg = True
                break
        a = 255
        if touches_bg:
            # 离底灰越近的边缘像素适当衰减 alpha 并反混合去灰边
            dist = ((r - bgr) ** 2 + (g - bgg) ** 2 + (b - bgb) ** 2) ** 0.5
            if dist < 44.0:
                af = max(0.18, min(1.0, (dist - 12.0) / 32.0))
                a = int(af * 255.0 + 0.5)
                if af > 0.1:
                    r = max(0, min(255, int(bgr + (r - bgr) / af)))
                    g = max(0, min(255, int(bgg + (g - bgg) / af)))
                    b = max(0, min(255, int(bgb + (b - bgb) / af)))
        o = i * 4
        buf[o] = r
        buf[o + 1] = g
        buf[o + 2] = b
        buf[o + 3] = a

    return Image.frombytes("RGBA", (w, h), bytes(buf))


def resize_premultiplied(im: Image.Image, target_size):
    """预乘 alpha 缩放，避免透明边界泛灰黑边。"""
    w, h = im.size
    nw, nh = target_size
    if (w, h) == (nw, nh):
        return im.copy()
    r, g, b, a = im.split()
    ad = a.tobytes()
    pre = []
    for ch in (r, g, b):
        d = ch.tobytes()
        pre.append(Image.frombytes("L", (w, h),
                                   bytes((d[i] * ad[i] + 127) // 255 for i in range(w * h))))
    pm = Image.merge("RGBA", (pre[0], pre[1], pre[2], a)).resize((nw, nh), Image.LANCZOS)
    pr, pg, pb, pa = pm.split()
    pd = pa.tobytes()
    out = []
    for ch in (pr, pg, pb):
        d = ch.tobytes()
        out.append(Image.frombytes("L", (nw, nh),
                                   bytes(min(255, (d[i] * 255 + pd[i] // 2) // pd[i]) if pd[i] else 0
                                         for i in range(nw * nh))))
    return Image.merge("RGBA", (out[0], out[1], out[2], pa))


def fit_square_centered(im: Image.Image, box_size: int, pad: int = 8) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return Image.new("RGBA", (box_size, box_size), (0, 0, 0, 0))
    crop = im.crop(bbox)
    cw, ch = crop.size
    avail = box_size - pad * 2
    scale = min(avail / float(cw), avail / float(ch))
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))
    scaled = resize_premultiplied(crop, (nw, nh))
    canvas = Image.new("RGBA", (box_size, box_size), (0, 0, 0, 0))
    canvas.paste(scaled, ((box_size - nw) // 2, (box_size - nh) // 2), scaled)
    return canvas


def fit_pair_bottom_aligned(poses: list, box_w: int, box_h: int, pad_x: int = 10, pad_y: int = 10) -> list:
    """将同一角色的多个动作帧按统一比例底部居中对齐，防止切换姿势时忽大忽小或上下跳动。"""
    crops = []
    max_h = 1
    max_w = 1
    for im in poses:
        bbox = im.getbbox()
        c = im.crop(bbox) if bbox else Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        crops.append(c)
        max_w = max(max_w, c.width)
        max_h = max(max_h, c.height)
    scale = min((box_w - pad_x * 2) / float(max_w), (box_h - pad_y * 2) / float(max_h))
    out = []
    for c in crops:
        nw = max(1, int(round(c.width * scale)))
        nh = max(1, int(round(c.height * scale)))
        scaled = resize_premultiplied(c, (nw, nh))
        canvas = Image.new("RGBA", (box_w, box_h), (0, 0, 0, 0))
        ox = (box_w - nw) // 2
        oy = box_h - pad_y - nh
        canvas.paste(scaled, (ox, oy), scaled)
        out.append(canvas)
    return out


def tint_blackwhale_wait_shades(im: Image.Image) -> Image.Image:
    """
    微调乔装黑鲸娘待机帧（Row2 Col1）的浅色眼镜片，使其更接近右格的墨镜酷感，
    同时保留镜框与周围肤色。
    """
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    # 在大致眼部区域（x: 34%~64%, y: 31%~44%）里找被深色镜框包围的高亮浅肤/镜片反光色并压暗偏墨紫灰
    # 仅处理亮度较高且接近肤色/米白反光的镜片区域，避免碰触白色衣领或脸颊外侧
    x0, x1 = int(w * 0.37), int(w * 0.62)
    y0, y1 = int(h * 0.34), int(h * 0.425)
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            # 跳过鼻梁中心极窄竖带（保留眼镜鼻托区皮肤），以及最深黑描边
            if abs(x - int(w * 0.495)) <= int(w * 0.015):
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            # 眼白/浅灰/眼瞳高光都偏暗化处理成半透深墨镜效果
            if lum > 72:
                nr = int(r * 0.24 + 12)
                ng = int(g * 0.22 + 12)
                nb = int(b * 0.26 + 18)
                px[x, y] = (nr, ng, nb, a)
    return rgba


def build_contact_preview(items: list, out_path: str):
    """生成棋盘格背景缩略拼图以验收抠图质量。"""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    cols = 6
    cell_w, cell_h = 180, 196
    rows = (len(items) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * cell_w, rows * cell_h), (40, 44, 52))
    draw = ImageDraw.Draw(canvas)

    for idx, (label, img) in enumerate(items):
        r = idx // cols
        c = idx % cols
        ox = c * cell_w
        oy = r * cell_h
        # 棋盘格
        for yy in range(oy, oy + cell_h - 24, 12):
            for xx in range(ox, ox + cell_w, 12):
                col = (155, 160, 170) if (((xx // 12) + (yy // 12)) % 2 == 0) else (112, 118, 128)
                draw.rectangle([xx, yy, min(xx + 11, ox + cell_w - 1), min(yy + 11, oy + cell_h - 25)], fill=col)
        # 居中贴图
        thumb = img.copy()
        thumb.thumbnail((cell_w - 16, cell_h - 36), Image.LANCZOS)
        tx = ox + (cell_w - thumb.width) // 2
        ty = oy + (cell_h - 24 - thumb.height) // 2
        canvas.paste(thumb.convert("RGB"), (tx, ty), thumb)
        draw.rectangle([ox, oy + cell_h - 24, ox + cell_w - 1, oy + cell_h - 1], fill=(20, 26, 36))
        draw.text((ox + 6, oy + cell_h - 18), label, fill=(225, 240, 255))
        draw.rectangle([ox, oy, ox + cell_w - 1, oy + cell_h - 1], outline=(70, 90, 115))

    canvas.save(out_path)


def build_foreground_masks(bg_rgb: Image.Image):
    """
    直接从 1280×720 实景底图 shop_bg 中精准抠出 4 层前景遮罩（同尺寸 1280×720 透明 PNG，保证像素级零错位）：
      1. shop_fg_window.png  : 左侧外卖窗下方凸出木窗台与拱窗外框（窗洞内部全透明，顾客从窗内探头）
      2. shop_fg_counter.png : 中景木质吧台台面与柜体正面（店员站进柜台里面，腰部以下被挡住）
      3. shop_fg_booth1.png  : 右一珊瑚卡座的木餐桌与前方挡板（顾客坐在后排粉色坐垫，腿部藏进桌后）
      4. shop_fg_booth2.png  : 右二珊瑚卡座的木餐桌与最右侧前排粉沙发（乔装黑鲸娘坐在卡座内餐桌后）
    """
    w, h = bg_rgb.size
    rgba = bg_rgb.convert("RGBA")

    def mask_layer(draw_fn):
        m = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(m)
        draw_fn(d)
        out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        out.paste(rgba, (0, 0), m)
        return out

    # 1) 外卖窗口前景：保留窗外左右木柱+顶部木栅，扣掉内部开窗区，只让下缘凸出木窗台遮挡客人尾巴
    def _draw_window(d: ImageDraw.ImageDraw):
        # 覆盖窗口周边区域的木框架与下窗台（x: 78..252, y: 175..430）
        d.rectangle([78, 175, 252, 430], fill=255)
        # 抠透明：保留暗色窗洞内部（下方窗台从 y=369 起保留不透明）
        # 上部木竖栅栏底部在 y≈246，窗洞左右内壁大约在 x: 112..214
        d.rectangle([113, 246, 213, 368], fill=0)

    fg_win = mask_layer(_draw_window)
    fg_win.save(os.path.join(OUT_DIR, "shop_fg_window.png"))

    # 2) 中景木吧台前景：台面顶部亮木沿在 y=350（左端 y=353，右端 y=349），向下延伸至地板 y=462
    def _draw_counter(d: ImageDraw.ImageDraw):
        # 主木吧台轮廓（含上方浅木台沿与最上方 2px 深色描边线）
        d.polygon([
            (384, 350),
            (686, 350),
            (686, 458),
            (394, 458),
            (384, 380),
        ], fill=255)

    fg_cnt = mask_layer(_draw_counter)
    fg_cnt.save(os.path.join(OUT_DIR, "shop_fg_counter.png"))

    # 3) 右一卡座前景：严格贴合木桌面斜边与旋木桌脚，不带入左侧粉色坐垫
    def _draw_booth1(d: ImageDraw.ImageDraw):
        d.polygon([
            (795, 384),
            (850, 376),
            (956, 378),
            (956, 476),
            (842, 476),
            (842, 408),
            (795, 398),
        ], fill=255)

    fg_b1 = mask_layer(_draw_booth1)
    fg_b1.save(os.path.join(OUT_DIR, "shop_fg_booth1.png"))

    # 4) 右二卡座前景：严格沿着棕色木桌面实际边缘 (1028,418)->(1178,398) 切割，不抓进上方粉色坐垫
    def _draw_booth2(d: ImageDraw.ImageDraw):
        d.polygon([
            (1028, 418),
            (1178, 398),
            (1240, 404),
            (1240, 496),
            (1118, 496),
            (1118, 440),
            (1028, 434),
        ], fill=255)
        # 最右侧前排粉红沙发靠背 (1162..1280, y: 372..496)
        d.polygon([
            (1240, 370),
            (1280, 366),
            (1280, 496),
            (1160, 496),
            (1160, 452),
            (1214, 412),
        ], fill=255)

    fg_b2 = mask_layer(_draw_booth2)
    fg_b2.save(os.path.join(OUT_DIR, "shop_fg_booth2.png"))

    # 合成一张遮挡验收样图到 scratch 目录下
    test = rgba.copy()
    seahorse = Image.open(os.path.join(OUT_DIR, "cust_seahorse_wait.png")).convert("RGBA").resize((132, 132), Image.LANCZOS)
    crew = Image.open(os.path.join(OUT_DIR, "crew_cook.png")).convert("RGBA").resize((156, 180), Image.LANCZOS)
    turtle = Image.open(os.path.join(OUT_DIR, "cust_turtle_wait.png")).convert("RGBA").resize((144, 144), Image.LANCZOS)
    bw = Image.open(os.path.join(OUT_DIR, "cust_blackwhale_wait.png")).convert("RGBA").resize((142, 142), Image.LANCZOS)

    test.alpha_composite(seahorse, (98, 260))
    test.alpha_composite(fg_win)
    test.alpha_composite(crew, (456, 232))
    test.alpha_composite(fg_cnt)
    test.alpha_composite(turtle, (746, 294))
    test.alpha_composite(fg_b1)
    test.alpha_composite(bw, (1016, 304))
    test.alpha_composite(fg_b2)

    occ_path = os.path.join(ART_DIR, "scratch", "shop_occlusion_test.png")
    test.crop((0, 120, 1280, 505)).save(occ_path)
    print(f"[OK] 前景遮罩 4 层已生成，遮挡验收图: {occ_path}")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    preview_items = []

    # 1. 横屏背景 1280x720
    bg_src = Image.open(os.path.join(ART_DIR, "v2_shop_bg_wide_1795769817999.jpg")).convert("RGB")
    bg_out = bg_src.resize((1280, 720), Image.LANCZOS)
    bg_out.save(os.path.join(OUT_DIR, "shop_bg.png"))
    print(f"[OK] shop_bg.png {bg_out.size}")
    build_foreground_masks(bg_out)

    # 2. 菜品与代币图标 3x3 -> 112x112
    icons_src = Image.open(os.path.join(ART_DIR, "v2_shop_icons_3x3_1795769840703.jpg"))
    ixs, iys = find_grid_splits(icons_src, 3, 3)
    icon_names = [
        ["dish_burger", "dish_fries", "dish_nuggets"],
        ["dish_wrap", "dish_soda", "dish_supreme"],
        ["coin_shell", "badge_crisp", "tray_wood"],
    ]
    for r in range(3):
        for c in range(3):
            cell = icons_src.crop((ixs[c], iys[r], ixs[c + 1], iys[r + 1]))
            keyed = remove_gray_bg(cell, bg_tol=22, chroma_tol=18)
            final = fit_square_centered(keyed, 112, pad=8)
            name = icon_names[r][c]
            final.save(os.path.join(OUT_DIR, f"{name}.png"))
            preview_items.append((name, final))
            print(f"[OK] {name}.png {final.size}")

    # 3. 厨具工位 2x2 -> 196x196 底部对齐
    st_src = Image.open(os.path.join(ART_DIR, "v2_shop_stations_2x2_1795769879682.jpg"))
    sxs, sys_ = find_grid_splits(st_src, 2, 2)
    st_names = [
        ["station_fryer_1", "station_fryer_2"],
        ["station_board", "station_soda"],
    ]
    raw_st = []
    for r in range(2):
        for c in range(2):
            cell = st_src.crop((sxs[c], sys_[r], sxs[c + 1], sys_[r + 1]))
            # 油炸锅内部有银灰金属面，略收紧内部洞穴校验避免误伤金属块
            raw_st.append((st_names[r][c], remove_gray_bg(cell, bg_tol=20, chroma_tol=16, internal_tol=8, internal_min_area=32)))
    aligned_st = fit_pair_bottom_aligned([p[1] for p in raw_st], 196, 184, pad_x=10, pad_y=8)
    for (name, _), final in zip(raw_st, aligned_st):
        final.save(os.path.join(OUT_DIR, f"{name}.png"))
        preview_items.append((name, final))
        print(f"[OK] {name}.png {final.size}")

    # 4. 店员动作 2x2 -> 184x212 底部对齐
    crew_src = Image.open(os.path.join(ART_DIR, "v2_shop_crew_2x2_1795769904669.jpg"))
    cxs, cys = find_grid_splits(crew_src, 2, 2)
    crew_names = [
        ["crew_welcome", "crew_cook"],
        ["crew_serve", "crew_cheer"],
    ]
    raw_crew = []
    for r in range(2):
        for c in range(2):
            cell = crew_src.crop((cxs[c], cys[r], cxs[c + 1], cys[r + 1]))
            raw_crew.append((crew_names[r][c], remove_gray_bg(cell, bg_tol=22, chroma_tol=18)))
    aligned_crew = fit_pair_bottom_aligned([p[1] for p in raw_crew], 184, 212, pad_x=10, pad_y=8)
    for (name, _), final in zip(raw_crew, aligned_crew):
        final.save(os.path.join(OUT_DIR, f"{name}.png"))
        preview_items.append((name, final))
        print(f"[OK] {name}.png {final.size}")

    # 5. 顾客 A 组 3行2列 -> 每位顾客 Wait+Eat 统一比例底部对齐
    ca_src = Image.open(os.path.join(ART_DIR, "v2_shop_customers_a_3x2_1795769941467.jpg"))
    axs, ays = find_grid_splits(ca_src, 2, 3)
    ca_rows = ["seahorse", "turtle", "jelly"]
    for r, cname in enumerate(ca_rows):
        pair = []
        for c in range(2):
            cell = ca_src.crop((axs[c], ays[r], axs[c + 1], ays[r + 1]))
            pair.append(remove_gray_bg(cell, bg_tol=22, chroma_tol=18))
        aligned = fit_pair_bottom_aligned(pair, 192, 192, pad_x=10, pad_y=8)
        for suffix, final in zip(("wait", "eat"), aligned):
            fname = f"cust_{cname}_{suffix}"
            final.save(os.path.join(OUT_DIR, f"{fname}.png"))
            preview_items.append((fname, final))
            print(f"[OK] {fname}.png {final.size}")

    # 6. 顾客 B 组 2行2列
    cb_src = Image.open(os.path.join(ART_DIR, "v2_shop_customers_b_2x2_v2_1795769957343.jpg"))
    bxs, bys = find_grid_splits(cb_src, 2, 2)
    cb_rows = ["shark", "blackwhale"]
    for r, cname in enumerate(cb_rows):
        pair = []
        for c in range(2):
            cell = cb_src.crop((bxs[c], bys[r], bxs[c + 1], bys[r + 1]))
            keyed = remove_gray_bg(cell, bg_tol=22, chroma_tol=18)
            pair.append(keyed)
        aligned = fit_pair_bottom_aligned(pair, 204, 204, pad_x=10, pad_y=8)
        for suffix, final in zip(("wait", "eat"), aligned):
            fname = f"cust_{cname}_{suffix}"
            final.save(os.path.join(OUT_DIR, f"{fname}.png"))
            preview_items.append((fname, final))
            print(f"[OK] {fname}.png {final.size}")

    build_contact_preview(preview_items, PREVIEW_PATH)
    print(f"[OK] 拼图预览已保存: {PREVIEW_PATH} (共 {len(preview_items)} 枚透明精灵)")


if __name__ == "__main__":
    main()
