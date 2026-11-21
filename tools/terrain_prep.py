#!/usr/bin/env python3
"""Deep-sea reef & sunken shipwreck tileset builder + 1:1 visual preview.

Generates:
  - sprites/terrain/fill_seamless.png     (256x256 RGB, X/Y seamless rock fill)
  - sprites/terrain/top_01..04.png        (64x48 RGBA, horizon aligned at y=14)
  - sprites/terrain/wall_l.png, wall_r.png (36x64 RGBA, vertically seamless)
  - sprites/terrain/corner_out_l.png, corner_out_r.png (40x48 RGBA)
  - sprites/terrain/corner_in_l.png, corner_in_r.png   (36x36 RGBA)
  - sprites/terrain/chasm_lip_l.png, chasm_lip_r.png   (76x96 RGBA)
  - sprites/bg/far_silhouettes.png        (1024x384 RGBA, horizontally seamless)

Renders a 1:1 preview image into:
  <artifact_dir>/terrain_preview_v1.png
plus a closer tileset diagnostic sheet into:
  <artifact_dir>/scratch/terrain_tiles_check.png
"""
import json
import math
import os
from collections import deque
from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RAW_EDGES = os.path.join(ROOT, "image", "terrain", "raw_terrain_edges.png")
RAW_SILHOUETTE = os.path.join(ROOT, "image", "terrain", "raw_bg_silhouette.png")
OUT_TERRAIN = os.path.join(ROOT, "sprites", "terrain")
OUT_BG = os.path.join(ROOT, "sprites", "bg")

ARTIFACT_DIR = os.path.join(ROOT, "tools", "_preview")
PREVIEW_PATH = os.path.join(ARTIFACT_DIR, "terrain_preview_v1.png")
ATLAS_CHECK_PATH = os.path.join(ARTIFACT_DIR, "scratch", "terrain_tiles_check.png")

# Shared geometry constants mirrored into TerrainChunk.gd in Step 2:
TILE = 64
SURFACE_OFFSET_Y = 14          # local y inside top_*, corner_out_*, chasm_lip_* == SURFACE_Y
FILL_INSET = 6                 # inset fill_seamless beneath solid crust/wall rims
WALL_SIZE = (36, 64)
WALL_R_CLIFF_X = 28
WALL_L_CLIFF_X = 8
CORNER_OUT_SIZE = (40, 48)
CORNER_OUT_R_CLIFF_X = 32
CORNER_OUT_L_CLIFF_X = 8
CORNER_IN_SIZE = (36, 36)
CORNER_IN_R_ANCHOR = (8, 22)   # (wall_x - 8, floor_y - 22)
CORNER_IN_L_ANCHOR = (28, 22)  # (wall_x - 28, floor_y - 22)
CHASM_LIP_SIZE = (76, 96)
CHASM_LIP_R_CLIFF_X = 46       # rock cliff edge on right side of left platform
CHASM_LIP_L_CLIFF_X = 30       # rock cliff edge on left side of right platform


