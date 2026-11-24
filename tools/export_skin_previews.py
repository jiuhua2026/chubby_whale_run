#!/usr/bin/env python3
"""从皮肤三视图原图裁出第 1 尊正面全身立绘，精确去白底与内部闭合镂空孔并导出 `sprites/skins/<skin_id>/preview.png`。"""
import argparse
import os
import sys
from collections import deque
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png_alpha_key as pak

SKINS_SRC_DIR = os.path.join("image", "player", "skins")
SKINS_OUT_DIR = os.path.join("sprites", "skins")
TARGET_H = 260

SKIP_SKINS: set[str] = set()

## 针对跨白名单区域/紧贴白色鞋袜描边的定向补孔种子表（源图 left_slice 坐标）
## 仅向内按亮白阈值扩张并带 max_area 保险丝，绝不波及周边白色毛边或白袜。
EXTRA_HOLE_SEEDS = {
    "snow_cloak": [
        (807, 1088),  # 右下斗篷下摆、长发与鲸鱼尾巴夹缝
    ],
    "academy_plaid": [
        (600, 829),   # 右下格纹裙摆、长发与鲸鱼尾巴夹缝
    ],
    "santa_cloak": [
        (332, 731),   # 双腿白袜正中纵向窄缝
        (447, 734),   # 右下白色毛边裙底与鲸鱼尾巴之间细缝
    ],
    "burger_crew": [
        (435, 775),   # 左侧下颌、发丝与红白衣领之间的棋盘格镂空
        (635, 765),   # 右侧话筒、发丝与红白肩袖之间的棋盘格镂空
        (322, 737),   # 左侧外缕细发丝与主发卷之间的夹缝
        (776, 974),   # 右侧白袖口与长马尾之间的细小镂空角
    ],
}


def find_turnaround(skin_dir: str) -> str | None:
    for name in (
        "character_turnaround.png",
        "Gemini_Generated_Image_xssux7xssux7xssu.jpg",
        "character_turnaround.jpg",
    ):
        p = os.path.join(skin_dir, name)
        if os.path.isfile(p):
            return p
    return None


def _is_checkerboard_bg(im: Image.Image) -> bool:
    """检测左上角背景是否为灰白棋盘格（同时存在浅白 >=245 与中性灰 <=222）。"""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    has_gray = False
    has_white = False
    for y in range(0, min(100, h), 2):
        for x in range(0, min(100, w), 2):
            r, g, b = px[x, y]
            if max(r, g, b) - min(r, g, b) > 12:
                continue
            mc = min(r, g, b)
            if 190 <= mc <= 222:
                has_gray = True
            elif mc >= 245:
                has_white = True
            if has_gray and has_white:
                return True
    return False


