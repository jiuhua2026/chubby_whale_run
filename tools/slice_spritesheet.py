#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
slice_spritesheet —— 把鲸鱼娘精灵表切成单帧序列 + JSON 帧数据。

为什么不能等宽硬切
------------------
三张表都是 AI 生成，帧宽帧距完全不规则：
  run   15 帧，内容中心步距 133~142（2064 除不尽，无可用等分网格）
  jump  13 帧，沿抛物线排列，y 从 218 跨到 549
  slide 18 帧，3 行的帧数还不一样（7 / 5 / 6）
按统一网格硬切，角色相对均匀网格的累计偏差可达 12px（角色本身才 115px 宽）。

两条轴都逐帧归一化（这是本脚本的关键）
---------------------------------------
  X 与 Y 在源表里**都是排版轴**：帧是从左到右「摆」开的，纵向位置也只是排版。
  平台游戏里角色的世界位置由物理持有，帧内的排版位移必须全部归零，
  否则锚点会把排版位移当成动作，表现为「跳高翻倍」「滑铲浮空」。

      → anchorX 取该帧自身「头部区域水平中心」（头部比包围盒中心稳：
        手脚伸展会改变包围盒宽度，但不会改变头的位置）。
      → anchorY 取该帧自身**轮廓最低点**（脚底），把脚钉在世界原点。
        这恰恰是在**消除**上下抖动，不是在放大它 —— 这里曾经误判过：
        以为「逐帧脚底归一化把素材误差放大成抖动」，于是想改成行带共同基准，
        其实方向是反的。头部出现的起伏来自各帧包围盒高度差，那是素材问题。

  遗留的 anchor_mode="band"（行带共同基准）只作对比回退，不要当默认值。

  另外 slide 是多行表，行与行之间的距离（跨了 750px）纯属排版，
  锚点必须按行带分别计算，不能用全表最低点。

缩放归一化
----------
三张表实测比例不同（头部模板 NCC 标定）：run 1.00 / jump 1.26 / slide 1.40。
不归一化的话三组动作拼在一起角色会忽大忽小。重采样必须「预乘 alpha → 缩放 →
反预乘」，直接缩 RGBA 会让透明区（黑）渗进边缘形成暗边。

用法
----
源图（带文字标注的黑底 jpg）**不能直接切**，要先过前两步：
    python tools/_work/strip_labels.py                  # ① 剔除文字标注（自带逐位比对自检）
    python tools/png_alpha_key.py *_clean.png -o alpha --bg black   # ② 抠成透明
然后切图（**必须显式传 --action**；换素材还要带 --color-ref-path，否则静默跳过色彩对齐）：
    python tools/slice_spritesheet.py alpha/111_clean.png --action run --scale 2.4962 \
        -o slices --verify --color-ref-path alpha/333_clean.png
三张一起（用内置 DEFAULT_SHEETS，前提是 ①② 已跑完）：
    python tools/slice_spritesheet.py --batch --outdir sprites --verify
