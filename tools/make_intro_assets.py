#!/usr/bin/env python3
"""生成开场大片（OpeningIntro）专用的 5 份视效资源 → `sprites/intro/*.png`。

严格保持与《深海鲸鱼娘·跑酷》2.5 头身萌系像素画风 100% 一致：
  1. `title_splash_2x.png`  (2560x1440 RGB) —— 2 倍高清过渡定格立绘（微推不闪烁）
  2. `chaser_wipe_rush.png` (~897x867 RGBA)  —— 原彩萌系黑鲸娘超近景搞笑飞扑特写（净边去灰晕 + 微弱水光轮廓）
  3. `chaser_wipe_wave.png` (1600x720 RGBA)  —— 紧随其后的碧蓝深海像素浪墙 + 晶莹气泡水花擦屏遮罩
  4. `fg_kelp_strip.png`    (1536x256 RGBA)  —— 超近景高速飞掠深海海藻条（无缝循环 + 横向动感模糊）
  5. `intro_horizon_bg.png` (1920x720 RGB)   —— 远景深海光柱、远山岩壁与平坦海底跑道（真岩纹理 + 无缝循环）

用法：
  python tools/make_intro_assets.py
"""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chaser_prep as cp

SRC_COVER = "image/title_cover/title_screen_pixel_art.png"
SRC_CHASER_BITE = "image/boss/pixel art/咬击.png"
SRC_ROCK = "image/background/rock_src.jpg"
OUT_DIR = "sprites/intro"


def _ensure_out() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)


# ---------------------------------------------------------------- 0. 周期性连续噪声工具
def periodic_fbm_1d(width: int, octaves: int = 5, base_freq: int = 2, seed: int = 42) -> np.ndarray:
    """在 [0, width) 上生成左右首尾 100% 连续的一维周期 fBM（三角级数叠加）。"""
    rng = np.random.default_rng(seed)
    x = np.linspace(0.0, 2.0 * math.pi, width, endpoint=False)
    signal = np.zeros(width, dtype=np.float64)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        k = base_freq * (2 ** o)
        phase1 = rng.uniform(0, 2 * math.pi)
        phase2 = rng.uniform(0, 2 * math.pi)
        signal += amp * (0.65 * np.sin(k * x + phase1) + 0.35 * np.cos((k + 1) * x + phase2))
        norm += amp
        amp *= 0.52
    return signal / max(1e-6, norm)


def periodic_fbm_2d(w: int, h: int, scales=(4, 8, 16), seed: int = 7) -> np.ndarray:
    """生成横向 100% 无缝平铺的二维噪声图（范围 [0, 1]）。"""
    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for s in scales:
        gh = max(2, int(round(h / (w / float(s)))))
        gw = max(2, int(s))
        grid = rng.uniform(0.0, 1.0, (gh, gw)).astype(np.float32)
        # 横向首尾拼接 3 份，缩放后裁中心，确保 X 方向接缝导数也平滑
        tiled = np.concatenate([grid, grid, grid], axis=1)
        im_small = Image.fromarray((tiled * 255.0).astype(np.uint8), mode="L")
        im_big = im_small.resize((w * 3, h), Image.BICUBIC)
        mid = np.asarray(im_big, dtype=np.float32)[:, w:w * 2] / 255.0
        acc += mid * amp
        total += amp
        amp *= 0.5
    acc /= max(1e-6, total)
    return np.clip(acc, 0.0, 1.0)


# ---------------------------------------------------------------- 1. 2x 高清封面立绘
def build_title_splash_2x() -> None:
    W, H = 2560, 1440
    im = Image.open(SRC_COVER).convert("RGB")
    sw, sh = im.size
    scale = max(W / sw, H / sh)
    nw, nh = round(sw * scale), round(sh * scale)
    im2 = im.resize((nw, nh), Image.LANCZOS)
    left = (nw - W) // 2
    top = (nh - H) // 2
    im3 = im2.crop((left, top, left + W, top + H))
    # 极克制微锐化：微推缩放时不糊且无白边振铃
    im3 = im3.filter(ImageFilter.UnsharpMask(radius=0.9, percent=28, threshold=3))
    out_path = os.path.join(OUT_DIR, "title_splash_2x.png")
    im3.save(out_path, optimize=True)
    print(f"  [OK] {out_path:<38} {im3.size} (源 {sw}x{sh} 精准同口径裁切)")