def key_checkerboard_clean(
    im: Image.Image,
    extra_seeds: list[tuple[int, int]] | None = None,
) -> Image.Image:
    """从灰白假棋盘格 JPG 中精确扣除外部与闭合镂空，并用局部背景亮度反预乘去白/灰边。"""
    rgb = im.convert("RGB")
    w, h = rgb.size
    n = w * h
    px = rgb.load()

    def is_bg_px(r: int, g: int, b: int) -> bool:
        return min(r, g, b) >= 188 and (max(r, g, b) - min(r, g, b)) <= 14

    bg = bytearray(n)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            i = y * w + x
            if is_bg_px(*px[x, y]) and not bg[i]:
                bg[i] = 1
                dq.append(i)
    for y in range(h):
        for x in (0, w - 1):
            i = y * w + x
            if is_bg_px(*px[x, y]) and not bg[i]:
                bg[i] = 1
                dq.append(i)
    while dq:
        i = dq.popleft()
        x, y = i % w, i // w
        for ni in (
            i - 1 if x > 0 else -1,
            i + 1 if x < w - 1 else -1,
            i - w if y > 0 else -1,
            i + w if y < h - 1 else -1,
        ):
            if ni >= 0 and not bg[ni] and is_bg_px(*px[ni % w, ni // w]):
                bg[ni] = 1
                dq.append(ni)

    # 人物紧致包围盒，仅对发丝/头顶区域的棋盘格闭合孔自动挖孔
    xs_fg = [x for x in range(0, w, 2) if any(not bg[y * w + x] for y in range(0, h, 2))]
    ys_fg = [y for y in range(0, h, 2) if any(not bg[y * w + x] for x in range(0, w, 2))]
    fx0, fx1 = (min(xs_fg), max(xs_fg)) if xs_fg else (0, w - 1)
    fy0, fy1 = (min(ys_fg), max(ys_fg)) if ys_fg else (0, h - 1)
    fw, fh = max(1, fx1 - fx0), max(1, fy1 - fy0)

    seen = bytearray(n)
    for sy in range(h):
        for sx in range(w):
            si = sy * w + sx
            if bg[si] or seen[si] or not is_bg_px(*px[sx, sy]):
                continue
            dq = deque([si])
            seen[si] = 1
            pts = []
            edge_pts = []
            while dq:
                i = dq.popleft()
                pts.append(i)
                x, y = i % w, i // w
                is_edge = False
                for ni in (
                    i - 1 if x > 0 else -1,
                    i + 1 if x < w - 1 else -1,
                    i - w if y > 0 else -1,
                    i + w if y < h - 1 else -1,
                ):
                    if ni < 0 or bg[ni]:
                        continue
                    if is_bg_px(*px[ni % w, ni // w]):
                        if not seen[ni]:
                            seen[ni] = 1
                            dq.append(ni)
                    else:
                        is_edge = True
                if is_edge:
                    edge_pts.append((x, y))
            if len(pts) < 30 or not edge_pts:
                continue
            xs_p = [p % w for p in pts]
            ys_p = [p // w for p in pts]
            cx = (min(xs_p) + max(xs_p)) * 0.5
            cy = (min(ys_p) + max(ys_p)) * 0.5
            rx = (cx - fx0) / fw
            ry = (cy - fy0) / fh
            if not (ry < 0.20 or (ry < 0.72 and (rx < 0.25 or rx > 0.68))):
                continue
            gray_cnt = sum(1 for p in pts if 190 <= min(px[p % w, p // w]) <= 220)
            if gray_cnt < len(pts) * 0.15:
                continue
            ink = 0
            warm = 0
            samples = edge_pts[::max(1, len(edge_pts) // 160)]
            for ex, ey in samples:
                hd = False
                hw = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    for rad in range(1, 7):
                        nx, ny = ex + dx * rad, ey + dy * rad
                        if 0 <= nx < w and 0 <= ny < h:
                            rr, gg, bb = px[nx, ny]
                            if max(rr, gg, bb) < 165 or (bb - rr >= 15 and max(rr, gg, bb) < 228):
                                hd = True
                            if rr - bb > 26 and rr > 140:
                                hw = True
                            if hd or hw:
                                break
                    if hd or hw:
                        break
                if hd:
                    ink += 1
                if hw:
                    warm += 1
            if ink / float(len(samples)) >= 0.65 and warm / float(len(samples)) <= 0.08:
                for p in pts:
                    bg[p] = 1

    # 定向补孔（颈部/发丝内侧紧贴肤色与红条纹衣服的封闭棋盘格孔）
    if extra_seeds:
        for sx, sy in extra_seeds:
            if not (0 <= sx < w and 0 <= sy < h):
                continue
            si = sy * w + sx
            if bg[si] or not is_bg_px(*px[sx, sy]):
                continue
            dq = deque([si])
            vis = {si}
            aborted = False
            while dq:
                i = dq.popleft()
                if len(vis) > 4500:
                    aborted = True
                    break
                x, y = i % w, i // w
                for ni in (
                    i - 1 if x > 0 else -1,
                    i + 1 if x < w - 1 else -1,
                    i - w if y > 0 else -1,
                    i + w if y < h - 1 else -1,
                ):
                    if ni >= 0 and not bg[ni] and ni not in vis and is_bg_px(*px[ni % w, ni // w]):
                        vis.add(ni)
                        dq.append(ni)
            if not aborted:
                for p in vis:
                    bg[p] = 1

    # 边界 4px 过渡带：用局部背景亮度 + 最近前景内部色做反预乘并压暗去白边
    band = 4
    dist = bytearray(n)
    frontier = [i for i in range(n) if bg[i]]
    for lv in range(1, band + 3):
        nxt = []
        for i in frontier:
            x, y = i % w, i // w
            for ni in (
                i - 1 if x > 0 else -1,
                i + 1 if x < w - 1 else -1,
                i - w if y > 0 else -1,
                i + w if y < h - 1 else -1,
            ):
                if ni >= 0 and not bg[ni] and dist[ni] == 0:
                    dist[ni] = lv
                    nxt.append(ni)
        frontier = nxt
        if not frontier:
            break

    bg_val = bytearray(n)
    bg_q = deque()
    for i in range(n):
        if bg[i]:
            r, g, b = px[i % w, i // w]
            bg_val[i] = (r + g + b) // 3
            bg_q.append(i)
    while bg_q:
        i = bg_q.popleft()
        if dist[i] >= band:
            continue
        x, y = i % w, i // w
        for ni in (
            i - 1 if x > 0 else -1,
            i + 1 if x < w - 1 else -1,
            i - w if y > 0 else -1,
            i + w if y < h - 1 else -1,
        ):
            if ni >= 0 and not bg[ni] and bg_val[ni] == 0 and dist[ni] <= band:
                bg_val[ni] = bg_val[i]
                bg_q.append(ni)

    minc = bytearray(n)
    for y in range(h):
        row = y * w
        for x in range(w):
            minc[row + x] = min(px[x, y])

    deep = bytearray(n)
    for i in range(n):
        if bg[i]:
            continue
        if dist[i] == 0 or dist[i] > band:
            deep[i] = 1
        else:
            x, y = i % w, i // w
            v = minc[i]
            if not (
                (x > 0 and not bg[i - 1] and minc[i - 1] < v)
                or (x < w - 1 and not bg[i + 1] and minc[i + 1] < v)
                or (y > 0 and not bg[i - w] and minc[i - w] < v)
                or (y < h - 1 and not bg[i + w] and minc[i + w] < v)
            ):
                deep[i] = 1

    cr = bytearray(n)
    cg = bytearray(n)
    cb = bytearray(n)
    cm = bytearray(n)
    has = bytearray(n)
    fq = deque()
    for i in range(n):
        if deep[i]:
            r, g, b = px[i % w, i // w]
            cr[i] = r
            cg[i] = g
            cb[i] = b
            cm[i] = max(r, g, b)
            has[i] = 1
            fq.append(i)
    while fq:
        i = fq.popleft()
        x, y = i % w, i // w
        for ni in (
            i - 1 if x > 0 else -1,
            i + 1 if x < w - 1 else -1,
            i - w if y > 0 else -1,
            i + w if y < h - 1 else -1,
        ):
            if ni >= 0 and not bg[ni] and not has[ni]:
                cr[ni] = cr[i]
                cg[ni] = cg[i]
                cb[ni] = cb[i]
                cm[ni] = cm[i]
                has[ni] = 1
                fq.append(ni)

    out = Image.new("RGBA", (w, h))
    po = out.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            i = row + x
            if bg[i]:
                po[x, y] = (0, 0, 0, 0)
                continue
            r, g, b = px[x, y]
            if deep[i]:
                po[x, y] = (r, g, b, 255)
                continue
            fm = min(cr[i], cg[i], cb[i]) if has[i] else 40
            cap = cm[i] if has[i] else 40
            bv = float(bg_val[i] if bg_val[i] > 0 else 230)
            den = bv - fm
            a = 1.0 if den <= 1.0 else (bv - minc[i]) / den
            a = _clamp01(a)
            al = int(a * 255.0 + 0.5)
            if al < 14:
                po[x, y] = (0, 0, 0, 0)
                continue
            back = bv * (1.0 - a)
            rr = int((r - back) / a + 0.5)
            gg = int((g - back) / a + 0.5)
            bb = int((b - back) / a + 0.5)
            hi = max(rr, gg, bb)
            if hi > cap > 0:
                k = cap / float(hi)
                rr = int(rr * k + 0.5)
                gg = int(gg * k + 0.5)
                bb = int(bb * k + 0.5)
            po[x, y] = (
                0 if rr < 0 else (255 if rr > 255 else rr),
                0 if gg < 0 else (255 if gg > 255 else gg),
                0 if bb < 0 else (255 if bb > 255 else bb),
                al,
            )
    return out


def _clamp01(v: float) -> float:
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def _enclosed_white_pockets(im: Image.Image, t_bg: int = 238, extra_seeds: list[tuple[int, int]] | None = None) -> bytearray:
    """识别三视图正面人物内部被深色描边围住的纯白镂空孔（呆毛内环、发隙、双腿间隙）。

    用两条特征与白色服饰/毛领/眼白区分：
      1. 内部像素均色偏中性纯白（平均通道极差 <= 6.5，排除淡蓝/暖粉阴影的白衣服）；
      2. 沿边界向外走 6px 内能碰到深色描边线（`max(R,G,B) < 155` 占比 >= 0.55），
         而白色毛领/围裙/袜子内侧只会碰到带色阴影或另一片浅白。
    """
    rgb = im.convert("RGB")
    w, h = rgb.size
    n = w * h
    px = rgb.load()

    outer = bytearray(n)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            r, g, b = px[x, y]
            if min(r, g, b) >= t_bg and not outer[y * w + x]:
                outer[y * w + x] = 1
                dq.append(y * w + x)
    for y in range(h):
        for x in (0, w - 1):
            r, g, b = px[x, y]
            if min(r, g, b) >= t_bg and not outer[y * w + x]:
                outer[y * w + x] = 1
                dq.append(y * w + x)
    while dq:
        i = dq.popleft()
        x, y = i % w, i // w
        for ni in (
            i - 1 if x > 0 else -1,
            i + 1 if x < w - 1 else -1,
            i - w if y > 0 else -1,
            i + w if y < h - 1 else -1,
        ):
            if ni >= 0 and not outer[ni]:
                rr, gg, bb = px[ni % w, ni // w]
                if min(rr, gg, bb) >= t_bg:
                    outer[ni] = 1
                    dq.append(ni)

    # 仅按最左侧第 1 尊人物的水平列分段计算 tight 人物包围盒，避免被第 2 尊侧视图边缘拉偏 rx
    col_has = [any(not outer[y * w + x] for y in range(0, h, 2)) for x in range(w)]
    segs = []
    st = None
    for x, has in enumerate(col_has):
        if has and st is None:
            st = x
        elif not has and st is not None:
            if x - st >= 40:
                segs.append((st, x - 1))
            st = None
    if st is not None and w - st >= 40:
        segs.append((st, w - 1))
    merged = [segs[0]] if segs else [(0, w - 1)]
    for s0, s1 in segs[1:]:
        p0, p1 = merged[-1]
        if s0 - p1 <= 8:
            merged[-1] = (p0, s1)
        else:
            break
    fx0, fx1 = merged[0]
    fg_ys = [y for y in range(0, h, 2) for x in range(fx0, fx1 + 1, 2) if not outer[y * w + x]]
    fy0, fy1 = (min(fg_ys), max(fg_ys)) if fg_ys else (0, h - 1)
    fw = max(1, fx1 - fx0)
    fh = max(1, fy1 - fy0)

    seen = bytearray(n)
    pockets = bytearray(n)
    t_inner = max(t_bg + 3, 241)

    for sy in range(h):
        for sx in range(w):
            si = sy * w + sx
            if outer[si] or seen[si]:
                continue
            r, g, b = px[sx, sy]
            if min(r, g, b) < t_inner or (max(r, g, b) - min(r, g, b)) > 11:
                continue

            dq = deque([si])
            seen[si] = 1
            pts = []
            edge_pts = []
            while dq:
                i = dq.popleft()
                pts.append(i)
                x, y = i % w, i // w
                is_edge = False
                for ni in (
                    i - 1 if x > 0 else -1,
                    i + 1 if x < w - 1 else -1,
                    i - w if y > 0 else -1,
                    i + w if y < h - 1 else -1,
                ):
                    if ni < 0 or outer[ni]:
                        continue
                    rr, gg, bb = px[ni % w, ni // w]
                    if min(rr, gg, bb) >= t_inner and (max(rr, gg, bb) - min(rr, gg, bb)) <= 11:
                        if not seen[ni]:
                            seen[ni] = 1
                            dq.append(ni)
                    else:
                        is_edge = True
                if is_edge:
                    edge_pts.append((x, y))

            if len(pts) < 16 or not edge_pts:
                continue

            spread_sum = 0
            min_sum = 0
            r_sum = 0
            g_sum = 0
            b_sum = 0
            xs_p = []
            ys_p = []
            for i in pts:
                x, y = i % w, i // w
                xs_p.append(x)
                ys_p.append(y)
                rr, gg, bb = px[x, y]
                spread_sum += max(rr, gg, bb) - min(rr, gg, bb)
                min_sum += min(rr, gg, bb)
                r_sum += rr
                g_sum += gg
                b_sum += bb
            cnt = float(len(pts))
            avg_spread = spread_sum / cnt
            avg_min = min_sum / cnt
            avg_r = r_sum / cnt
            avg_g = g_sum / cnt
            avg_b = b_sum / cnt
            # 先用偏色与亮度粗过滤，再做区域白名单与外圈边界确认（支持压缩图发丝微偏色）
            if avg_spread > 4.8 or avg_min < 245.0:
                continue
            if avg_r > avg_g + 1.5 or avg_r > avg_b + 1.8:
                continue

            # 区域白名单（最硬保障）：
            #   · 头顶呆毛区 (ry < 0.26)
            #   · 衣领之上的头部及高马尾两侧 (ry < 0.42 且 rx < 0.30 或 rx > 0.65)
            #   · 身体两侧外围长发/耳鳍区 (ry <= 0.75 且 rx < 0.22 或 rx > 0.77)
            # 躯干、衣袖、手套、围裙、袜子、白鞋面所在中心及下身区一律禁止穿洞。
            cx = (min(xs_p) + max(xs_p)) * 0.5
            cy = (min(ys_p) + max(ys_p)) * 0.5
            if cx < fx0 or cx > fx1:
                continue
            rx = (cx - fx0) / fw
            ry = (cy - fy0) / fh
            in_ahoge_top = (ry < 0.26 and 0.25 <= rx <= 0.75)
            in_upper_hair = (ry < 0.42 and (rx < 0.30 or rx > 0.65))
            in_side_hair = (ry <= 0.75 and (rx < 0.22 or rx > 0.77))
            if not (in_ahoge_top or in_upper_hair or in_side_hair):
                continue

            # 边界特征：真镂空孔外圈是深色描边或蓝发阴影（不含大片暖红服饰/皮肤）
            ink_or_hair = 0
            warm_or_red = 0
            step = max(1, len(edge_pts) // 240)
            samples = edge_pts[::step]
            for ex, ey in samples:
                hit_dark = False
                hit_warm = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    for rad in range(1, 7):
                        nx, ny = ex + dx * rad, ey + dy * rad
                        if 0 <= nx < w and 0 <= ny < h:
                            rr, gg, bb = px[nx, ny]
                            mx = max(rr, gg, bb)
                            if mx < 165 or (bb - rr >= 15 and mx < 228):
                                hit_dark = True
                            if rr - bb > 26 and rr > 140:
                                hit_warm = True
                            if hit_dark or hit_warm:
                                break
                    if hit_dark or hit_warm:
                        break
                if hit_dark:
                    ink_or_hair += 1
                if hit_warm:
                    warm_or_red += 1

            dark_frac = ink_or_hair / float(len(samples))
            warm_frac = warm_or_red / float(len(samples))
            strict_ok = (
                avg_min >= 248.5
                and avg_r <= avg_g + 1.0
                and avg_r <= avg_b + 0.8
                and dark_frac >= 0.55
                and warm_frac <= 0.08
            )
            compressed_hair_ok = (
                (in_upper_hair or in_side_hair)
                and dark_frac >= 0.80
                and warm_frac <= 0.05
            )
            if strict_ok or compressed_hair_ok:
                for i in pts:
                    pockets[i] = 1

    # 定向种子补孔（处理一侧紧贴肤色/红条纹衣领的高难白缝）
    if extra_seeds:
        for sx, sy in extra_seeds:
            if not (0 <= sx < w and 0 <= sy < h):
                continue
            si = sy * w + sx
            if outer[si] or pockets[si]:
                continue
            r0, g0, b0 = px[sx, sy]
            if min(r0, g0, b0) < 230 or (max(r0, g0, b0) - min(r0, g0, b0)) > 16:
                continue
            dq = deque([si])
            visited = {si}
            pts_s = []
            aborted = False
            while dq:
                i = dq.popleft()
                pts_s.append(i)
                if len(pts_s) > 4500:
                    aborted = True
                    break
                x, y = i % w, i // w
                for ni in (
                    i - 1 if x > 0 else -1,
                    i + 1 if x < w - 1 else -1,
                    i - w if y > 0 else -1,
                    i + w if y < h - 1 else -1,
                ):
                    if ni >= 0 and not outer[ni] and ni not in visited:
                        rr, gg, bb = px[ni % w, ni // w]
                        if min(rr, gg, bb) >= 232 and (max(rr, gg, bb) - min(rr, gg, bb)) <= 14:
                            visited.add(ni)
                            dq.append(ni)
            if not aborted:
                for i in pts_s:
                    pockets[i] = 1
    return pockets


def key_white_clean(
    im: Image.Image,
    t_bg: int = 238,
    band: int = 5,
    alpha_floor: int = 14,
    extra_seeds: list[tuple[int, int]] | None = None,
) -> Image.Image:
    """结合闭合白孔识别 + 反预乘去白底光晕。"""
    rgb = im.convert("RGB")
    pockets = _enclosed_white_pockets(rgb, t_bg=t_bg, extra_seeds=extra_seeds)
    rgba, _ = pak.key_white_to_alpha(rgb, t_bg=t_bg, band=band, alpha_floor=alpha_floor)
    if not any(pockets):
        return rgba

    w, h = rgb.size
    n = w * h
    po = rgba.load()
    dist_p = bytearray(n)
    frontier = []
    for i in range(n):
        if pockets[i]:
            po[i % w, i // w] = (0, 0, 0, 0)
            dist_p[i] = 1
            frontier.append(i)

    # 清除孔洞内壁 3px 残余白光晕
    for lv in range(2, 6):
        nxt = []
        for i in frontier:
            x, y = i % w, i // w
            for ni in (
                i - 1 if x > 0 else -1,
                i + 1 if x < w - 1 else -1,
                i - w if y > 0 else -1,
                i + w if y < h - 1 else -1,
            ):
                if ni >= 0 and dist_p[ni] == 0:
                    nx, ny = ni % w, ni // w
                    r, g, b, a = po[nx, ny]
                    if a == 0:
                        continue
                    dist_p[ni] = lv
                    nxt.append(ni)
                    mc = min(r, g, b)
                    if mc >= t_bg:
                        po[nx, ny] = (0, 0, 0, 0)
                    elif mc > 175 and (max(r, g, b) - mc) <= 16:
                        cov = _clamp01((255.0 - float(mc)) / max(1.0, 255.0 - 95.0))
                        new_a = int(a * cov + 0.5)
                        if new_a < alpha_floor:
                            po[nx, ny] = (0, 0, 0, 0)
                        else:
                            scale = max(0.35, cov)
                            po[nx, ny] = (int(r * scale), int(g * scale), int(b * scale), new_a)
        frontier = nxt
    return rgba


def crop_left_figure(rgba: Image.Image) -> Image.Image:
    """按水平 alpha 投影定位三视图里最左侧人物的紧致包围盒。"""
    w, h = rgba.size
    a = rgba.getchannel("A").tobytes()
    col_has = [False] * w
    for x in range(w):
        for y in range(h):
            if a[y * w + x] > 12:
                col_has[x] = True
                break

    segments = []
    start = None
    for x, has in enumerate(col_has):
        if has and start is None:
            start = x
        elif not has and start is not None:
            if x - start >= 40:
                segments.append((start, x - 1))
            start = None
    if start is not None and w - start >= 40:
        segments.append((start, w - 1))

    if not segments:
        return rgba

    # 合并间隔 <= 8px 的碎片（防止单人边缘细碎高光劈裂，但绝不把第 2 个侧视图吞进来）
    merged = [segments[0]]
    for s0, s1 in segments[1:]:
        p0, p1 = merged[-1]
        if s0 - p1 <= 8:
            merged[-1] = (p0, s1)
        else:
            merged.append((s0, s1))

    x0, x1 = merged[0]
    y0, y1 = h - 1, 0
    for y in range(h):
        row_off = y * w
        if any(a[row_off + x] > 12 for x in range(x0, x1 + 1)):
            if y < y0:
                y0 = y
            if y > y1:
                y1 = y

    pad = 4
    crop_box = (max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + 1 + pad), min(h, y1 + 1 + pad))
    return rgba.crop(crop_box)


def resize_premultiplied(im: Image.Image, target_h: int) -> Image.Image:
    w, h = im.size
    if h <= 0:
        return im
    new_w = max(1, round(w * (target_h / float(h))))
    rgba = im.convert("RGBA")
    r, g, b, a = rgba.split()
    rb, gb, bb, ab = r.tobytes(), g.tobytes(), b.tobytes(), a.tobytes()
    pr = bytearray(len(ab))
    pg = bytearray(len(ab))
    pb = bytearray(len(ab))
    for i, av in enumerate(ab):
        pr[i] = (rb[i] * av + 127) // 255
        pg[i] = (gb[i] * av + 127) // 255
        pb[i] = (bb[i] * av + 127) // 255
    prem = Image.merge("RGBA", (
        Image.frombytes("L", (w, h), bytes(pr)),
        Image.frombytes("L", (w, h), bytes(pg)),
        Image.frombytes("L", (w, h), bytes(pb)),
        a,
    )).resize((new_w, target_h), Image.Resampling.HAMMING)

    rr, gg, bb2, aa = prem.split()
    r2, g2, b2, a2 = rr.tobytes(), gg.tobytes(), bb2.tobytes(), aa.tobytes()
    out_r = bytearray(len(a2))
    out_g = bytearray(len(a2))
    out_b = bytearray(len(a2))
    out_a = bytearray(a2)
    for i, av in enumerate(a2):
        if av >= 10:
            out_r[i] = min(255, (r2[i] * 255 + av // 2) // av)
            out_g[i] = min(255, (g2[i] * 255 + av // 2) // av)
            out_b[i] = min(255, (b2[i] * 255 + av // 2) // av)
        else:
            out_a[i] = 0
    return Image.merge("RGBA", (
        Image.frombytes("L", (new_w, target_h), bytes(out_r)),
        Image.frombytes("L", (new_w, target_h), bytes(out_g)),
        Image.frombytes("L", (new_w, target_h), bytes(out_b)),
        Image.frombytes("L", (new_w, target_h), bytes(out_a)),
    ))


def export_one(skin_id: str, src_path: str, out_dir: str, target_h: int) -> None:
    with Image.open(src_path) as im:
        w, h = im.size
        is_checker = _is_checkerboard_bg(im)
        left_w = int(w * 0.375) if is_checker else int(w * 0.42)
        left_slice = im.crop((0, 0, left_w, h))
        seeds = EXTRA_HOLE_SEEDS.get(skin_id)
        if is_checker:
            rgba = key_checkerboard_clean(left_slice, extra_seeds=seeds)
        else:
            rgba = key_white_clean(
                left_slice,
                t_bg=238,
                band=4,
                alpha_floor=12,
                extra_seeds=seeds,
            )
        fig = crop_left_figure(rgba)
        out_im = resize_premultiplied(fig, target_h)

    dst_dir = os.path.join(out_dir, skin_id)
    os.makedirs(dst_dir, exist_ok=True)
    dst_path = os.path.join(dst_dir, "preview.png")
    out_im.save(dst_path, optimize=True)

    # 同步导出头肩特写正方形大头贴 avatar.png (128x128)
    av_im = make_head_avatar(out_im, 128, skin_id)
    av_path = os.path.join(dst_dir, "avatar.png")
    av_im.save(av_path, optimize=True)
    print(f"[OK] {skin_id:<16} {out_im.size}  {os.path.getsize(dst_path)/1024:.1f} KB -> {dst_path} (+ avatar.png)")


def make_head_avatar(preview_im: Image.Image, size: int = 128, skin_id: str = "") -> Image.Image:
    """从全身立绘 preview.png 裁出头肩特写正方形大头贴，严格按双眼对称中心水平居中。"""
    w, h = preview_im.size
    # 锁定面部区间 (y in 0.33h..0.48h, x in 0.25w..0.72w) 的深色眼睫像素，彻底避开右侧鲸鱼尾巴干扰
    px = preview_im.load()
    eye_xs = [
        x for y in range(int(h * 0.33), int(h * 0.48))
        for x in range(int(w * 0.25), int(w * 0.72))
        if px[x, y][3] > 200 and max(px[x, y][:3]) < 65
    ]
    cx = (min(eye_xs) + max(eye_xs)) * 0.5 if eye_xs else w * 0.5
    if skin_id == "burger_crew":
        # 鲸堡店员高马尾把整体拉高，适当缩小裁切框并保留顶部呆毛
        crop_side = int(round(h * 0.65))
        y0 = 0
    else:
        crop_side = int(round(h * 0.68))  # 覆盖呆毛帽顶到胸口领结/肩部
        y0 = 0
    half = crop_side * 0.5
    x0 = int(round(cx - half))
    # 建立透明画布并贴入裁切区（防止贴边溢出丢失边缘）
    sq = Image.new("RGBA", (crop_side, crop_side), (0, 0, 0, 0))
    sx0 = max(0, x0)
    sy0 = max(0, y0)
    sx1 = min(w, x0 + crop_side)
    sy1 = min(h, y0 + crop_side)
    if sx1 > sx0 and sy1 > sy0:
        sq.alpha_composite(preview_im.crop((sx0, sy0, sx1, sy1)), (sx0 - x0, sy0 - y0))
    return resize_premultiplied(sq, size) if crop_side != size else sq


def main() -> None:
    ap = argparse.ArgumentParser(description="导出皮肤透明立绘预览图")
    ap.add_argument("--target-h", type=int, default=TARGET_H)
    args = ap.parse_args()

    default_src = os.path.join("image", "player", "whale_maid_character_turnaround.jpg")
    if os.path.isfile(default_src):
        export_one("default", default_src, SKINS_OUT_DIR, args.target_h)

    if not os.path.isdir(SKINS_SRC_DIR):
        sys.exit(f"缺少源目录: {SKINS_SRC_DIR}")
    for skin_id in sorted(os.listdir(SKINS_SRC_DIR)):
        if skin_id in SKIP_SKINS:
            continue
        skin_dir = os.path.join(SKINS_SRC_DIR, skin_id)
        if not os.path.isdir(skin_dir):
            continue
        src = find_turnaround(skin_dir)
        if src is None:
            print(f"[跳过] {skin_id}: 未找到 character_turnaround.*")
            continue
        export_one(skin_id, src, SKINS_OUT_DIR, args.target_h)


if __name__ == "__main__":
    main()