"""

import argparse
import json
import os
import sys
from array import array
from collections import defaultdict, deque

try:
    from PIL import Image, ImageChops, ImageDraw
except ImportError:  # pragma: no cover
    sys.exit("需要 Pillow：pip install Pillow")


# 三张表实测的相对缩放。数值 = 该表角色的像素尺寸 ÷ 「统一基准尺寸」。
# 切图时按 s = ref_scale / KNOWN_SCALE[action] 缩放，让三套动作的**角色高度一致**。
#
# 统一基准 = 131.6 px（由旧 run 的「块高中位 294 / 2.2333」反推，沿用不改）。
#
# 2026-09-26 晚 · 第二次重新标定（用户交了三张新分镜图 111/222/333）
# ---------------------------------------------------------------
# 标定方法沿用项目既有口径，**分动作用不同特征**：
#   run  —— 块高中位。跑步全程站姿，块高即角色高度，而**屏幕高度**决定碰撞盒
#           与跳跃距离，按头部归一会让跑步"缩水"。
#   jump / slide —— 姿势变化大（收腿抱膝、趴地滑铲），块高不等于角色高度，
#           本应改用头部尺寸。但实测发现新素材三张的**头身比例彼此不同**
#           （头饰圆环孔径：111 宽 40px、222 33px、333 26px），
#           用头部标定与用块高标定会给出相差 20% 的两套结果，不可兼得。
#           既然项目约定的是「角色高度对齐到 131.6」，此处统一改用
#           **站立姿势的块高**（三张新图都有明确的站立帧）：
#             新 run(111)  —— 8 帧全是跑步站姿，取块高中位 327.0
#             新 jump(222) —— 帧10「恢复站立」块高 308
#             新 slide(333)—— 帧9「恢复直立」块高 257
#           ⇒ 327.0/131.6=2.4848 ｜ 308/131.6=2.3404 ｜ 257/131.6=1.9529
#
# ⚠ 已知遗留：旧表本身就不自洽 —— 用头饰圆环的孔直径做统一标尺换算，
#   旧 run 的归一化值是 11.22，而旧 jump / slide 是 9.26 / 9.50（差 19.6%）。
#   即现有游戏里 **run 的头部比 jump/slide 大近 20%**。这是既存问题，
#   与本轮换素材无关，未擅自"修正"（修正会让角色尺寸突变）。
KNOWN_SCALE = {"run": 2.4848, "jump": 2.3404, "slide": 1.9529}

NEI8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
ALPHA_T = 16
HEAD_BAND = 0.45          # 头部区域占包围盒高度的比例


# ---------------------------------------------------------------- 连通域

def find_blobs(im, min_area):
    """返回 (blobs, labels)。

    blobs：每个连通块的 dict（包围盒、像素数、头部区域水平中心 cx、id）。
    labels：array('H')，逐像素记录所属连通块的 id；0 = 不属于任何保留连通块
            （背景、太小的碎块、以及 alpha 低于 ALPHA_T 的边缘像素）。
            **切图时用它过滤，只保留本帧自己的像素——见 slice_sheet 里的说明。**

    cx 取包围盒顶部 HEAD_BAND 行内轮廓的 x 中心。
    比包围盒中心稳：手脚伸展会改变包围盒宽度，但不会改变头。
    """
    w, h = im.size
    ap = im.getchannel("A").point(lambda v: 255 if v > ALPHA_T else 0).load()
    seen = bytearray(w * h)
    labels = array("H", bytes(2 * w * h))
    out = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or ap[sx, sy] == 0:
                continue
            dq = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            pix = []
            x0 = x1 = sx
            y0 = y1 = sy
            while dq:
                x, y = dq.popleft()
                pix.append((x, y))
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
                for dx, dy in NEI8:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and ap[nx, ny]:
                        seen[ny * w + nx] = 1
                        dq.append((nx, ny))
            if len(pix) < min_area:
                continue
            bid = len(out) + 1
            for px_, py_ in pix:
                labels[py_ * w + px_] = bid
            top = y0 + int((y1 - y0 + 1) * HEAD_BAND)
            hx = [px for px, py in pix if py <= top]
            out.append({"id": bid,
                        "x0": x0, "y0": y0, "x1": x1, "y1": y1,
                        "n": len(pix), "cx": (min(hx) + max(hx)) / 2.0})
    return out, labels


def find_bands(blobs, w, h, gap=6):
    """全图 y 投影找行带（空白 > gap 处断开）。"""
    mask = bytearray(w * h)
    for b in blobs:
        for y in range(b["y0"], b["y1"] + 1):
            base = y * w
            for x in range(b["x0"], b["x1"] + 1):
                mask[base + x] = 1
    rows = [y for y in range(h) if any(mask[y * w + x] for x in range(w))]
    bands = []
    if rows:
        s = prev = rows[0]
        for y in rows[1:]:
            if y - prev > gap:
                bands.append((s, prev))
                s = y
            prev = y
        bands.append((s, prev))
    return bands


def order_frames(blobs, bands):
    """行带内按 x 排序 -> 正确的读帧顺序。

    这一步是为 jump 准备的：它虽然只有一行，但沿弧线排列，
    若按 y 分组会打乱左右顺序。
    """
    def band_of(b):
        cy = (b["y0"] + b["y1"]) / 2.0
        for i, (by0, by1) in enumerate(bands):
            if by0 <= cy <= by1:
                return i
        return len(bands)
    return sorted(blobs, key=lambda b: (band_of(b), b["x0"]))


# ---------------------------------------------------------------- 缩放

def resize_rgba(img, size):
    """预乘 alpha -> 缩放 -> 反预乘，避免透明区渗色形成暗边。"""
    w, h = img.size
    nw, nh = size
    if (nw, nh) == (w, h):
        return img.copy()
    r, g, b, a = img.split()
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


# ---------------------------------------------------------------- 色彩归一化
#
# 三张表来自两次不同的 AI 生成（run 是一次，jump + slide 是另一次），
# 角色的配色跟着生成的随机性漂移了：
#   run   蓝色偏灰、整体暗一档   （B 中位 130 / S 107 / V 130）
#   jump  比 slide 略暗          （B 中位 140 / S 132 / V 141）
#   slide 最鲜明（用户认定最好） （B 中位 154 / S 133 / V 156）
#
# 色相 H 三张完全一致（155~172 分布一模一样），说明是同一套配色、只是光照强度不同，
# 所以可以安全地做「逐通道直方图匹配」——比调亮度/饱和度的参数化方法更精确，
# 一次就把明度和饱和度都对齐了（提亮 B 通道等价于同时提亮 + 提饱和）。
#
# 统计只用**实心像素**（alpha > SOLID_ALPHA）：半透明边缘是抠图留下的暗边，
# 三张表都有，不参与统计免得干扰结果。

COLOR_REF_ACTION = "slide"     # 基准表：三张里色彩最鲜明的那套
SOLID_ALPHA = 240


def _solid_mask(im):
    return im.getchannel("A").point(lambda v: 255 if v > SOLID_ALPHA else 0)


def _cdf(hist):
    tot = sum(hist) or 1
    out = []
    acc = 0
    for v in hist:
        acc += v
        out.append(acc / tot)
    return out


def _smooth_monotone(lut, passes=2):
    """轻微平滑 LUT 并强制单调不减，避免量化产生色带。"""
    out = list(lut)
    for _ in range(passes):
        nxt = out[:]
        for i in range(1, 256):
            nxt[i] = (out[i - 1] + 2 * out[i] + out[min(i + 1, 255)]) // 4
        for i in range(1, 256):
            if nxt[i] < nxt[i - 1]:
                nxt[i] = nxt[i - 1]
        out = nxt
    return out


def build_color_lut(src_im, ref_im):
    """源表 -> 参考表 的逐通道直方图匹配 LUT，返回 [R, G, B] 各 256 项。

    直方图匹配（histogram specification）：让源表的通道分布与参考表完全一致，
    因此色彩、明度、饱和度一次性对齐，不需要手动调三个参数。
    """
    ref_rgb = ref_im.convert("RGB")
    ref_mask = _solid_mask(ref_im)
    rgb = src_im.convert("RGB")
    src_mask = _solid_mask(src_im)
    luts = []
    for c in range(3):
        cs = _cdf(rgb.getchannel(c).histogram(src_mask))
        cd = _cdf(ref_rgb.getchannel(c).histogram(ref_mask))
        lut = [0] * 256
        j = 0
        for v in range(256):
            while j < 255 and cd[j] < cs[v]:
                j += 1
            lut[v] = j
        luts.append(_smooth_monotone(lut))
    return luts


def apply_color_lut(im, luts):
    r, g, b, a = im.split()
    return Image.merge("RGBA", (r.point(luts[0]), g.point(luts[1]), b.point(luts[2]), a))


def build_sv_lut(post_rgb_im, ref_im):
    """在 RGB 直方图匹配**之后**，再把 S / V 两个通道也对齐到参考表。返回 [S, V] 各 256 项。

    为什么还需要这一步：S / V 是 R/G/B 的**非线性组合**，
    「逐通道 RGB 直方图匹配」**不等于** S / V 匹配。
    实测（2026-09-26 的 run 表）：RGB 匹配后中位色已经和 slide 一致（偏差 2 级以内），
    但 S 仍高 4 级、V 高 2 级 —— 肉眼就读作"这一张好像偏亮/偏艳"。
    补上 S / V 的直方图匹配后，S / V 中位与参考表完全一致（132 / 156 = slide 的 132 / 156）。

    色相 H **不动**：三套表本来就出自同一套配色（H 分布一致），动 H 只会引入偏色。
    """
    src_hsv = post_rgb_im.convert("RGB").convert("HSV")
    ref_hsv = ref_im.convert("RGB").convert("HSV")
    src_mask = _solid_mask(post_rgb_im)
    ref_mask = _solid_mask(ref_im)
    luts = []
    for ch in ("S", "V"):
        cs = _cdf(src_hsv.getchannel(ch).histogram(src_mask))
        cd = _cdf(ref_hsv.getchannel(ch).histogram(ref_mask))
        lut = [0] * 256
        j = 0
        for v in range(256):
            while j < 255 and cd[j] < cs[v]:
                j += 1
            lut[v] = j
        luts.append(_smooth_monotone(lut))
    return luts


def apply_sv_lut(im, sv_luts):
    """把 S / V 的 LUT 套到图上（H 与原 alpha 不变）。"""
    hsv = im.convert("RGB").convert("HSV")
    h, s, v = hsv.split()
    out = Image.merge("HSV", (h, s.point(sv_luts[0]), v.point(sv_luts[1])))
    out = out.convert("RGB").convert("RGBA")
    out.putalpha(im.getchannel("A"))
    return out


def _lut_summary(luts):
    probes = (32, 96, 160, 224)
    return "  ".join("%s %s" % (ch, " ".join("%d->%d" % (v, luts[c][v]) for v in probes))
                     for c, ch in enumerate("RGB"))


def _probe(lut):
    """单条 LUT 的抽样映射，打印用。"""
    return " ".join("%d->%d" % (v, lut[v]) for v in (32, 96, 160, 224))


def _channel_medians(im):
    """实心像素的 R/G/B 中位，用于自检。"""
    m = _solid_mask(im)
    rgb = im.convert("RGB")
    out = []
    for c in range(3):
        h = rgb.getchannel(c).histogram(m)
        tot = sum(h) * 0.5
        acc = 0
        for v, n in enumerate(h):
            acc += n
            if acc >= tot:
                out.append(v)
                break
        else:
            out.append(0)
    return out


def _sv_medians(im):
    """实心像素的 S / V 中位，用于自检（S/V 是感知上的"艳不艳、亮不亮"）。"""
    m = _solid_mask(im)
    hsv = im.convert("RGB").convert("HSV")
    out = []
    for ch in ("S", "V"):
        h = hsv.getchannel(ch).histogram(m)
        tot = sum(h) * 0.5
        acc = 0
        for v, n in enumerate(h):
            acc += n
            if acc >= tot:
                out.append(v)
                break
        else:
            out.append(0)
    return out


def verify_color_lut(src_im, luts, ref_im, action, ref_action, tol=14, sv_luts=None):
    """自检：套上 LUT 后源表中位色应当贴近参考表。

    加这道检查是因为 LUT 用错通道（比如把 B 的表套到 G 上）不会报错、
    只会悄悄把颜色弄花，肉眼在缩略图上很难发现。
    2026-09-26 起追加 S / V 中位检查 —— RGB 对齐了但 S/V 没对齐，
    肉眼就是"这一套偏亮/偏艳"，前面就是这么漏过去的。
    """
    graded = apply_color_lut(src_im, luts)
    s = _channel_medians(graded)
    r = _channel_medians(ref_im)
    d = max(abs(s[i] - r[i]) for i in range(3))
    ok = d <= tol
    print("       自检 %s->%s  RGB 校正后 %s  基准 %s  最大偏差 %d  %s"
          % (action, ref_action, s, r, d, "OK" if ok else "!! 偏差过大，检查 LUT 用错通道"))
    if sv_luts is not None:
        graded2 = apply_sv_lut(graded, sv_luts)
        sv_s = _sv_medians(graded2)
        sv_r = _sv_medians(ref_im)
        dv = max(abs(sv_s[i] - sv_r[i]) for i in range(2))
        ok2 = dv <= 4
        ok = ok and ok2
        print("       自检 %s->%s  S/V 校正后 S%d V%d  基准 S%d V%d  最大偏差 %d  %s"
              % (action, ref_action, sv_s[0], sv_s[1], sv_r[0], sv_r[1], dv,
                 "OK" if ok2 else "!! S/V 未对齐"))
    return ok


# ---------------------------------------------------------------- 主流程

def slice_sheet(src, action, sheet_scale, ref_scale, outdir, min_area=800, fps=12,
                verify=False, anchor_mode="frame", color_luts=None, color_ref=None,
                sv_luts=None):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    blobs, labels = find_blobs(im, min_area)
    if not blobs:
        print(f"[跳过] {src} 没找到任何帧")
        return None
    bands = find_bands(blobs, w, h)
    ordered = order_frames(blobs, bands)

    bi_of = {}
    for i, (by0, by1) in enumerate(bands):
        for b in ordered:
            cy = (b["y0"] + b["y1"]) / 2.0
            if by0 <= cy <= by1:
                bi_of[id(b)] = i

    s = ref_scale / sheet_scale

    band_bottom, band_top = {}, {}
    for b in ordered:
        bi = bi_of[id(b)]
        band_bottom[bi] = max(band_bottom.get(bi, 0), b["y1"])
        band_top[bi] = min(band_top.get(bi, 10 ** 9), b["y0"])

    d = os.path.join(outdir, action)
    os.makedirs(d, exist_ok=True)

    frames = []
    for i, b in enumerate(ordered):
        x0, y0, x1, y1 = b["x0"], b["y0"], b["x1"], b["y1"]
        bi = bi_of[id(b)]
        fw, fh = x1 - x0 + 1, y1 - y0 + 1
        crop = im.crop((x0, y0, x1 + 1, y1 + 1))
        # 只保留属于本帧连通块的像素。**这一步不是可选的**：
        # 各帧的包围盒互相重叠（实测相邻帧最多叠 10px），直接按矩形裁下来，
        # 会把邻帧的头发、以及夹缝里的小碎点一起框进画面——
        # 在游戏里就表现为角色旁边飘着几片不明碎片。
        # 按连通块 id 过滤即可，顺带也把 alpha 低于 ALPHA_T 的边缘噪点清掉。
        m = Image.new("L", crop.size, 0)
        pm = m.load()
        bid = b["id"]
        for yy in range(y0, y1 + 1):
            base = yy * w
            dy = yy - y0
            for xx in range(x0, x1 + 1):
                if labels[base + xx] == bid:
                    pm[xx - x0, dy] = 255
        crop.putalpha(ImageChops.multiply(crop.getchannel("A"), m))
        # 色彩归一化要在缩放之前做：LUT 是按源图分辨率的像素值定义的。
        if color_luts is not None:
            crop = apply_color_lut(crop, color_luts)
        # 再做一次 S / V 对齐（RGB 逐通道匹配不等于 S/V 匹配，见 build_sv_lut 注释）。
        if sv_luts is not None:
            crop = apply_sv_lut(crop, sv_luts)
        if s != 1.0:
            crop = resize_rgba(crop, (max(1, int(round(fw * s))), max(1, int(round(fh * s)))))
        name = f"{action}_{i:02d}.png"
        crop.save(os.path.join(d, name))
        frames.append({
            "index": i,
            "band": bi,
            "file": name,
            "w": crop.width,
            "h": crop.height,
            # 引擎绘制：左上角 = (锚点屏幕坐标.x - anchorX, 锚点屏幕坐标.y - anchorY)
            "anchorX": round((b["cx"] - x0) * s, 2),   # 逐帧：抵消排版位移
            # anchorY：默认逐帧取该帧自己的脚底。
            "anchorY": round(((y1 - y0) if anchor_mode == "frame"
                              else (band_bottom[bi] - y0)) * s, 2),
            # 行带基准也一并留着，方便对比和回退
            "anchorYBand": round((band_bottom[bi] - y0) * s, 2),
            "srcBbox": [x0, y0, x1, y1],
            "srcCx": round(b["cx"], 1),
        })

    meta = {
        "action": action,
        "source": os.path.basename(src),
        "sourceSize": [w, h],
        "sourceScale": sheet_scale,
        "normalizedScale": ref_scale,
        "resampleFactor": round(s, 6),
        "fps": fps,
        # 色彩归一化记录：为 null 表示该表就是基准，未做任何改动
        "colorMatch": (None if color_luts is None else
                       {"method": "histogram_specification(RGB→HSV-SV)" if sv_luts is not None
                        else "histogram_specification(RGB)",
                        "reference": color_ref,
                        "svRefine": sv_luts is not None}),
        "anchorNote": "anchorX 逐帧取头部区域水平中心；anchorY 逐帧取轮廓最低点（脚底）"
                      " —— 两轴都归一化，帧内排版位移全部归零",
        "bands": [
            {"index": i, "y": [band_top[i], band_bottom[i]],
             "anchorY": round(band_bottom[i] * s, 2),
             "frames": sum(1 for f in frames if f["band"] == i)}
            for i in sorted(band_bottom)
        ],
        "frames": frames,
    }
    with open(os.path.join(d, f"{action}.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    print(f"[OK] {action:<6} 帧数 {len(frames):>2}  行带 {len(bands)}  重采样 x{s:.3f}"
          f"  色彩 {'对齐到 ' + str(color_ref) + ('（含 S/V）' if sv_luts is not None else '') if color_luts is not None else '基准/未改'}  -> {d}")
    for bd in meta["bands"]:
        print(f"       行带{bd['index']}  {bd['frames']} 帧  y[{bd['y'][0]},{bd['y'][1]}]")
    if verify:
        make_verify(frames, d, action)
        print(f"       对齐校验图 -> {os.path.join(d, action + '_aligned.png')}")
    return meta


def make_verify(frames, d, action):
    """按锚点把同一行带的帧全叠在一起：对齐正确的话，叠图是干净的一张轮廓。"""
    byband = defaultdict(list)
    for f in frames:
        byband[f["band"]].append(f)

    strips = []
    for bi in sorted(byband):
        fs = byband[bi]
        lefts = [-f["anchorX"] for f in fs]
        tops = [-f["anchorY"] for f in fs]
        ox = min(lefts) - 20
        oy = min(tops) - 20
        W = int(max(l + f["w"] for l, f in zip(lefts, fs)) - ox + 20)
        H = int(max(t + f["h"] for t, f in zip(tops, fs)) - oy + 20)
        canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for l, t, f in zip(lefts, tops, fs):
            canvas.alpha_composite(Image.open(os.path.join(d, f["file"])),
                                   (int(l - ox), int(t - oy)))
        bg = Image.new("RGBA", (W, H), (250, 250, 252, 255))
        bg.alpha_composite(canvas)
        dr = ImageDraw.Draw(bg)
        ax, ay = -ox, -oy
        dr.line([(ax - 14, ay), (ax + 14, ay)], fill=(230, 60, 60, 255), width=2)
        dr.line([(ax, ay - 14), (ax, ay + 14)], fill=(230, 60, 60, 255), width=2)
        dr.text((6, 4), f"{action}  band{bi}  n={len(fs)}", fill=(30, 30, 30, 255))
        strips.append(bg.convert("RGB"))

    W = max(s.width for s in strips) + 20
    H = sum(s.height for s in strips) + 20 * (len(strips) + 1)
    out = Image.new("RGB", (W, H), (236, 236, 240))
    y = 20
    for st in strips:
        out.paste(st, (10, y))
        y += st.height + 20
    out.save(os.path.join(d, f"{action}_aligned.png"))


# ---------------------------------------------------------------- 入口

# 当前在用的三张「可直接切图的精灵表」= 已剔除标注 + 已抠图的透明 PNG。
#
# ⚠ **源图和可切图表不是一回事**：源图是 `image/player/pixel_art/` 下的
#   111/222/333.jpg，但它① 带文字标注、② 是黑底，**不能直接切**，必须先过
#     strip_labels.py（剔除标注）→ png_alpha_key.py（抠成透明）
#   产出下面这三个 _clean.png 才能切。
DEFAULT_SHEETS = [
    ("tools/_work/alpha/111_clean.png", "run"),
    ("tools/_work/alpha/222_clean.png", "jump"),
    ("tools/_work/alpha/333_clean.png", "slide"),
]


def main():
    ap = argparse.ArgumentParser(description="精灵表 -> 单帧序列 + JSON")
    ap.add_argument("sheets", nargs="*", help="表文件（--batch 时可省略）")
    ap.add_argument("--action", default=None, help="动作名，决定缩放基准")
    ap.add_argument("--scale", type=float, default=None,
                    help="该表角色相对 run 的实测放大倍率，默认取内置标定值")
    ap.add_argument("--ref-scale", type=float, default=1.00,
                    help="统一到的目标倍率，默认 1.00（即 run 的原始比例）")
    ap.add_argument("-o", "--outdir", default="sprites")
    ap.add_argument("--min-area", type=int, default=800)
    ap.add_argument("--fps", type=int, default=12)
    ap.add_argument("--anchor-mode", choices=("frame", "band"), default="frame",
                    help="anchorY 取法：frame=逐帧自己的脚底（默认，推荐）；band=行带共同基准")
    ap.add_argument("--no-color-match", action="store_true",
                    help="关闭色彩归一化（默认把非基准表对齐到基准表）")
    ap.add_argument("--no-sv-match", action="store_true",
                    help="只做 RGB 逐通道匹配，不做 S/V 对齐。"
                         "默认开启 S/V 对齐：RGB 匹配不等于 S/V 匹配，"
                         "少了这步会残留「这套偏亮/偏艳」的观感（见 build_sv_lut 注释）")
    ap.add_argument("--color-ref", default=COLOR_REF_ACTION,
                    help=f"色彩基准动作，默认 {COLOR_REF_ACTION}（三张里最鲜明的那套）")
    ap.add_argument("--color-ref-path", default=None,
                    help="显式指定色彩基准表的**文件路径**。换素材时基准表也换了文件名"
                         "（默认只会在内置的旧表路径里找，找不到就静默跳过对齐），"
                         "所以换素材务必带上这个参数。")
    ap.add_argument("--batch", action="store_true", help="处理内置的三张默认表")
    ap.add_argument("--verify", action="store_true", help="输出锚点叠加校验图")
    args = ap.parse_args()

    jobs = []
    if args.batch or not args.sheets:
        for p, a in DEFAULT_SHEETS:
            jobs.append((p, a, KNOWN_SCALE[a]))
    else:
        for p in args.sheets:
            if args.action:
                a = args.action
            else:
                stem = os.path.splitext(os.path.basename(p))[0]
                a = stem.replace("whale_maid_", "").replace("_spritesheet", "")
                # 文件名推导只对旧命名（whale_maid_xxx_spritesheet.png）有效。
                # 新素材叫 111_clean.png 之类，会推出 "111_clean" 这种无效动作名，
                # 而 KNOWN_SCALE.get(a, 1.0) 会**静默回退到 1.0** —— 切出来的角色
                # 尺寸全错却不报错。这类"结果悄悄错掉"必须在源头拦住。
                if a not in KNOWN_SCALE:
                    sys.exit(f"[错误] 无法从文件名 {stem!r} 推导出动作名。"
                             f"有效动作：{sorted(KNOWN_SCALE)}。请显式传 --action。")
            jobs.append((p, a, args.scale if args.scale is not None else KNOWN_SCALE[a]))

    # 基准表只加载一次，各表共用
    ref_im = None
    if not args.no_color_match:
        if args.color_ref_path:
            if os.path.isfile(args.color_ref_path):
                ref_im = Image.open(args.color_ref_path).convert("RGBA")
                print(f"[色彩] 基准表 = {args.color_ref_path}")
            else:
                print(f"[警告] --color-ref-path 指向的文件不存在：{args.color_ref_path}")
        else:
            for p, a in DEFAULT_SHEETS:
                if a == args.color_ref and os.path.isfile(p):
                    ref_im = Image.open(p).convert("RGBA")
                    break
        if ref_im is None:
            print(f"[警告] 找不到色彩基准表 {args.color_ref}，跳过色彩归一化")

    for path, action, sc in jobs:
        if not os.path.isfile(path):
            print("跳过（不存在）:", path)
            continue
        luts = None
        sv_luts = None
        if ref_im is not None and action != args.color_ref:
            src_im = Image.open(path).convert("RGBA")
            luts = build_color_lut(src_im, ref_im)
            print(f"[色彩] {action} 对齐到 {args.color_ref}：{_lut_summary(luts)}")
            if not args.no_sv_match:
                # S/V 的 LUT 要基于「已做 RGB 匹配之后」的图来算
                sv_luts = build_sv_lut(apply_color_lut(src_im, luts), ref_im)
                print(f"       S/V 对齐：S {_probe(sv_luts[0])}   V {_probe(sv_luts[1])}")
            verify_color_lut(src_im, luts, ref_im, action, args.color_ref, sv_luts=sv_luts)
        slice_sheet(path, action, sc, args.ref_scale, args.outdir,
                    args.min_area, args.fps, args.verify, args.anchor_mode,
                    luts, args.color_ref, sv_luts)


if __name__ == "__main__":
    main()