# ---------------------------------------------------------------- 2. 原彩萌系黑鲸娘超近景贴脸飞扑（源自高精 咬击.png 第 2 帧）
def build_chaser_wipe_rush() -> None:
    """从高精原画 `咬击.png` 提取第 2 帧飞扑咬击姿，保留 100% 原彩呆萌配色 (~897x867 RGBA)。

    设计规范（改法 A · 0 恐怖感）：
      · 完全保留粉嫩腮红、水润大眼、可爱“嗷呜”张嘴与黑白女仆装原色（绝不做黑化发光鬼眼）
      · 精准剔除灰底残留的 1px 外缘灰晕，并按亮蕾丝/暗轮廓分别提纯，叠在亮海蓝水上干净无脏边
      · 顶部与右前迎光轮廓轻点极淡海水蓝青高光，整数 3× 最近邻放大匹配像素锐利质感
    """
    im = Image.open(SRC_CHASER_BITE).convert("RGB")
    bg = cp.bg_color(im)
    outside = cp.build_outside(im, bg, tol=14)
    w0, h0 = im.size
    alpha_all = cp.raw_alpha(im, outside, bg, w0, h0, edge_full=24)
    rgba = im.convert("RGBA")
    rgba.putalpha(Image.frombytes("L", (w0, h0), bytes(alpha_all)))
    cells = cp.find_cells(alpha_all, w0, h0, 4, 1)
    cell = rgba.crop(cells[1])
    bb = cell.getbbox()
    if bb:
        cell = cell.crop(bb)

    arr = np.asarray(cell, dtype=np.float32)
    h, w, _ = arr.shape
    a_raw = arr[:, :, 3]

    # 只保留清晰实心主体（清除 gray 边带 1px 灰碎点，保留呆毛/鞋/尾尖完整性）
    # 同时抠掉左上方飘发卷曲环内部被围住的 #6d6d6c 纯背景小孔 (x:68..94, y:102..122)
    fg_bin = a_raw >= 175.0
    arr_rgb_int = arr[:, :, :3].astype(int)
    bg_arr = np.array(bg, dtype=int)[None, None, :]
    in_curl_hole = np.zeros((h, w), dtype=bool)
    in_curl_hole[102:122, 68:94] = (
        np.max(np.abs(arr_rgb_int[102:122, 68:94] - bg_arr), axis=2) <= 9
    )
    fg_bin &= (~in_curl_hole)
    lbl, nfeat = ndimage.label(fg_bin, structure=np.ones((3, 3), dtype=int))
    if nfeat > 0:
        counts = np.bincount(lbl.ravel())
        counts[0] = 0
        fg_bin = (lbl == int(np.argmax(counts)))

    out_rgb = arr[:, :, :3].copy()
    r, g, b = out_rgb[:, :, 0], out_rgb[:, :, 1], out_rgb[:, :, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    chroma = np.max(out_rgb, axis=2) - np.min(out_rgb, axis=2)

    # 净化最外圈 1px 像素：把从原图 #6e6d6c 中灰背景沾到的灰污染推向纯净描边/纯白蕾丝
    fg_pad = np.pad(fg_bin, 1, mode="constant", constant_values=False)
    is_outer1 = fg_bin & (
        (~fg_pad[:-2, 1:-1]) | (~fg_pad[2:, 1:-1]) | (~fg_pad[1:-1, :-2]) | (~fg_pad[1:-1, 2:])
    )
    white_lace_edge = is_outer1 & (lum > 165.0) & (chroma < 28.0)
    dark_ink_edge = is_outer1 & (~white_lace_edge) & (lum < 145.0)

    out_rgb[white_lace_edge] = np.clip(
        out_rgb[white_lace_edge] * 0.45 + np.array([132.0, 138.0, 145.0]), 0.0, 255.0
    )
    out_rgb[dark_ink_edge] = np.clip(
        out_rgb[dark_ink_edge] * 0.55 + np.array([10.0, 16.0, 28.0]), 0.0, 255.0
    )

    # 仅在右/上迎光边轻微缀一丁点海蓝空气光感 (16%)，让人物融进海底水色而不失任何原色温暖感
    rim_top_right = fg_bin & ((~fg_pad[:-2, 1:-1]) | (~fg_pad[1:-1, 2:]))
    out_rgb[rim_top_right] = np.clip(
        out_rgb[rim_top_right] * 0.84 + np.array([32.0, 155.0, 205.0]) * 0.16, 0.0, 255.0
    )

    out_rgba = np.dstack([
        np.clip(out_rgb, 0, 255).astype(np.uint8),
        np.where(fg_bin, 255, 0).astype(np.uint8),
    ])
    small_im = Image.fromarray(out_rgba, mode="RGBA")
    big_im = small_im.resize((w * 3, h * 3), Image.NEAREST)
    out_path = os.path.join(OUT_DIR, "chaser_wipe_rush.png")
    big_im.save(out_path, optimize=True)
    print(f"  [OK] {out_path:<38} {big_im.size} RGBA (原彩萌系贴脸飞扑 | 3x像素锐利净边)")


# ---------------------------------------------------------------- 3. 深海像素涡流浪墙 + 气泡潮汐遮罩
def _stamp_pixel_bubble(draw: ImageDraw.ImageDraw, cx: int, cy: int, rad: int, ring_col: tuple, hi_col: tuple) -> None:
    """绘制与 make_fx.py 同源的像素化亮青圆气泡（通透环边 + 极淡内填 + 左上角晶莹高光点）。"""
    box = [cx - rad, cy - rad, cx + rad, cy + rad]
    fill_c = (ring_col[0] // 2, ring_col[1] // 2, min(255, ring_col[2]), 22)
    draw.ellipse(box, fill=fill_c, outline=ring_col, width=max(1, rad // 5))
    hx = cx - max(1, int(rad * 0.40))
    hy = cy - max(1, int(rad * 0.40))
    hs = max(1, rad // 5)
    draw.rectangle([hx - hs, hy - hs, hx + hs, hy + hs], fill=hi_col)


def build_chaser_wipe_wave() -> None:
    """生成紧随黑鲸娘身后横扫的深海像素海浪 + 爆裂气泡 Wipe 遮罩 (1600x720 RGBA)。

    结构（贴脸从左往右掀开画面）：
      · 中段 (x ~ 520..1240)：100% 垂直闭屏深海涡流蓝黑水幕（高速横向水波流线纹，保证幕后切换零穿透）
      · 右缘 (x ~ 1240..1500)：隐于飞扑黑鲸娘身后方的前锋弧浪
      · 左缘 (x ~ 80..520)：「掀开浪幕」的一瞬间 ——
        2px 像素阶梯质感的多层清澈水花浪峰 + 85 颗纯透亮青空心圆气泡与疾驰水花流线！
    """
    W, H = 1600, 720
    PW, PH = W // 2, H // 2
    y = np.linspace(0.0, 1.0, PH, dtype=np.float32)[:, None]
    x = np.arange(PW, dtype=np.float32)[None, :]

    wave_noise = periodic_fbm_2d(PW, PH, scales=(5, 10, 20), seed=412)
    # 水平拉伸的高速水流纹（横向频率低、纵向细密）
    flow_noise = periodic_fbm_2d(PW // 4, PH, scales=(4, 12, 28), seed=618)
    flow_noise = np.asarray(
        Image.fromarray((flow_noise * 255).astype(np.uint8), "L").resize((PW, PH), Image.BILINEAR),
        dtype=np.float32,
    ) / 255.0

    # 左侧掀开浪峰：轻斜向浪涌（上略超前、下微拖后）配双峰翻卷感
    trail_x = (
        255.0 - 82.0 * y
        + 26.0 * np.sin(y * math.pi * 2.4 + 0.5)
        + 18.0 * np.sin(y * math.pi * 5.6 - 0.2)
        + 36.0 * (wave_noise - 0.5)
    )
    # 右侧前锋（宽松拉宽确保中段有极宽的 100% 实心闭屏区）
    lead_x = (
        720.0 + 32.0 * np.sin(y * math.pi * 2.0)
        - 26.0 * (wave_noise - 0.5)
    )

    dist_l = x - trail_x
    dist_r = lead_x - x
    inside = (dist_l >= 0.0) & (dist_r >= 0.0)

    # 内部高速水流条纹：横贯的明快深海蔚蓝流动丝带（衬托原彩黑鲸娘的墨发黑裙不压黑）
    streak_band = np.power(flow_noise, 1.45)
    swirl = 0.55 + 0.45 * np.sin(y * 18.0 + flow_noise * 6.0)
    water_k = np.clip(0.35 * streak_band + 0.65 * swirl * flow_noise, 0.0, 1.0)
    r_ch = 11.0 + 18.0 * water_k
    g_ch = 44.0 + 62.0 * water_k
    b_ch = 84.0 + 86.0 * water_k

    # 左缘三层像素浪花边（外层深海青 -> 中层亮水青 -> 边缘清亮泡沫浪白）
    foam_outer = inside & (dist_l < 18.0 + 7.0 * (flow_noise - 0.5))
    foam_mid = inside & (dist_l < 8.5 + 4.0 * (flow_noise - 0.5))
    foam_crest = inside & (dist_l < 3.2 + 2.0 * (flow_noise - 0.5))

    r_ch = np.where(foam_outer, 28.0, r_ch)
    g_ch = np.where(foam_outer, 122.0, g_ch)
    b_ch = np.where(foam_outer, 174.0, b_ch)

    r_ch = np.where(foam_mid, 78.0, r_ch)
    g_ch = np.where(foam_mid, 206.0, g_ch)
    b_ch = np.where(foam_mid, 238.0, b_ch)

    r_ch = np.where(foam_crest, 208.0, r_ch)
    g_ch = np.where(foam_crest, 248.0, g_ch)
    b_ch = np.where(foam_crest, 255.0, b_ch)

    lead_rim = inside & (dist_r < 6.0)
    r_ch = np.where(lead_rim, 34.0, r_ch)
    g_ch = np.where(lead_rim, 128.0, g_ch)
    b_ch = np.where(lead_rim, 178.0, b_ch)

    rgba_half = np.dstack([
        np.clip(r_ch, 0, 255).astype(np.uint8),
        np.clip(g_ch, 0, 255).astype(np.uint8),
        np.clip(b_ch, 0, 255).astype(np.uint8),
        np.where(inside, 255, 0).astype(np.uint8),
    ])
    wave_im = Image.fromarray(rgba_half, mode="RGBA")

    # ★ 在独立透明叠层绘制气泡与水流细线，再用 alpha_composite 叠上：绝不把实心闭屏区挖洞！
    bubble_layer = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bubble_layer)
    rng = np.random.default_rng(1116)

    # 1. 浪内高速横扫水波亮丝线（增强水墙飞驰感）
    for _ in range(36):
        sy = int(rng.uniform(14, PH - 14))
        sx = int(rng.uniform(295, 650))
        slen = int(rng.uniform(24, 72))
        al = int(rng.uniform(45, 110))
        bd.line([(sx, sy), (sx + slen, sy)], fill=(86, 206, 242, al), width=1)

    # 2. 沿左侧掀开浪峰飞散出的晶莹空心小气泡 + 细碎水沫
    for _ in range(88):
        yn = float(rng.uniform(0.02, 0.98))
        sy = int(yn * PH)
        wave_edge = int(
            255.0 - 82.0 * yn
            + 26.0 * math.sin(yn * math.pi * 2.4 + 0.5)
            + 18.0 * math.sin(yn * math.pi * 5.6 - 0.2)
        )
        offset = int(rng.exponential(scale=28.0))
        sx = wave_edge - offset
        if sx < 6 or sx >= PW - 8:
            continue
        rad = int(rng.choice([2, 3, 4, 5, 6, 8, 10]))
        if offset < 12 and rng.random() < 0.40:
            # 紧贴浪尖的小朵清亮水沫珠
            bd.ellipse([sx - rad, sy - rad, sx + rad, sy + rad], fill=(140, 232, 252, 185), outline=(220, 252, 255, 220))
        else:
            _stamp_pixel_bubble(bd, sx, sy, rad, (110, 226, 250, 225), (242, 255, 255, 245))

    # 3. 浪体内部的深水暗色微泡（叠色渲染，100% 保留下方实心不透明！）
    for _ in range(32):
        sy = int(rng.uniform(16, PH - 16))
        sx = int(rng.uniform(315, 655))
        rad = int(rng.choice([2, 3, 5, 6]))
        _stamp_pixel_bubble(bd, sx, sy, rad, (68, 178, 220, 145), (175, 238, 255, 195))

    wave_im = Image.alpha_composite(wave_im, bubble_layer)

    # 2x 最近邻放大到 1600x720，保持干净 crisp 的 2px 像素粒子与浪峰阶梯感
    out_im = wave_im.resize((W, H), Image.NEAREST)

    final_arr = np.asarray(out_im)
    col_min = final_arr[:, :, 3].min(axis=0)
    solid_cols = int(np.sum(col_min >= 250))
    out_path = os.path.join(OUT_DIR, "chaser_wipe_wave.png")
    out_im.save(out_path, optimize=True)
    print(f"  [OK] {out_path:<38} {out_im.size} RGBA (像素深海浪墙 + 晶莹气泡 | 闭屏宽={solid_cols}px)")


# ---------------------------------------------------------------- 4. 前景高速飞掠海藻条（无缝循环）
def _draw_kelp_blade(draw: ImageDraw.ImageDraw, W: int, H: int, base_x: float,
                     height: float, lean: float, base_w: float, phase: float,
                     color_fill: tuple, color_edge: tuple, color_rim: tuple) -> None:
    """绘制一株顺滑 S 型摆动的有机海藻叶片（36 步细腻采样），并在 X±W 同步镜像保证零接缝。"""
    steps = 36
    pts_left = []
    pts_right = []
    # 从底部外侧 +28px 向上长出，避免在底边切出平直线段
    start_y = H + 28.0
    for k in range(steps + 1):
        t = k / float(steps)
        cy = start_y - t * (height + 28.0)
        bend = -lean * (t ** 1.48) + math.sin(t * 6.8 + phase) * (base_w * 0.44 * t)
        cx = base_x + bend
        wiggle = 1.0 + 0.14 * math.sin(t * 16.0 + phase * 1.7)
        half_w = base_w * (0.48 + 0.62 * math.sin(math.pi * (0.10 + 0.88 * t))) * (1.0 - 0.88 * (t ** 2.1)) * wiggle
        half_w = max(0.8, half_w)
        pts_left.append((cx - half_w, cy))
        pts_right.append((cx + half_w, cy))

    poly = pts_left + list(reversed(pts_right))
    for shift in (-W, 0, W):
        shifted = [(px + shift, py) for px, py in poly]
        draw.polygon(shifted, fill=color_fill, outline=color_edge)
        rim_pts = [(px + shift - 1.5, py) for px, py in pts_right[5:-3]]
        if len(rim_pts) >= 2:
            draw.line(rim_pts, fill=color_rim, width=max(2, int(base_w * 0.15)))


def build_fg_kelp_strip() -> None:
    """生成 1536x256 高度动态模糊的无缝前景深海海藻条（无平直底条、细腻叶束 + 动感拉丝）。"""
    W, H = 1536, 256
    SS = 2
    sw, sh = W * SS, H * SS
    canvas = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    rng = np.random.default_rng(1116)
    # 4 个深度梯度：含远底暗影草、中层厚叶、近景纤细长丝叶梢，根部有机起伏铺满下缘
    layers = [
        # (count, h_range, lean_range, w_range, fill, outline, rim)
        (58, (150, 380), (140, 310), (20, 40), (4, 16, 26, 235), (2, 7, 13, 245), (10, 48, 66, 170)),
        (46, (125, 320), (125, 270), (16, 34), (9, 40, 50, 245), (3, 13, 20, 250), (22, 92, 110, 205)),
        (38, (95, 260),  (105, 235), (14, 28), (16, 68, 78, 250), (5, 20, 30, 255), (52, 182, 206, 225)),
        # 超纤细高速水草丝（加强速度拉丝感）
        (55, (70, 290),  (160, 350), (6, 12),  (14, 62, 74, 235), (4, 18, 26, 245), (72, 210, 230, 215)),
    ]
    for count, hr, lr, wr, fill, edge, rim in layers:
        for _ in range(count):
            bx = rng.uniform(0.0, sw)
            bh = rng.uniform(*hr)
            blean = rng.uniform(*lr)
            bw = rng.uniform(*wr)
            ph = rng.uniform(0.0, 2.0 * math.pi)
            _draw_kelp_blade(draw, sw, sh, bx, bh, blean, bw, ph, fill, edge, rim)

    # 底部有机的低矮暗影起伏波带（替代平直方框），托住草根且保证接缝完全平滑
    bed_pts = []
    for xk in range(0, sw + 16, 16):
        ang = (xk / float(sw)) * 2.0 * math.pi
        by = sh - 18.0 - 10.0 * math.sin(ang * 5.0 + 0.4) - 6.0 * math.cos(ang * 11.0)
        bed_pts.append((float(xk), by))
    bed_poly = [(0.0, float(sh + 10))] + bed_pts + [(float(sw), float(sh + 10))]
    draw.polygon(bed_poly, fill=(3, 12, 20, 255))

    arr = np.asarray(canvas, dtype=np.float32)
    a = arr[:, :, 3:4] / 255.0
    premul = arr[:, :, :3] * a
    full_premul = np.concatenate([premul, arr[:, :, 3:4]], axis=2)

    k_len = 17  # 2x 下 17px 横向疾驰残影 -> 1x ~8.5px 强速度感
    kernel = np.linspace(0.22, 1.0, k_len, dtype=np.float32)
    kernel /= kernel.sum()
    blurred = ndimage.convolve1d(full_premul, kernel, axis=1, mode="wrap")

    a_out = np.clip(blurred[:, :, 3], 0.0, 255.0)
    rgb_out = np.where(
        a_out[:, :, None] > 1.5,
        blurred[:, :, :3] / np.maximum(a_out[:, :, None] / 255.0, 0.01),
        0.0,
    )
    res_arr = np.dstack([
        np.clip(rgb_out, 0, 255).astype(np.uint8),
        a_out.astype(np.uint8),
    ])
    out_im = Image.fromarray(res_arr, mode="RGBA").resize((W, H), Image.LANCZOS)

    oa = np.asarray(out_im, dtype=np.float32)
    seam_diff = float(np.mean(np.abs(oa[:, 0, 3] - oa[:, -1, 3])))
    out_path = os.path.join(OUT_DIR, "fg_kelp_strip.png")
    out_im.save(out_path, optimize=True)
    print(f"  [OK] {out_path:<38} {out_im.size} RGBA (精细流线草叶 + 动糊 | 接缝Alpha差={seam_diff:.1f})")


# ---------------------------------------------------------------- 5. 远景深海山脊横卷轴背景
def _tileable_rock_layer(w: int, h: int) -> np.ndarray:
    """读取 rock_src.jpg 做**整除宽度的首尾无缝交叉淡化 + 垂直镜像拼接**，确保横向接缝差 0.00。"""
    im = Image.open(SRC_ROCK).convert("RGB")
    # 目标单块有效宽选 960 (恰为 1920 的 1/2 整数倍!)：从 1088 缩放到宽后交叉淡化 128px 得 eff_w=960
    tw, th = 1088, h
    im = im.resize((tw, th), Image.LANCZOS)
    arr = np.asarray(im, dtype=np.float32)
    fade = 128
    eff_w = tw - fade  # = 960，严格整除 1920！
    t = np.linspace(0.0, 1.0, fade, dtype=np.float32)[None, :, None]
    out_tile = arr[:, :eff_w, :].copy()
    out_tile[:, :fade, :] = arr[:, :fade, :] * t + arr[:, eff_w:, :] * (1.0 - t)
    tiled = np.tile(out_tile, (1, math.ceil(w / float(eff_w)), 1))
    return tiled[:, :w, :]


def build_intro_horizon_bg() -> None:
    """生成 1920x720 零接缝深海远景横卷轴：上方神光海面 + 圆润深海山脊 + 平坦沙石跑道。"""
    W, H = 1920, 720
    x = np.arange(W, dtype=np.float32)[None, :]
    y = np.arange(H, dtype=np.float32)[:, None]
    yn = y / float(H - 1)

    # 1. 上层：取自封面同款深海光色渐变
    top_col = np.array([154.0, 234.0, 246.0], dtype=np.float32)
    mid_col = np.array([28.0, 148.0, 202.0], dtype=np.float32)
    bot_col = np.array([14.0, 72.0, 118.0], dtype=np.float32)

    k_up = np.clip(yn / 0.42, 0.0, 1.0)[:, :, None]
    k_dn = np.clip((yn - 0.42) / 0.58, 0.0, 1.0)[:, :, None]
    water = np.where(
        yn[:, :, None] < 0.42,
        top_col * (1.0 - k_up) + mid_col * k_up,
        mid_col * (1.0 - k_dn) + bot_col * k_dn,
    )

    # 软羽化斜向深海神光光柱（严格周期绕 W 闭合，温和斜率）
    theta = (x - y * 0.52) * (2.0 * math.pi / float(W))
    rays = (
        0.52 * np.power(np.maximum(0.0, np.sin(theta * 3.0 + 0.3)), 2.2)
        + 0.34 * np.power(np.maximum(0.0, np.sin(theta * 5.0 + 1.7)), 2.6)
        + 0.22 * np.power(np.maximum(0.0, np.sin(theta * 7.0 + 3.0)), 3.0)
    )
    ray_fade_y = np.exp(-((yn - 0.12) / 0.46) ** 2) * (1.0 - np.clip((yn - 0.56) / 0.32, 0.0, 1.0))
    ray_mask = (rays * ray_fade_y)[:, :, None]
    water = np.clip(water + np.array([92.0, 126.0, 132.0], dtype=np.float32) * ray_mask * 0.46, 0.0, 255.0)

    rock_tex = _tileable_rock_layer(W, H)
    rock_lum = (0.299 * rock_tex[:, :, 0] + 0.587 * rock_tex[:, :, 1] + 0.114 * rock_tex[:, :, 2])[:, :, None]
    rock_detail = (rock_lum - np.mean(rock_lum)) / 24.0

    # 2. 远景海沟山脊：改用平滑缓坡 (0.5 + 0.5*fbm)，杜绝尖锐 V 型谷与硬边
    far_raw = periodic_fbm_1d(W, octaves=6, base_freq=2, seed=11)
    far_curve = 390.0 - 82.0 * np.power(np.clip(0.55 + 0.65 * far_raw, 0.0, 1.0), 1.35)
    far_ridge_mask = np.clip((y - far_curve[None, :]) / 5.0, 0.0, 1.0)[:, :, None]
    far_rock_col = np.array([22.0, 88.0, 132.0], dtype=np.float32) + rock_detail * np.array([6.0, 14.0, 20.0], dtype=np.float32)
    mist_k = np.clip((y - 340.0) / 160.0, 0.0, 1.0)[:, :, None] * 0.48
    far_rock_col = far_rock_col * (1.0 - mist_k) + np.array([24.0, 108.0, 154.0], dtype=np.float32) * mist_k
    canvas = water * (1.0 - far_ridge_mask) + far_rock_col * far_ridge_mask

    # 3. 中远景岩礁剪影：柔顺起伏 + 淡淡海雾沉底（去掉刺眼硬边亮线）
    mid_raw = periodic_fbm_1d(W, octaves=6, base_freq=3, seed=29)
    mid_curve = 448.0 - 52.0 * np.power(np.clip(0.55 + 0.65 * mid_raw, 0.0, 1.0), 1.3)
    mid_dist = y - mid_curve[None, :]
    mid_mask = np.clip(mid_dist / 4.0, 0.0, 1.0)[:, :, None]
    mid_rim = np.exp(-((mid_dist - 2.0) / 4.5) ** 2)[:, :, None]
    # 底部淡雾融合，避免岩礁脚底接缝线太生硬
    mid_base_mist = np.clip((y - 460.0) / 65.0, 0.0, 1.0)[:, :, None] * 0.45
    mid_rock_col = (
        np.array([15.0, 56.0, 90.0], dtype=np.float32)
        + rock_detail * np.array([8.0, 18.0, 24.0], dtype=np.float32)
        + mid_rim * np.array([16.0, 48.0, 68.0], dtype=np.float32)
    )
    mid_rock_col = mid_rock_col * (1.0 - mid_base_mist) + np.array([26.0, 74.0, 104.0], dtype=np.float32) * mid_base_mist
    canvas = canvas * (1.0 - mid_mask) + mid_rock_col * mid_mask

    # 3.5 地平线远岸珊瑚/海草迷雾簇：柔化直线地平线，并与封面图风格一致
    tuft_raw = periodic_fbm_1d(W, octaves=7, base_freq=18, seed=67)
    tuft_h = np.power(np.clip(0.45 + 0.85 * tuft_raw, 0.0, 1.0), 1.9) * 26.0
    tuft_curve = 516.0 - tuft_h
    tuft_mask = np.clip((y - tuft_curve[None, :]) / 4.0, 0.0, 1.0)[:, :, None] * np.clip((526.0 - y) / 14.0, 0.0, 1.0)[:, :, None]
    tuft_col = np.array([17.0, 62.0, 92.0], dtype=np.float32) + rock_detail * np.array([4.0, 10.0, 14.0], dtype=np.float32)
    canvas = canvas * (1.0 - tuft_mask * 0.78) + tuft_col * (tuft_mask * 0.78)

    # 4. 底部平坦海底跑道：同步封面深海青石板色阶，不再灰白刺眼
    floor_curve = 518.0 + 4.5 * periodic_fbm_1d(W, octaves=4, base_freq=3, seed=53)
    f_dist = y - floor_curve[None, :]
    floor_mask = np.clip(f_dist / 9.0, 0.0, 1.0)[:, :, None]
    fk = np.clip(f_dist / (H - 515.0), 0.0, 1.0)[:, :, None]
    sand_base = (
        np.array([40.0, 86.0, 114.0], dtype=np.float32) * (1.0 - fk)
        + np.array([14.0, 36.0, 56.0], dtype=np.float32) * fk
    )
    caustics = periodic_fbm_2d(W, H, scales=(10, 22), seed=88)
    caustic_glow = np.power(np.clip(caustics - 0.54, 0.0, 0.46) * 2.15, 1.55)[:, :, None] * (1.0 - fk * 0.70)
    floor_col = (
        sand_base
        + rock_detail * np.array([8.0, 15.0, 21.0], dtype=np.float32) * (0.35 + 0.65 * fk)
        + caustic_glow * np.array([26.0, 68.0, 92.0], dtype=np.float32)
    )
    # 柔和青色海沙微光边（与水下光柱同色温）
    horizon_hi = np.exp(-((f_dist - 4.0) / 8.0) ** 2)[:, :, None]
    floor_col += horizon_hi * np.array([10.0, 34.0, 48.0], dtype=np.float32)
    canvas = canvas * (1.0 - floor_mask) + floor_col * floor_mask

    rng = np.random.default_rng(777)
    img = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img, "RGBA")
    for _ in range(55):
        px = float(rng.uniform(0, W))
        py = float(rng.uniform(40, 480))
        rad = float(rng.uniform(1.5, 4.0))
        al = int(rng.uniform(28, 72))
        for sh in (-W, 0, W):
            draw.ellipse([px + sh - rad, py - rad, px + sh + rad, py + rad], fill=(190, 245, 255, al))

    final_arr = np.asarray(img, dtype=np.float32)
    seam_err = float(np.mean(np.abs(final_arr[:, 0, :] - final_arr[:, -1, :])))
    out_path = os.path.join(OUT_DIR, "intro_horizon_bg.png")
    img.save(out_path, optimize=True)
    print(f"  [OK] {out_path:<38} {img.size} RGB (左右接缝差={seam_err:.2f})")


def main() -> None:
    _ensure_out()
    print("=" * 65)
    print("正在生成开场大片全套 5 份视效素材 → sprites/intro/")
    print("=" * 65)
    build_title_splash_2x()
    build_chaser_wipe_rush()
    build_chaser_wipe_wave()
    build_fg_kelp_strip()
    build_intro_horizon_bg()
    print("=" * 65)
    print("全部素材生成完毕！")
    print("=" * 65)


if __name__ == "__main__":
    main()