def lum709(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def clampi(v, lo=0, hi=255):
    return lo if v < lo else (hi if v > hi else int(round(v)))


def key_edges_bfs(im_rgb):
    """Remove flat dark-navy background via border BFS, preserving dark outlines."""
    w, h = im_rgb.size
    px = im_rgb.load()
    corners = [px[4, 4], px[w - 5, 4], px[4, h - 5], px[w - 5, h - 5]]
    bg = tuple(sum(c[i] for c in corners) / 4.0 for i in range(3))

    def bg_dist(c):
        return (
            abs(c[0] - bg[0]) * 1.1
            + abs(c[1] - bg[1]) * 1.0
            + abs(c[2] - bg[2]) * 1.15
        )

    visited = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_dist(px[x, y]) < 26:
                visited[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y][x] and bg_dist(px[x, y]) < 26:
                visited[y][x] = True
                q.append((x, y))

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                if bg_dist(px[nx, ny]) < 26:
                    visited[ny][nx] = True
                    q.append((nx, ny))

    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if visited[y][x]:
                op[x, y] = (0, 0, 0, 0)
            else:
                adj_bg = False
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and visited[ny][nx]:
                        adj_bg = True
                        break
                if adj_bg:
                    d = bg_dist((r, g, b))
                    if d < 42:
                        a = clampi((d - 16) / 26.0 * 255.0)
                        op[x, y] = (clampi(r * 0.7), clampi(g * 0.72), clampi(b * 0.78), a)
                    else:
                        op[x, y] = (r, g, b, 255)
                else:
                    op[x, y] = (r, g, b, 255)
    return out


def grade_terrain_rgba(im, brightness_scale=0.50, suppress_green=False):
    """Calibrate pixel colors into deep-sea hierarchy while preserving seaweed/barnacles/wood."""
    w, h = im.size
    out = im.copy()
    px = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            is_seaweed = (not suppress_green) and (g > r + 14) and (g >= b - 18) and (g > 75)
            is_barnacle = (not suppress_green) and (r > 130) and (b > 145) and abs(r - b) < 48 and (r + g + b > 410)
            is_plank = (r > b + 6 or abs(r - g) < 12) and (r > 55) and (b < r + 24) and not is_barnacle and (g < b + 12)

            if is_seaweed:
                nr = clampi(r * 0.62)
                ng = clampi(g * 0.68)
                nb = clampi(b * 0.68)
            elif is_barnacle:
                nr = clampi(r * 0.66)
                ng = clampi(g * 0.66)
                nb = clampi(b * 0.72)
            elif is_plank and (r - b > -6):
                avg = (r + g + b) / 3.0
                nr = clampi((r * 0.55 + avg * 0.45) * 0.54)
                ng = clampi((g * 0.55 + avg * 0.45) * 0.53)
                nb = clampi((b * 0.50 + avg * 0.50) * 0.58 + 4)
            else:
                lum = lum709(r, g, b)
                s = brightness_scale
                if lum > 135:
                    s *= 0.86
                elif lum < 45:
                    s *= 0.80
                nr = clampi(r * s * 0.76)
                # Suppress any accidental greenish moss cast inside solid rock fills
                gg = g * 0.85 if (suppress_green and g > b * 0.9) else g
                ng = clampi(gg * s * 0.90)
                nb = clampi(b * s * 1.04 + 3)
            px[x, y] = (nr, ng, nb, a)
    return out


def toroidal_seamless_tile(src_im, out_size=(256, 256), feather_frac=0.40):
    """Create an X/Y seamless tileable RGB texture using half-shift diamond blending."""
    w, h = out_size
    tile = src_im.convert("RGB").resize((w, h), Image.Resampling.LANCZOS)
    shifted = ImageChops.offset(tile, w // 2, h // 2)
    tp = tile.load()
    sp = shifted.load()
    out = Image.new("RGB", (w, h))
    op = out.load()
    for y in range(h):
        ny = abs((y / float(h - 1)) - 0.5) * 2.0
        wy = max(0.0, min(1.0, (1.0 - ny) / feather_frac))
        wy = wy * wy * (3.0 - 2.0 * wy)
        for x in range(w):
            nx = abs((x / float(w - 1)) - 0.5) * 2.0
            wx = max(0.0, min(1.0, (1.0 - nx) / feather_frac))
            wx = wx * wx * (3.0 - 2.0 * wx)
            w_orig = wx * wy
            c1 = tp[x, y]
            c2 = sp[x, y]
            op[x, y] = (
                clampi(c1[0] * w_orig + c2[0] * (1.0 - w_orig)),
                clampi(c1[1] * w_orig + c2[1] * (1.0 - w_orig)),
                clampi(c1[2] * w_orig + c2[2] * (1.0 - w_orig)),
            )
    return out


def build_fill_seamless(raw_edges_rgba):
    """Harvest clean rock-wall interiors (zero moss/seaweed!) into a non-mirrored X/Y seamless 256x256 RGB fill."""
    p1 = raw_edges_rgba.crop((80, 480, 268, 606)).convert("RGB")
    p2 = raw_edges_rgba.crop((775, 480, 948, 606)).convert("RGB")

    def clean_patch(im, w, h):
        im = im.resize((w, h), Image.Resampling.LANCZOS)
        px = im.load()
        vals_r, vals_g, vals_b = [], [], []
        for yy in range(h):
            for xx in range(w):
                r, g, b = px[xx, yy]
                if g > r + 10 and g >= b - 10:
                    px[xx, yy] = (clampi(r * 0.9), clampi(b * 0.85), clampi(b * 1.05))
                r, g, b = px[xx, yy]
                vals_r.append(r); vals_g.append(g); vals_b.append(b)
        return im, (sum(vals_r)/len(vals_r), sum(vals_g)/len(vals_g), sum(vals_b)/len(vals_b))

    p1, m1 = clean_patch(p1, 256, 256)
    p2, m2 = clean_patch(p2, 256, 256)
    px2 = p2.load()
    for yy in range(256):
        for xx in range(256):
            r, g, b = px2[xx, yy]
            px2[xx, yy] = (
                clampi(r + (m1[0] - m2[0])),
                clampi(g + (m1[1] - m2[1])),
                clampi(b + (m1[2] - m2[2])),
            )

    # Pure translational diamond cross-fade (NO mirroring, NO internal cut lines!):
    # Make p1 seamless with shifted(p1) -> seamless A; make p2 seamless with shifted(p2) -> seamless B;
    # then softly blend A with offset(B, 96, 112) in periodic cosine space so rock strata never repeat identically!
    a_tile = toroidal_seamless_tile(p1, (256, 256), feather_frac=0.45)
    b_tile = toroidal_seamless_tile(p2, (256, 256), feather_frac=0.45)
    b_off = ImageChops.offset(b_tile, 96, 112)
    ap = a_tile.load()
    bp = b_off.load()
    q = Image.new("RGB", (256, 256))
    qp = q.load()
    for y in range(256):
        cy = 0.5 + 0.5 * math.cos(2.0 * math.pi * y / 256.0)
        for x in range(256):
            cx = 0.5 + 0.5 * math.cos(2.0 * math.pi * x / 256.0)
            w_a = 0.20 + 0.60 * (cx * cy)
            c1, c2 = ap[x, y], bp[x, y]
            qp[x, y] = (
                clampi(c1[0] * w_a + c2[0] * (1.0 - w_a)),
                clampi(c1[1] * w_a + c2[1] * (1.0 - w_a)),
                clampi(c1[2] * w_a + c2[2] * (1.0 - w_a)),
            )

    graded = grade_terrain_rgba(q.convert("RGBA"), brightness_scale=0.39, suppress_green=True).convert("RGB")
    gp = graded.load()
    mean_c = (18.0, 33.0, 49.0)
    for y in range(256):
        for x in range(256):
            r, g, b = gp[x, y]
            gp[x, y] = (
                clampi(r * 0.72 + mean_c[0] * 0.28),
                clampi(g * 0.72 + mean_c[1] * 0.28),
                clampi(b * 0.72 + mean_c[2] * 0.28),
            )
    grain = graded.resize((128, 128), Image.Resampling.BOX).resize((256, 256), Image.Resampling.NEAREST)
    out = Image.blend(graded, grain, 0.70)
    return out


def remap_shelf_strip(patch_rgba, out_w, out_h, raw_back_y, raw_rim_y, target_back_y=8, target_rim_y=18):
    """Piecewise resample a ledge crop so its 2.5D top shelf maps cleanly onto [target_back_y .. target_rim_y]."""
    sw, sh = patch_rgba.size
    x_res = patch_rgba.resize((out_w, sh), Image.Resampling.LANCZOS)
    xp = x_res.load()
    out = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    op = out.load()

    def sample_y(x, sy_float):
        sy_float = max(0.0, min(sh - 1.001, sy_float))
        y0 = int(sy_float)
        y1 = min(sh - 1, y0 + 1)
        t = sy_float - y0
        c0 = xp[x, y0]
        c1 = xp[x, y1]
        a0, a1 = c0[3] / 255.0, c1[3] / 255.0
        a = a0 * (1 - t) + a1 * t
        if a < 0.02:
            return (0, 0, 0, 0)
        r = (c0[0] * a0 * (1 - t) + c1[0] * a1 * t) / a
        g = (c0[1] * a0 * (1 - t) + c1[1] * a1 * t) / a
        b = (c0[2] * a0 * (1 - t) + c1[2] * a1 * t) / a
        return (clampi(r), clampi(g), clampi(b), clampi(a * 255.0))

    scale_x = out_w / float(sw)
    under_scale_y = 0.44

    for y in range(out_h):
        if y < target_back_y:
            sy = raw_back_y - (target_back_y - y) / max(0.32, min(0.55, scale_x))
        elif y <= target_rim_y:
            t = (y - target_back_y) / float(max(1, target_rim_y - target_back_y))
            sy = raw_back_y + t * (raw_rim_y - raw_back_y)
        else:
            sy = raw_rim_y + (y - target_rim_y) / under_scale_y
        if sy < 0 or sy >= sh:
            continue
        for x in range(out_w):
            op[x, y] = sample_y(x, sy)
    return out


def feather_alpha_bottom(im, solid_end_y, fade_end_y):
    out = im.copy()
    px = out.load()
    w, h = out.size
    for y in range(solid_end_y, h):
        if y >= fade_end_y:
            t = 0.0
        else:
            k = (y - solid_end_y) / float(max(1, fade_end_y - solid_end_y))
            t = 1.0 - (k * k * (3.0 - 2.0 * k))
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, clampi(a * t))
    return out


def feather_alpha_horizontal(im, fade_from_x, fade_to_x, keep_left=True):
    out = im.copy()
    px = out.load()
    w, h = out.size
    lo = min(fade_from_x, fade_to_x)
    hi = max(fade_from_x, fade_to_x)
    for x in range(w):
        if keep_left:
            if x <= lo:
                t = 1.0
            elif x >= hi:
                t = 0.0
            else:
                k = (x - lo) / float(hi - lo)
                t = 1.0 - (k * k * (3.0 - 2.0 * k))
        else:
            if x >= hi:
                t = 1.0
            elif x <= lo:
                t = 0.0
            else:
                k = (hi - x) / float(hi - lo)
                t = 1.0 - (k * k * (3.0 - 2.0 * k))
        if t < 0.999:
            for y in range(h):
                r, g, b, a = px[x, y]
                px[x, y] = (r, g, b, clampi(a * t))
    return out


def fill_underside_voids(tile_rgba, fill_rgb, top_y=18):
    out = tile_rgba.copy()
    tp = out.load()
    fp = fill_rgb.load()
    w, h = out.size
    fw, fh = fill_rgb.size
    for y in range(top_y, h):
        for x in range(w):
            r, g, b, a = tp[x, y]
            if a < 255:
                fr, fg, fb = fp[x % fw, y % fh]
                af = a / 255.0
                tp[x, y] = (
                    clampi(r * af + fr * (1.0 - af)),
                    clampi(g * af + fg * (1.0 - af)),
                    clampi(b * af + fb * (1.0 - af)),
                    255,
                )
    return out


def harmonize_top_seams(tops, clean_ref, seam_cols=6):
    """Blend left/right seams of top_01..04 toward clean_ref's flat deck column (strictly sky=0 above y=7)
    so zero sky smudges or vertical height steps appear between any permutation of top_01..04."""
    ref = clean_ref.load()
    w, h = tops[0].size
    edge_col = []
    for y in range(h):
        if y < 7:
            # Force clean sky above horizontal shelf at seam boundaries!
            edge_col.append((0, 0, 0, 0))
        else:
            c = ref[w // 2, y]
            edge_col.append(c)

    res = []
    for im in tops:
        cpy = im.copy()
        px = cpy.load()
        for dx in range(seam_cols):
            t = dx / float(seam_cols)
            t = t * t * (3.0 - 2.0 * t)
            for y in range(h):
                er, eg, eb, ea = edge_col[y]
                for rx in (dx, w - 1 - dx):
                    rr, gr, br, ar = px[rx, y]
                    # Above shelf rim (y < 7), push boundary strictly to transparent so no pebble smudge hits x=0/63
                    nr_a = 0 if (y < 7 and dx == 0) else clampi(ea * (1.0 - t) + ar * t)
                    if nr_a < 8:
                        px[rx, y] = (0, 0, 0, 0)
                    else:
                        w_e = ea * (1.0 - t)
                        w_i = ar * t
                        s = w_e + w_i
                        px[rx, y] = (
                            clampi((er * w_e + rr * w_i) / s),
                            clampi((eg * w_e + gr * w_i) / s),
                            clampi((eb * w_e + br * w_i) / s),
                            nr_a,
                        )
        res.append(cpy)
    return res, clean_ref


def build_top_variants(raw_edges_rgba, fill_rgb):
    """Build top_01..04 (64x48 RGBA) aligned at SURFACE_OFFSET_Y = 14."""
    raw_s1 = raw_edges_rgba.crop((102, 82, 218, 255))
    raw_s2 = raw_edges_rgba.crop((562, 108, 724, 265))
    raw_s3 = raw_edges_rgba.crop((425, 108, 562, 260))
    # Crop inner section of right reef rocks (avoid outer rounded corner on right side)
    raw_s4 = raw_edges_rgba.crop((734, 88, 868, 255))

    t1 = remap_shelf_strip(raw_s1, TILE, 48, raw_back_y=36, raw_rim_y=94)
    t2 = remap_shelf_strip(raw_s2, TILE, 48, raw_back_y=10, raw_rim_y=68)
    t3 = remap_shelf_strip(raw_s3, TILE, 48, raw_back_y=10, raw_rim_y=68)
    t4 = remap_shelf_strip(raw_s4, TILE, 48, raw_back_y=30, raw_rim_y=88)

    # Embedded flat sunken waterlogged plank onto clean reef base
    t_plank = t3.copy()
    raw_plank = raw_edges_rgba.crop((288, 378, 438, 420)).resize((46, 12), Image.Resampling.LANCZOS)
    pp = raw_plank.load()
    for py in range(12):
        for pxx in range(46):
            r, g, b, a = pp[pxx, py]
            if pxx < 4:
                a = clampi(a * (pxx / 4.0))
            elif pxx > 41:
                a = clampi(a * ((45 - pxx) / 4.0))
            if py > 9:
                a = clampi(a * ((11 - py) / 2.0))
            pp[pxx, py] = (r, g, b, a)
    t_plank.alpha_composite(raw_plank, (9, 7))

    # Grade & finish clean reference reef tile t3 alongside the 4 final variants
    def finish_top(im):
        vg = grade_terrain_rgba(im, brightness_scale=0.52)
        vg = fill_underside_voids(vg, fill_rgb, top_y=19)
        vg = feather_alpha_bottom(vg, solid_end_y=34, fade_end_y=47)
        return vg

    clean_ref = finish_top(t3)
    variants = [finish_top(v) for v in (t1, t2, t_plank, t4)]
    tops, clean_ref = harmonize_top_seams(variants, clean_ref, seam_cols=6)
    return tops, clean_ref


def build_chasm_lips_and_walls(raw_edges_rgba, fill_rgb):
    """Build chasm_lip_l/r (76x96) AND extract wall_l/r (36x64) directly from their cliff faces
    so chasm cliff X and wall rock column match within 0px (zero vertical notch!)."""
    def build_lip(is_right=True):
        if is_right:
            crop = raw_edges_rgba.crop((182, 344, 478, 608))
            cliff_src_x = 120
        else:
            crop = raw_edges_rgba.crop((571, 344, 867, 608))
            cliff_src_x = 149

        cw, ch = crop.size
        out_w, out_h = CHASM_LIP_SIZE
        cliff_dst_x = CHASM_LIP_R_CLIFF_X if is_right else CHASM_LIP_L_CLIFF_X

        if is_right:
            left_part = crop.crop((0, 0, cliff_src_x, ch)).resize((cliff_dst_x, ch), Image.Resampling.LANCZOS)
            over_src = crop.crop((cliff_src_x, 0, cw, ch))
            over_part = over_src.resize((out_w - cliff_dst_x - 2, ch), Image.Resampling.LANCZOS)
            x_comp = Image.new("RGBA", (out_w, ch), (0, 0, 0, 0))
            x_comp.paste(left_part, (0, 0))
            x_comp.paste(over_part, (cliff_dst_x, 0))
        else:
            right_part = crop.crop((cliff_src_x, 0, cw, ch)).resize((out_w - cliff_dst_x, ch), Image.Resampling.LANCZOS)
            over_src = crop.crop((0, 0, cliff_src_x, ch))
            over_part = over_src.resize((cliff_dst_x - 2, ch), Image.Resampling.LANCZOS)
            x_comp = Image.new("RGBA", (out_w, ch), (0, 0, 0, 0))
            x_comp.paste(over_part, (2, 0))
            x_comp.paste(right_part, (cliff_dst_x, 0))

        im = remap_shelf_strip(x_comp, out_w, out_h, raw_back_y=22, raw_rim_y=77,
                               target_back_y=8, target_rim_y=18)
        im = grade_terrain_rgba(im, brightness_scale=0.50)

        ip = im.load()
        fp = fill_rgb.load()
        fw, fh = fill_rgb.size
        for y in range(18, out_h):
            for x in range(out_w):
                r, g, b, a = ip[x, y]
                in_solid = (x < cliff_dst_x - 4) if is_right else (x > cliff_dst_x + 4)
                if in_solid and a < 255:
                    fr, fg, fb = fp[x % fw, y % fh]
                    af = a / 255.0
                    ip[x, y] = (
                        clampi(r * af + fr * (1 - af)),
                        clampi(g * af + fg * (1 - af)),
                        clampi(b * af + fb * (1 - af)),
                        255,
                    )
        return im

    lip_l_raw = build_lip(is_right=False)
    lip_r_raw = build_lip(is_right=True)

    # Extract vertically seamless wall_r / wall_l from lower vertical wall portion of Row 2 & chasm lips!
    # Look at lip_r_raw y=60..95 around cliff_dst_x=46: strip x = [cliff_dst_x - WALL_R_CLIFF_X .. +36] = [18..54]
    def extract_wall_from_lip(lip_im, cliff_x_in_lip, cliff_x_in_wall, face_right=True):
        # Measure actual foreground max/min x in lower band y=58..92 to keep wall aligned with lip bottom!
        x0 = cliff_x_in_lip - cliff_x_in_wall
        # Crop lower 42px of cliff wall (y=52..94), scrub any leftover dangling seaweed pixels from wall tile
        band = lip_im.crop((x0, 52, x0 + WALL_SIZE[0], 94))
        bp = band.load()
        for yy in range(band.height):
            for xx in range(band.width):
                r, g, b, a = bp[xx, yy]
                # Remove thin floating green strand in chasm gap outside solid rock face
                is_strand = (xx > cliff_x_in_wall + 1) if face_right else (xx < cliff_x_in_wall - 1)
                if is_strand and g > r + 10:
                    bp[xx, yy] = (0, 0, 0, 0)
        wall_base = band.resize(WALL_SIZE, Image.Resampling.LANCZOS)
        # Toroidal Y cross-fade for vertical tiling
        w, h = WALL_SIZE
        shifted = ImageChops.offset(wall_base, 0, h // 2)
        gp = wall_base.load()
        sp = shifted.load()
        res = Image.new("RGBA", (w, h))
        rp = res.load()
        for y in range(h):
            ny = abs((y / float(h - 1)) - 0.5) * 2.0
            wy = max(0.0, min(1.0, (1.0 - ny) / 0.36))
            wy = wy * wy * (3.0 - 2.0 * wy)
            for x in range(w):
                c1 = gp[x, y]
                c2 = sp[x, y]
                na = clampi(c1[3] * wy + c2[3] * (1.0 - wy))
                if na < 8:
                    rp[x, y] = (0, 0, 0, 0)
                else:
                    w1 = c1[3] * wy
                    w2 = c2[3] * (1.0 - wy)
                    s = w1 + w2
                    rp[x, y] = (
                        clampi((c1[0] * w1 + c2[0] * w2) / s),
                        clampi((c1[1] * w1 + c2[1] * w2) / s),
                        clampi((c1[2] * w1 + c2[2] * w2) / s),
                        na,
                    )
        if face_right:
            res = feather_alpha_horizontal(res, 0, 12, keep_left=False)
        else:
            res = feather_alpha_horizontal(res, w - 12, w, keep_left=True)
        return res

    wall_r = extract_wall_from_lip(lip_r_raw, CHASM_LIP_R_CLIFF_X, WALL_R_CLIFF_X, face_right=True)
    wall_l = extract_wall_from_lip(lip_l_raw, CHASM_LIP_L_CLIFF_X, WALL_L_CLIFF_X, face_right=False)

    # Now finish horizontal/bottom feathers on chasm_lip_l & chasm_lip_r
    clip_r = feather_alpha_horizontal(lip_r_raw, 0, 12, keep_left=False)
    clip_r = feather_alpha_bottom(clip_r, solid_end_y=76, fade_end_y=95)

    clip_l = feather_alpha_horizontal(lip_l_raw, CHASM_LIP_SIZE[0] - 12, CHASM_LIP_SIZE[0], keep_left=True)
    clip_l = feather_alpha_bottom(clip_l, solid_end_y=76, fade_end_y=95)

    return clip_l, clip_r, wall_l, wall_r


def build_corner_out(raw_edges_rgba, fill_rgb, clean_ref, wall_l, wall_r):
    """Build solid-section convex outer step corners aligned accurately to wall_l/wall_r X and clean_ref Y."""
    raw_r = raw_edges_rgba.crop((94, 672, 194, 780))
    raw_l = raw_edges_rgba.crop((830, 672, 930, 780))

    def finish_corner(raw_crop, is_right=True):
        im = remap_shelf_strip(raw_crop, 40, 48, raw_back_y=12, raw_rim_y=55,
                               target_back_y=8, target_rim_y=18)
        im = grade_terrain_rgba(im, brightness_scale=0.52)
        # Keep cliff edge silhouette strictly within CORNER_OUT_R_CLIFF_X / CORNER_OUT_L_CLIFF_X + 2px
        # (matches wall_r/wall_l exposed rock X so step corners don't overhang awkwardly)
        ip = im.load()
        fp = fill_rgb.load()
        fw, fh = fill_rgb.size
        for y in range(18, 48):
            for x in range(40):
                r, g, b, a = ip[x, y]
                in_rock = (x < 30) if is_right else (x > 10)
                if in_rock and a < 255:
                    fr, fg, fb = fp[x % fw, y % fh]
                    af = a / 255.0
                    ip[x, y] = (
                        clampi(r * af + fr * (1 - af)),
                        clampi(g * af + fg * (1 - af)),
                        clampi(b * af + fb * (1 - af)),
                        255,
                    )
        # Harmonize deck-side outer edge (left side of corner_out_r, right side of corner_out_l) with clean_ref!
        rp = clean_ref.load()
        for dx in range(6):
            t = dx / 6.0
            t = t * t * (3.0 - 2.0 * t)
            x = dx if is_right else (39 - dx)
            for y in range(48):
                er, eg, eb, ea = (0, 0, 0, 0) if y < 7 else rp[32, y]
                cr, cg, cb, ca = ip[x, y]
                na = clampi(ea * (1.0 - t) + ca * t)
                if na < 8:
                    ip[x, y] = (0, 0, 0, 0)
                else:
                    we = ea * (1.0 - t)
                    wc = ca * t
                    s = we + wc
                    ip[x, y] = (
                        clampi((er * we + cr * wc) / s),
                        clampi((eg * we + cg * wc) / s),
                        clampi((eb * we + cb * wc) / s),
                        na,
                    )
        if is_right:
            im = feather_alpha_horizontal(im, 0, 8, keep_left=False)
        else:
            im = feather_alpha_horizontal(im, 32, 40, keep_left=True)
        im = feather_alpha_bottom(im, solid_end_y=30, fade_end_y=46)
        return im

    return finish_corner(raw_l, is_right=False), finish_corner(raw_r, is_right=True)


def build_corner_in(raw_edges_rgba, fill_rgb):
    """Build solid-section concave inside corners corner_in_l & corner_in_r (36x36 RGBA)."""
    raw_r = raw_edges_rgba.crop((158, 805, 248, 955))
    raw_l = raw_edges_rgba.crop((776, 805, 866, 955))

    def finish_in(raw_crop, wall_on_left=True):
        im = remap_shelf_strip(raw_crop, 36, 36, raw_back_y=50, raw_rim_y=110,
                               target_back_y=16, target_rim_y=26)
        im = grade_terrain_rgba(im, brightness_scale=0.48)
        ip = im.load()
        fp = fill_rgb.load()
        fw, fh = fill_rgb.size
        for y in range(36):
            for x in range(36):
                r, g, b, a = ip[x, y]
                in_wall = (x < 9) if wall_on_left else (x >= 27)
                in_floor = y >= 25
                if (in_wall or in_floor) and a < 255:
                    fr, fg, fb = fp[x % fw, y % fh]
                    af = a / 255.0
                    ip[x, y] = (
                        clampi(r * af + fr * (1 - af)),
                        clampi(g * af + fg * (1 - af)),
                        clampi(b * af + fb * (1 - af)),
                        255,
                    )
        cx, cy = (11.0, 21.0) if wall_on_left else (24.0, 21.0)
        for y in range(36):
            for x in range(36):
                r, g, b, a = ip[x, y]
                if a == 0:
                    continue
                d = math.hypot(x - cx, y - cy)
                if d < 10.0:
                    k = 1.0 - 0.24 * (1.0 - d / 10.0)
                    ip[x, y] = (clampi(r * k), clampi(g * k), clampi(b * k), a)
        if wall_on_left:
            im = feather_alpha_horizontal(im, 0, 5, keep_left=False)
            im = feather_alpha_horizontal(im, 27, 36, keep_left=True)
        else:
            im = feather_alpha_horizontal(im, 0, 9, keep_left=False)
            im = feather_alpha_horizontal(im, 31, 36, keep_left=True)
        px = im.load()
        for y in range(36):
            ft = 1.0
            if y < 6:
                ft = y / 6.0
            elif y >= 30:
                ft = max(0.0, (35 - y) / 5.0)
            if ft < 0.999:
                for x in range(36):
                    r, g, b, a = px[x, y]
                    px[x, y] = (r, g, b, clampi(a * ft))
        return im

    return finish_in(raw_l, wall_on_left=False), finish_in(raw_r, wall_on_left=True)


def build_far_silhouettes():
    """Key black sky, wrap-blend horizontal seam, and subtly dim silhouettes to avg_lum ~20-21."""
    im = Image.open(RAW_SILHOUETTE).convert("RGB")
    w, h = im.size
    px = im.load()
    rgba = Image.new("RGBA", (w, h))
    rp = rgba.load()

    for y in range(h):
        bfade = 1.0
        if y > h * 0.82:
            k = (y - h * 0.82) / (h * 0.18)
            bfade = 1.0 - 0.60 * k
        for x in range(w):
            r, g, b = px[x, y]
            s = r + g + b
            if s < 16:
                rp[x, y] = (0, 0, 0, 0)
            else:
                a = 255 if s >= 34 else clampi((s - 16) / 18.0 * 255.0)
                # Keep distant silhouettes atmospheric & calm (~20 lum, clearly dimmer than terrain ~40)
                nr = clampi(r * 0.48 * bfade)
                ng = clampi(g * 0.52 * bfade)
                nb = clampi((b * 0.56 + 4) * bfade)
                rp[x, y] = (nr, ng, nb, a)

    sil = rgba.resize((1024, 384), Image.Resampling.LANCZOS)
    sw, sh = sil.size
    shifted = ImageChops.offset(sil, sw // 2, 0)
    sp1 = sil.load()
    sp2 = shifted.load()
    out = Image.new("RGBA", (sw, sh))
    op = out.load()
    for x in range(sw):
        nx = abs((x / float(sw - 1)) - 0.5) * 2.0
        wx = max(0.0, min(1.0, (1.0 - nx) / 0.18))
        wx = wx * wx * (3.0 - 2.0 * wx)
        for y in range(sh):
            c1 = sp1[x, y]
            c2 = sp2[x, y]
            na = clampi(c1[3] * wx + c2[3] * (1.0 - wx))
            if na < 6:
                op[x, y] = (0, 0, 0, 0)
            else:
                w1 = c1[3] * wx
                w2 = c2[3] * (1.0 - wx)
                tot = w1 + w2
                op[x, y] = (
                    clampi((c1[0] * w1 + c2[0] * w2) / tot),
                    clampi((c1[1] * w1 + c2[1] * w2) / tot),
                    clampi((c1[2] * w1 + c2[2] * w2) / tot),
                    na,
                )
    return out


# ---------------- 1:1 Visual Preview Renderer ----------------

def render_backdrop(w, h, surface_y, deep_rock, far_sil, is_bottom_panel=False):
    canvas = Image.new("RGBA", (w, h))
    cp = canvas.load()
    top_bg = (0.028 * 255, 0.072 * 255, 0.135 * 255)
    bot_bg = (0.006 * 255, 0.016 * 255, 0.030 * 255)
    for y in range(h):
        t = y / float(max(1, h - 1))
        row_c = (
            clampi(top_bg[0] + (bot_bg[0] - top_bg[0]) * t),
            clampi(top_bg[1] + (bot_bg[1] - top_bg[1]) * t),
            clampi(top_bg[2] + (bot_bg[2] - top_bg[2]) * t),
            255,
        )
        for x in range(w):
            cp[x, y] = row_c

    dr_w = int(round(deep_rock.width * 1.45))
    dr_h = int(round(deep_rock.height * 1.45))
    dr = deep_rock.resize((dr_w, dr_h), Image.Resampling.BILINEAR).convert("RGBA")
    dp = dr.load()
    for yy in range(dr_h):
        for xx in range(dr_w):
            r, g, b, a = dp[xx, yy]
            dp[xx, yy] = (clampi(r * 0.92), clampi(g), clampi(b * 1.12), a)
    dr_flip = dr.transpose(Image.Transpose.FLIP_TOP_BOTTOM)

    top_y = int(round(surface_y - dr_h + 150))
    for tx in range(0, w, dr_w):
        canvas.alpha_composite(dr, (tx, top_y))
        if top_y + dr_h < h:
            canvas.alpha_composite(dr_flip, (tx, top_y + dr_h - 2))

    sil_y = int(round(surface_y - far_sil.height + 100))
    for tx in range(-180, w, far_sil.width):
        canvas.alpha_composite(far_sil, (tx, sil_y))

    haze = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hp = haze.load()
    haze_h = 200.0
    haze_top = int(max(0, surface_y - haze_h))
    haze_bot = min(h, int(surface_y + 120))
    for y in range(haze_top, haze_bot):
        if y <= surface_y:
            t = 1.0 - (surface_y - y) / haze_h
            a = int(round(255.0 * 0.34 * t * t))
        else:
            k = (y - surface_y) / 120.0
            a = int(round(255.0 * (0.34 + 0.30 * k)))
        col = (3, 8, 16, clampi(a))
        for x in range(w):
            hp[x, y] = col
    canvas.alpha_composite(haze)

    if not is_bottom_panel:
        sf = Image.new("RGBA", (w, 220), (0, 0, 0, 0))
        sp = sf.load()
        for y in range(220):
            t0 = y / 220.0
            a = clampi(255.0 * 0.78 * pow(1.0 - t0, 1.8))
            col = (2, 5, 10, a)
            for x in range(w):
                sp[x, y] = col
        canvas.alpha_composite(sf, (0, 0))
    return canvas


def draw_world_fill_rect(canvas, fill_rgb, rx, ry, rw, rh):
    if rw <= 0 or rh <= 0:
        return
    fw, fh = fill_rgb.size
    fp = fill_rgb.load()
    cp = canvas.load()
    cw, ch = canvas.size
    x0 = max(0, int(rx))
    y0 = max(0, int(ry))
    x1 = min(cw, int(rx + rw))
    y1 = min(ch, int(ry + rh))
    for y in range(y0, y1):
        fy = y % fh
        for x in range(x0, x1):
            fx = x % fw
            fr, fg, fb = fp[fx, fy]
            cp[x, y] = (fr, fg, fb, 255)


def paste_wall_clipped(canvas, wall_im, x_pos, y_start, y_end):
    """Draw vertically tiled wall segment clipped strictly before y_end so step walls never bleed past lower floor."""
    wy = y_start
    wh = wall_im.height
    step_y = wh - 4
    while wy < y_end:
        rem = y_end - wy
        if rem < wh:
            sub = wall_im.crop((0, 0, wall_im.width, rem))
            canvas.alpha_composite(sub, (x_pos, wy))
        else:
            canvas.alpha_composite(wall_im, (x_pos, wy))
        wy += step_y


def render_terrain(canvas, h_cols, broken, fill_rgb, assets, surface_base_y):
    w, h_img = canvas.size
    tops = assets["tops"]
    wall_l = assets["wall_l"]
    wall_r = assets["wall_r"]
    co_l = assets["corner_out_l"]
    co_r = assets["corner_out_r"]
    ci_l = assets["corner_in_l"]
    ci_r = assets["corner_in_r"]
    clip_l = assets["chasm_lip_l"]
    clip_r = assets["chasm_lip_r"]

    def y_of(c):
        return int(surface_base_y + h_cols[c] * TILE)

    # Pass 0: Chasm abyss gradient
    if broken:
        c = 0
        while c < len(h_cols):
            if h_cols[c] == 0:
                c += 1
                continue
            c0 = c
            while c + 1 < len(h_cols) and h_cols[c + 1] != 0:
                c += 1
            c1 = c
            c += 1
            x0 = c0 * TILE
            cw_px = (c1 - c0 + 1) * TILE
            mouth_y = int(surface_base_y)
            void = Image.new("RGBA", (cw_px, max(1, h_img - mouth_y)), (0, 0, 0, 0))
            vp = void.load()
            grad_h = 195.0
            for yy in range(void.height):
                t = min(1.0, yy / grad_h)
                s = t * t * (3.0 - 2.0 * t)
                a = clampi(255.0 * 0.94 * s)
                for xx in range(cw_px):
                    vp[xx, yy] = (2, 5, 11, a)
            canvas.alpha_composite(void, (x0, mouth_y))

    # Pass 1: Underground rock fill runs (inset by FILL_INSET)
    c = 0
    while c < len(h_cols):
        if broken and h_cols[c] != 0:
            c += 1
            continue
        c0 = c
        while c + 1 < len(h_cols) and h_cols[c + 1] == h_cols[c]:
            c += 1
        c1 = c
        c += 1
        rx = c0 * TILE
        rw = (c1 - c0 + 1) * TILE
        ry = y_of(c0) + FILL_INSET
        left_exposed = (c0 > 0) and (h_cols[c0 - 1] > h_cols[c0])
        right_exposed = (c1 + 1 < len(h_cols)) and (h_cols[c1 + 1] > h_cols[c1])
        if left_exposed:
            rx += FILL_INSET
            rw -= FILL_INSET
        if right_exposed:
            rw -= FILL_INSET
        draw_world_fill_rect(canvas, fill_rgb, rx, ry, rw, h_img - ry)

    # Pass 2: Top crust variants
    for idx in range(len(h_cols)):
        if broken and h_cols[idx] != 0:
            continue
        vi = (idx * 2654435761) & 3
        top_y = y_of(idx) - SURFACE_OFFSET_Y
        canvas.alpha_composite(tops[vi], (idx * TILE, top_y))

    # Pass 3: Exposed vertical cliff walls + corners + chasm lips (walls cleanly clipped to bot_lv + 4!)
    c = 0
    while c < len(h_cols):
        if broken and h_cols[c] != 0:
            c += 1
            continue
        c0 = c
        while c + 1 < len(h_cols) and h_cols[c + 1] == h_cols[c]:
            c += 1
        c1 = c
        c += 1

        top_lv = y_of(c0)
        if c1 + 1 < len(h_cols) and h_cols[c1 + 1] > h_cols[c1]:
            edge_x = (c1 + 1) * TILE
            bot_lv = h_img if broken else y_of(c1 + 1)
            if broken:
                paste_wall_clipped(canvas, wall_r, edge_x - WALL_R_CLIFF_X, top_lv + 72, h_img)
                canvas.alpha_composite(clip_r, (edge_x - CHASM_LIP_R_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
            else:
                paste_wall_clipped(canvas, wall_r, edge_x - WALL_R_CLIFF_X, top_lv + 14, bot_lv + 4)
                canvas.alpha_composite(co_r, (edge_x - CORNER_OUT_R_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
                canvas.alpha_composite(ci_r, (edge_x - CORNER_IN_R_ANCHOR[0], bot_lv - CORNER_IN_R_ANCHOR[1]))

        if c0 > 0 and h_cols[c0 - 1] > h_cols[c0]:
            edge_x = c0 * TILE
            bot_lv = h_img if broken else y_of(c0 - 1)
            if broken:
                paste_wall_clipped(canvas, wall_l, edge_x - WALL_L_CLIFF_X, top_lv + 72, h_img)
                canvas.alpha_composite(clip_l, (edge_x - CHASM_LIP_L_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
            else:
                paste_wall_clipped(canvas, wall_l, edge_x - WALL_L_CLIFF_X, top_lv + 14, bot_lv + 4)
                canvas.alpha_composite(co_l, (edge_x - CORNER_OUT_L_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
                canvas.alpha_composite(ci_l, (edge_x - CORNER_IN_L_ANCHOR[0], bot_lv - CORNER_IN_L_ANCHOR[1]))

    # Pass 4: Gentle abyssal downward earth shading across bottom edge (sinks ground naturally into screen bottom)
    bot_fade_y = int(surface_base_y + 70)
    if bot_fade_y < h_img:
        shade = Image.new("RGBA", (w, h_img - bot_fade_y), (0, 0, 0, 0))
        sp = shade.load()
        sh = shade.height
        for yy in range(sh):
            k = yy / float(max(1, sh - 1))
            a = clampi(255.0 * 0.38 * k * k)
            col = (2, 5, 11, a)
            for xx in range(w):
                sp[xx, yy] = col
        canvas.alpha_composite(shade, (0, bot_fade_y))


def draw_entity(canvas, sprite_path, anchor_x, anchor_y, world_x, world_y, scale=1.0):
    im = Image.open(sprite_path).convert("RGBA")
    if abs(scale - 1.0) > 1e-3:
        im = im.resize(
            (int(round(im.width * scale)), int(round(im.height * scale))),
            Image.Resampling.NEAREST,
        )
        anchor_x *= scale
        anchor_y *= scale
    dx = int(round(world_x - anchor_x))
    dy = int(round(world_y - anchor_y))
    canvas.alpha_composite(im, (dx, dy))


def measure_stats(name, im, check_xy=False):
    rgb = im.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    vals = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if im.mode == "RGBA" and im.getpixel((x, y))[3] < 32:
                continue
            r, g, b = px[x, y]
            vals.append(lum709(r, g, b))
    avg = sum(vals) / max(1, len(vals))
    info = f"  {name:22s}: avg_lum={avg:5.1f} (max={max(vals) if vals else 0:5.1f})"
    if check_xy:
        dx = sum(abs(lum709(*px[0, y]) - lum709(*px[w - 1, y])) for y in range(h)) / float(h)
        dy = sum(abs(lum709(*px[x, 0]) - lum709(*px[x, h - 1])) for x in range(w)) / float(w)
        info += f" | seam dX={dx:.2f}, dY={dy:.2f}"
    print(info)


def main():
    os.makedirs(OUT_TERRAIN, exist_ok=True)
    os.makedirs(OUT_BG, exist_ok=True)
    os.makedirs(os.path.dirname(ATLAS_CHECK_PATH), exist_ok=True)

    raw_edges = key_edges_bfs(Image.open(RAW_EDGES).convert("RGB"))
    fill_rgb = build_fill_seamless(raw_edges)
    fill_rgb.save(os.path.join(OUT_TERRAIN, "fill_seamless.png"))

    tops, clean_ref = build_top_variants(raw_edges, fill_rgb)
    for i, t in enumerate(tops, 1):
        t.save(os.path.join(OUT_TERRAIN, f"top_0{i}.png"))

    clip_l, clip_r, wall_l, wall_r = build_chasm_lips_and_walls(raw_edges, fill_rgb)
    wall_l.save(os.path.join(OUT_TERRAIN, "wall_l.png"))
    wall_r.save(os.path.join(OUT_TERRAIN, "wall_r.png"))
    clip_l.save(os.path.join(OUT_TERRAIN, "chasm_lip_l.png"))
    clip_r.save(os.path.join(OUT_TERRAIN, "chasm_lip_r.png"))

    co_l, co_r = build_corner_out(raw_edges, fill_rgb, clean_ref, wall_l, wall_r)
    co_l.save(os.path.join(OUT_TERRAIN, "corner_out_l.png"))
    co_r.save(os.path.join(OUT_TERRAIN, "corner_out_r.png"))

    ci_l, ci_r = build_corner_in(raw_edges, fill_rgb)
    ci_l.save(os.path.join(OUT_TERRAIN, "corner_in_l.png"))
    ci_r.save(os.path.join(OUT_TERRAIN, "corner_in_r.png"))

    far_sil = build_far_silhouettes()
    far_sil.save(os.path.join(OUT_BG, "far_silhouettes.png"))

    deep_rock = Image.open(os.path.join(OUT_BG, "deep_rock.png")).convert("RGB")
    print("=== Luminance Ladder & Seam Verification ===")
    measure_stats("deep_rock.png", deep_rock)
    measure_stats("far_silhouettes.png", far_sil)
    measure_stats("fill_seamless.png", fill_rgb, check_xy=True)
    for i, t in enumerate(tops, 1):
        measure_stats(f"top_0{i}.png", t)
    measure_stats("wall_r.png", wall_r)
    measure_stats("corner_in_r.png", ci_r)
    measure_stats("chasm_lip_r.png", clip_r)

    # Save 2x2 real-size fill check (512x512 scaled down cleanly to fit sheet) + all modular pieces
    diag = Image.new("RGBA", (620, 280), (10, 22, 36, 255))
    fill_2x2 = Image.new("RGB", (512, 512))
    for yy in range(2):
        for xx in range(2):
            fill_2x2.paste(fill_rgb, (xx * 256, yy * 256))
    diag.paste(fill_2x2.resize((256, 256), Image.Resampling.BILINEAR), (10, 10))
    for i, t in enumerate(tops):
        diag.alpha_composite(t, (280 + i * 64, 20))
    diag.alpha_composite(wall_r, (280, 95))
    diag.alpha_composite(wall_r, (280, 95 + 60))
    diag.alpha_composite(co_r, (340, 95))
    diag.alpha_composite(ci_r, (395, 95))
    diag.alpha_composite(clip_r, (450, 95))
    diag.alpha_composite(clip_l, (535, 95))
    diag.save(ATLAS_CHECK_PATH)

    assets = {
        "tops": tops, "wall_l": wall_l, "wall_r": wall_r,
        "corner_out_l": co_l, "corner_out_r": co_r,
        "corner_in_l": ci_l, "corner_in_r": ci_r,
        "chasm_lip_l": clip_l, "chasm_lip_r": clip_r,
    }

    p1 = render_backdrop(1280, 720, 540, deep_rock, far_sil, is_bottom_panel=False)
    h1 = [0, 0, 0, 1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    render_terrain(p1, h1, False, fill_rgb, assets, 540)

    with open(os.path.join(ROOT, "sprites", "run", "run.json"), encoding="utf-8") as f:
        rj = json.load(f)["frames"][0]
    draw_entity(p1, os.path.join(ROOT, "sprites", "chaser_run", "chaser_run_01.png"),
                83.5, 169.0, 95, 540 - 26, scale=1.0)
    draw_entity(p1, os.path.join(ROOT, "sprites", "run", "run_00.png"),
                rj["anchorX"], rj["anchorY"], 470, 540, scale=0.85)
    barrels = Image.open(os.path.join(ROOT, "sprites", "hazard", "hazard_low_barrels.png")).convert("RGBA")
    p1.alpha_composite(barrels, (680 - barrels.width // 2, 540 - barrels.height))
    rib = Image.open(os.path.join(ROOT, "sprites", "hazard", "hazard_low_shiprib.png")).convert("RGBA")
    p1.alpha_composite(rib, (900 - rib.width // 2, 540 - rib.height))
    chain = Image.open(os.path.join(ROOT, "sprites", "hazard", "hazard_over_chain.png")).convert("RGBA")
    p1.alpha_composite(chain, (1110 - chain.width // 2, 540 - 66 - chain.height))

    p2 = render_backdrop(1280, 420, 210, deep_rock, far_sil, is_bottom_panel=True)
    h2 = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
    render_terrain(p2, h2, True, fill_rgb, assets, 210)
    with open(os.path.join(ROOT, "sprites", "jump", "jump.json"), encoding="utf-8") as f:
        jj = json.load(f)["frames"][4]
    draw_entity(p2, os.path.join(ROOT, "sprites", "jump", "jump_04.png"),
                jj["anchorX"], jj["anchorY"], 610, 145, scale=0.85)

    full = Image.new("RGB", (1280, 720 + 18 + 420), (8, 16, 28))
    full.paste(p1.convert("RGB"), (0, 0))
    full.paste(p2.convert("RGB"), (0, 720 + 18))
    draw = ImageDraw.Draw(full)
    draw.rectangle((0, 720, 1280, 738), fill=(12, 24, 40))
    full.save(PREVIEW_PATH)
    print(f"Saved preview -> {PREVIEW_PATH}")
    print(f"Saved tile atlas check -> {ATLAS_CHECK_PATH}")


if __name__ == "__main__":
    main()
