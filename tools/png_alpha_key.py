#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
black-key-to-alpha —— 把「纯黑背景」的精灵表转成带透明通道的 PNG。

为什么不是简单的亮度阈值
------------------------
这张图的情况：背景是纯黑 (0,0,0)，角色**没有黑描边**，但角色本体是深蓝藏青，
最暗处 max(R,G,B)≈39，而 JPG 压缩在背景上留下的噪点最高约 24。
两者只差 15，单纯用一个亮度阈值切，一定会二选一翻车：
  · 阈值调高 → 深蓝衣摆、头发阴影被啃出半透明斑块；
  · 阈值调低 → 背景噪点残留成灰边。

所以采用「距离分层」算法：
  1. key = max(R,G,B)，作为离背景黑的距离度量。
  2. 对 key <= t_dark 的像素做连通域分析：
       - 接触画布边框的连通域      → 外部背景
       - 被包围且面积很小的连通域  → 镂空/缝隙（如双腿之间、发髻内孔），同样算背景
     得到确定的背景集合 bg。
  3. 以 bg 为多源做 BFS，得到每个前景像素到背景的「距离环数」dist。
       - dist == 0            → alpha = 0
       - 1 <= dist <= ring     → alpha 由 key 线性羽化（还原原图抗锯齿边缘）
       - dist > ring           → alpha = 255（内部一律实心，杜绝半透明斑块）
  4. 反预乘 un-premultiply：原图是黑底合成结果 P = F·a，
     故 F = P / a。不做这步，半透明边缘贴到浅色背景会出现暗边——
     这是「抠黑底」最经典的翻车点。
  5. --hard 模式：不做羽化，alpha 只有 0/255。此时不做反预乘，
     保留的像素 RGB 与原图**逐位完全相同**，是最严格意义的无损，
     且边缘对像素画来说更锐利。

用法
----
    python png_alpha_key.py 输入图 [-o 输出目录] [--hard]
        [--t-dark 24] [--ring 2] [--ref 48] [--pocket 600]
        [--preview 预览目录] [--preview-frame N]
"""

import argparse
import os
import sys
from collections import deque

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    sys.exit("需要 Pillow：pip install Pillow")


# ---------------------------------------------------------------- 基础工具

def build_key(im):
    """key[i] = max(R,G,B)，比 sum 更抗色偏。

    用 bytes 切片 + map(max) 走 C 层，比逐像素循环快一个量级
    （150 万像素的精灵表尤其明显）。
    """
    data = im.tobytes()
    return bytearray(map(max, data[0::3], data[1::3], data[2::3]))


NEI8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))


def classify_background(key, w, h, t_dark, pocket_max):
    """返回 bytearray，1 = 背景（含外部背景 + 小面积镂空）。"""
    bg = bytearray(w * h)
    seen = bytearray(w * h)
    for start in range(w * h):
        if seen[start] or key[start] > t_dark:
            continue
        # 收集一个连通域
        comp = [start]
        seen[start] = 1
        dq = deque((start,))
        touches_border = False
        while dq:
            i = dq.popleft()
            y, x = divmod(i, w)
            if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                touches_border = True
            for dx, dy in NEI8:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    n = ny * w + nx
                    if not seen[n] and key[n] <= t_dark:
                        seen[n] = 1
                        comp.append(n)
                        dq.append(n)
        if touches_border or len(comp) <= pocket_max:
            for i in comp:
                bg[i] = 1
    return bg


def distance_from_bg(bg, w, h, maxd):
    """多源 BFS，返回 dist 数组（超过 maxd 的截断为 maxd+1）。"""
    INF = maxd + 1
    dist = bytearray([INF]) * (w * h)
    dq = deque()
    for i in range(w * h):
        if bg[i]:
            dist[i] = 0
            dq.append(i)
    while dq:
        i = dq.popleft()
        d = dist[i]
        if d >= maxd:
            continue
        y, x = divmod(i, w)
        for dx, dy in NEI8:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                n = ny * w + nx
                if dist[n] == INF:
                    dist[n] = d + 1
                    dq.append(n)
    return dist


# ---------------------------------------------------------------- 主算法

def key_to_alpha(im, t_dark=24, ring=2, ref=48, pocket=600, hard=False):
    src = im.convert("RGB")
    w, h = src.size
    key = build_key(src)
    bg = classify_background(key, w, h, t_dark, pocket)
    dist = distance_from_bg(bg, w, h, ring)

    data = src.tobytes()
    buf = bytearray(w * h * 4)  # RGBA，默认全 0 = 全透明
    stats = {"transparent": 0, "opaque": 0, "feather": 0}

    for y in range(h):
        base = y * w
        for x in range(w):
            i = base + x
            d = dist[i]
            if d == 0:
                stats["transparent"] += 1
                continue
            j = i * 3
            r, g, b = data[j], data[j + 1], data[j + 2]
            if hard or d > ring:
                a = 1.0
            else:
                k = key[i]
                a = 1.0 if k >= ref else (k / float(ref))
                if a <= 0.0:
                    stats["transparent"] += 1
                    continue
            o = i * 4
            if a >= 1.0:
                stats["opaque"] += 1
                buf[o] = r
                buf[o + 1] = g
                buf[o + 2] = b
                buf[o + 3] = 255
            else:
                stats["feather"] += 1
                inv = 1.0 / a
                nr, ng, nb = int(r * inv + 0.5), int(g * inv + 0.5), int(b * inv + 0.5)
                buf[o] = 255 if nr > 255 else nr
                buf[o + 1] = 255 if ng > 255 else ng
                buf[o + 2] = 255 if nb > 255 else nb
                buf[o + 3] = int(a * 255 + 0.5)

    out = Image.frombytes("RGBA", (w, h), bytes(buf))
    return out, stats


# ---------------------------------------------------------------- 预览

def make_preview(rgba, path, frame_w=None):
    """白底 / 暗底 / 棋盘格 三行对比图。"""
    w, h = rgba.size
    bgw = Image.new("RGBA", (w, h), (255, 255, 255, 255)); bgw.alpha_composite(rgba)
    bgd = Image.new("RGBA", (w, h), (16, 16, 20, 255)); bgd.alpha_composite(rgba)
    ck = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(ck)
    for yy in range(0, h, 16):
        for xx in range(0, w, 16):
            c = (160, 160, 160) if ((xx // 16 + yy // 16) % 2) else (120, 120, 120)
            d.rectangle([xx, yy, xx + 15, yy + 15], fill=c + (255,))
    ck.alpha_composite(rgba)

    gap = 10
    canvas = Image.new("RGB", (w, h * 3 + gap * 2), (255, 0, 255))
    for i, t in enumerate((bgw, bgd, ck)):
        canvas.paste(t.convert("RGB"), (0, i * (h + gap)))
    # 大图（如 1254x1254 的滑铲表）预览会撑到几千万像素，按整数倍降采样
    while canvas.width > 1600 or canvas.height > 2400:
        canvas = canvas.resize((max(1, canvas.width // 2), max(1, canvas.height // 2)),
                               Image.LANCZOS)
    canvas.save(path)


# ---------------------------------------------------------------- 白底模式
#
# 另一条管线，给「AI 直接出的白底 RGB 图」用（没经历过黑底那一步）。
# 与黑底算法镜像：黑底 key = max(RGB) 找暗部，白底 key = min(RGB) 找亮部。
#
# 实测（run 表 1254x1254）：
#   背景        min 通道 253~255（占 94%）
#   角色的光晕  250~252（帧间空隙整段都在 250~251）
#   角色与抗锯齿 249 以下，且过渡带只有 1~4 像素宽
#
# 两个必须绕开的坑：
#
# 坑一：**角色身上的白蕾丝和背景同色**。纯按亮度阈值会把蕾丝一起抠掉。
#       现在的做法是靠「距背景的距离」判定内外：离背景超过 band 像素的就是角色内部，
#       alpha 直接给 1，根本不参与亮度判断。蕾丝自然保住。
#
# 坑二（第一版栽在这）：**把「阈值羽化」当成了通用做法**。
#       第一版写的是「距背景 2px 内才羽化、再往里一律实心」，
#       结果帧间空隙（离背景十几像素）被强制成不透明，15 帧粘成 1 个连通块，切图直接失败。
#       修掉之后又发现真正的病根在阈值位置：白底上 obs=230 的边缘像素
#       真实覆盖率只有 0.13，任何把它当「接近实心」的阈值都会在深色背景上
#       亮出 200 多级 —— 那就是用户看到的**白边**。
#       最终改成按合成公式反解覆盖率（见 key_white_to_alpha 的注释），白边才消失。
#
# 教训：源图底色已知时，**别用阈值猜 alpha，用合成公式算**。

def key_white_to_alpha(im, t_bg=250, band=4, alpha_floor=10):
    """白底 -> 透明。

    关键：不能用「按亮度阈值羽化」那类做法。白底合成满足
        obs = 前景*a + 255*(1-a)
    也就是真实覆盖率 a = (255-obs) / (255-前景)。角色暗部前景的最小通道约 56，
    所以 a ≈ (255-obs)/199 —— 一个 obs=230 的边缘像素真实覆盖率只有 **0.13**。
    任何把 230 当成「接近实心」的阈值都会得到白边：
    深色背景上它会亮 220×(a_错误 − a_真实) 级。

    所以这里的分工是：
      1. 背景 = min(R,G,B) >= t_bg 且与图像四边连通（挡住角色周围那圈淡光晕）。
      2. 算每个前景像素到背景的 BFS 距离；距离 > band 的算「角色内部」，alpha = 1。
         这样内部像素不会被反混合，不会整体变暗。
      3. 把内部像素的最小通道值向外多源 BFS，带到过渡带上——
         过渡带用「最近的角色内部颜色」作为前景来反解 a，对深色和浅色前景都成立。
      4. 按 a 反预乘。

    实测（run 表 1254x1254）：过渡带只有 1~4 像素，所以 band=4 足够。
    """
    im = im.convert("RGB")
    w, h = im.size
    n = w * h
    px = im.load()

    minc = bytearray(n)
    for y in range(h):
        row = y * w
        for x in range(w):
            r, g, b = px[x, y]
            minc[row + x] = min(r, g, b)

    # 1) 背景：亮 + 与四边连通
    bg = bytearray(n)
    dq = deque()
    for x in range(w):
        for y in (0, h - 1):
            i = y * w + x
            if minc[i] >= t_bg and not bg[i]:
                bg[i] = 1
                dq.append(i)
    for y in range(h):
        for x in (0, w - 1):
            i = y * w + x
            if minc[i] >= t_bg and not bg[i]:
                bg[i] = 1
                dq.append(i)
    while dq:
        i = dq.popleft()
        x, y = i % w, i // w
        if x > 0 and not bg[i - 1] and minc[i - 1] >= t_bg:
            bg[i - 1] = 1
            dq.append(i - 1)
        if x < w - 1 and not bg[i + 1] and minc[i + 1] >= t_bg:
            bg[i + 1] = 1
            dq.append(i + 1)
        if y > 0 and not bg[i - w] and minc[i - w] >= t_bg:
            bg[i - w] = 1
            dq.append(i - w)
        if y < h - 1 and not bg[i + w] and minc[i + w] >= t_bg:
            bg[i + w] = 1
            dq.append(i + w)

    # 2) 距背景的 BFS 距离，只走 band+2 层就够了。
    #    跑完后「dist==0 且不是背景」= 一直没被走到 = 角色内部。
    dist = bytearray(n)
    frontier = [i for i in range(n) if bg[i]]
    for lv in range(1, band + 3):
        nxt = []
        for i in frontier:
            x, y = i % w, i // w
            if x > 0 and not bg[i - 1] and dist[i - 1] == 0:
                dist[i - 1] = lv
                nxt.append(i - 1)
            if x < w - 1 and not bg[i + 1] and dist[i + 1] == 0:
                dist[i + 1] = lv
                nxt.append(i + 1)
            if y > 0 and not bg[i - w] and dist[i - w] == 0:
                dist[i - w] = lv
                nxt.append(i - w)
            if y < h - 1 and not bg[i + w] and dist[i + w] == 0:
                dist[i + w] = lv
                nxt.append(i + w)
        frontier = nxt
        if not frontier:
            break

    # deep = 可靠的前景样本。两条判据缺一不可：
    #   ① 离背景 > band 像素（大面积区域的主体）
    #   ② **局部最暗**——细结构（发丝、头顶那个 2~4px 的小圆环）整条都落在过渡带里，
    #      按①根本找不到样本，只能从几像素外去借，而借到的往往是同一条细结构上
    #      更亮的那一段 → 反解出 a≥1 → alpha 255 且保留亮原色 → 白边。
    deep = bytearray(n)
    for i in range(n):
        if bg[i]:
            continue
        if dist[i] == 0 or dist[i] > band:
            deep[i] = 1
            continue
        x, y = i % w, i // w
        v = minc[i]
        loc = True
        if x > 0 and not bg[i - 1] and minc[i - 1] < v:
            loc = False
        elif x < w - 1 and not bg[i + 1] and minc[i + 1] < v:
            loc = False
        elif y > 0 and not bg[i - w] and minc[i - w] < v:
            loc = False
        elif y < h - 1 and not bg[i + w] and minc[i + w] < v:
            loc = False
        if loc:
            deep[i] = 1

    # 3) 把「最近的角色内部」的颜色向外带到过渡带。
    #    除了最小通道（用来反解覆盖率），还要带上三个通道的**上限**：
    #    过渡带像素反预乘出来的颜色不应该比它旁边的角色内部更亮——
    #    否则 AI 画稿在轮廓外留下的那圈淡光晕会在深色背景上显成白边。
    #    （run 表的鞋/腿周围就有这么一圈，band 调大只能缓解、还会把身体一起洗淡。）
    #    **不设层数上限**：细长结构（1px 发丝、蕾丝边）整条都是 dist=1，
    #    上面的像素离最近的「内部」可能有十几像素远，限层数会让它们拿不到估计。
    cr = bytearray(n)
    cg = bytearray(n)
    cb = bytearray(n)
    cm = bytearray(n)
    has = bytearray(n)
    for i in range(n):
        if deep[i]:
            x, y = i % w, i // w
            r, g, b = px[x, y]
            cr[i] = r
            cg[i] = g
            cb[i] = b
            cm[i] = max(r, g, b)
            has[i] = 1
    frontier = [i for i in range(n) if deep[i]]
    while frontier:
        nxt = []
        for i in frontier:
            x, y = i % w, i // w
            for j, ok in ((i - 1, x > 0), (i + 1, x < w - 1),
                          (i - w, y > 0), (i + w, y < h - 1)):
                if ok and not bg[j] and not has[j]:
                    cr[j] = cr[i]
                    cg[j] = cg[i]
                    cb[j] = cb[i]
                    cm[j] = cm[i]
                    has[j] = 1
                    nxt.append(j)
        frontier = nxt

    # 4) 输出
    out = Image.new("RGBA", (w, h))
    po = out.load()
    st = {"transparent": 0, "opaque": 0, "feather": 0, "floor": 0,
          "orphan": 0, "dehalo": 0}
    for y in range(h):
        row = y * w
        for x in range(w):
            i = row + x
            r, g, b = px[x, y]
            if bg[i]:
                po[x, y] = (0, 0, 0, 0)
                st["transparent"] += 1
                continue
            if deep[i]:
                po[x, y] = (r, g, b, 255)
                st["opaque"] += 1
                continue
            if has[i]:
                # 前景最小通道：从带过来的颜色里现取
                fm = cr[i] if cr[i] < cg[i] else cg[i]
                if cb[i] < fm:
                    fm = cb[i]
                cap = cm[i]
            else:
                # 兜底：拿不到前景估计时，按「深色前景」算覆盖率。
                # **绝不能退回「不透明 + 原色」**——那样一个浅色像素
                # 就会在深色背景上直接变成白边（这正是之前的 bug）。
                fm = 40
                cap = 40
                st["orphan"] += 1
            den = 255 - fm
            a = 1.0 if den <= 0 else (255 - minc[i]) / den
            a = 0.0 if a < 0.0 else (1.0 if a > 1.0 else a)
            al = int(a * 255.0 + 0.5)
            if al < alpha_floor:
                # 覆盖率低到看不见的像素直接归零，否则会散落成一堆小碎点
                po[x, y] = (0, 0, 0, 0)
                st["floor"] += 1
                continue
            # 反预乘：前景 = (obs - 255*(1-a)) / a
            back = 255.0 * (1.0 - a)
            rr = int((r - back) / a + 0.5)
            gg = int((g - back) / a + 0.5)
            bb = int((b - back) / a + 0.5)
            # 去光晕：颜色不许比最近的角色内部更亮（等比压暗，保住色相）
            hi = rr if rr > gg else gg
            if bb > hi:
                hi = bb
            if hi > cap > 0:
                k = cap / float(hi)
                rr = int(rr * k + 0.5)
                gg = int(gg * k + 0.5)
                bb = int(bb * k + 0.5)
                st["dehalo"] += 1
            po[x, y] = (0 if rr < 0 else (255 if rr > 255 else rr),
                        0 if gg < 0 else (255 if gg > 255 else gg),
                        0 if bb < 0 else (255 if bb > 255 else bb), al)
            st["feather"] += 1
    return out, st


# ---------------------------------------------------------------- 去噪

def despeckle(out, thresh=70, rounds=2, max_alpha=200):
    """压掉孤立亮点：一个像素若比它四个邻域**都**亮出 thresh 以上，就把颜色压到邻域上限。

    针对 AI 出图的抖色颗粒。实测「内部孤立亮点占比」：
        run 0.49% ｜ jump 0.13% ｜ slide 0.07%
    run 表比另两张粗 4~7 倍，这些亮点在深色背景上会显成零星的白色小点。

    要点：
      · 只压颜色、**不动 alpha**，所以轮廓形状完全不变；
      · 判据是「比**最暗**的邻域还亮出 thresh」——孤立亮点周围的邻域都是暗的；
      · 但压到的目标是**最亮**的邻域，不是最暗的。
        压到最暗会把白蕾丝边缘（一侧挨着黑裙子）整条压成黑色，
        中间调变成土黄描边 —— 这是个很容易踩的坑。
      · 邻域里透明的不参与比较（否则轮廓边的像素会被压成黑色）。
    """
    w, h = out.size
    for _ in range(rounds):
        px = out.load()
        snap = [px[x, y] for y in range(h) for x in range(w)]
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                r, g, b, a = snap[y * w + x]
                if a < max_alpha:
                    continue
                nbv = []
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    n = snap[(y + dy) * w + (x + dx)]
                    if n[3] > 0:
                        nbv.append(max(n[0], n[1], n[2]))
                if not nbv:
                    continue
                me = max(r, g, b)
                if me - min(nbv) > thresh:
                    k = max(nbv) / float(me)
                    if k < 1.0:
                        px[x, y] = (int(r * k + 0.5), int(g * k + 0.5),
                                    int(b * k + 0.5), a)
    return out


# ---------------------------------------------------------------- 入口

def main():
    ap = argparse.ArgumentParser(description="纯色背景精灵表 -> 透明 PNG")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("-o", "--outdir", default=None)
    ap.add_argument("--bg", choices=("black", "white"), default="black",
                    help="源图底色，默认 black。white 走另一条管线（见 key_white_to_alpha）")
    ap.add_argument("--t-bg", type=int, default=250,
                    help="白底模式：min(RGB) >= 此值且与四边连通才算背景，默认 250"
                         "（必须盖住角色周围 250~252 的光晕，否则会留灰雾、还会粘住相邻帧）")
    ap.add_argument("--band", type=int, default=4,
                    help="白底模式：过渡带宽度（像素），超过它的像素算角色内部。实测 1~4，默认 4")
    ap.add_argument("--alpha-floor", type=int, default=10,
                    help="白底模式：alpha 低于此值归零，默认 10（否则会散落一堆小碎点）")
    ap.add_argument("--despeckle", type=int, default=0,
                    help="去孤立亮点：亮度比四个邻域都高出此值就压暗，默认 0=关。"
                         "AI 抖色颗粒重的素材可设 70")
    ap.add_argument("--hard", action="store_true",
                    help="硬边模式：alpha 仅 0/255，RGB 与原图逐位一致（最严格无损）")
    ap.add_argument("--t-dark", type=int, default=24, help="判定为暗部/背景的 key 上限，默认 24")
    ap.add_argument("--ring", type=int, default=2, help="边缘羽化环数，默认 2")
    ap.add_argument("--ref", type=int, default=48, help="羽化参考亮度，默认 48")
    ap.add_argument("--pocket", type=int, default=600, help="视为镂空的最大连通域面积，默认 600")
    ap.add_argument("--suffix", default="", help="输出文件名后缀")
    ap.add_argument("--preview", default=None)
    args = ap.parse_args()

    for src in args.inputs:
        if not os.path.isfile(src):
            print("跳过（不存在）:", src)
            continue
        outdir = args.outdir or os.path.dirname(os.path.abspath(src))
        os.makedirs(outdir, exist_ok=True)
        stem = os.path.splitext(os.path.basename(src))[0]
        dst = os.path.join(outdir, stem + args.suffix + ".png")

        # 输入是 .png 且没给后缀时，输出路径会和源文件重合。
        # 覆盖前先留一份原件，避免把原始素材直接抹掉。
        if os.path.abspath(dst) == os.path.abspath(src):
            tag = ".whitebg.bak.png" if args.bg == "white" else ".blackbg.bak.png"
            bak = os.path.splitext(src)[0] + tag
            if not os.path.exists(bak):
                with Image.open(src) as _im:
                    _im.save(bak)
                print(f"[备份] 原底图 -> {bak}")

        with Image.open(src) as im:
            if args.bg == "white":
                rgba, st = key_white_to_alpha(im, args.t_bg, args.band, args.alpha_floor)
            else:
                rgba, st = key_to_alpha(im, args.t_dark, args.ring, args.ref,
                                        args.pocket, args.hard)
        if args.despeckle > 0:
            despeckle(rgba, args.despeckle)
        rgba.save(dst)

        total = rgba.width * rgba.height
        mode = ("white-bg t_bg=%d band=%d floor=%d" % (args.t_bg, args.band, args.alpha_floor)
                if args.bg == "white" else
                ("hard" if args.hard else f"feather(ring={args.ring},ref={args.ref})"))
        print(f"[OK] {src}\n  -> {dst}")
        print(f"  {rgba.width}x{rgba.height}  {mode}")
        print(f"  透明 {st['transparent']/total:6.2%}  不透明 {st['opaque']/total:6.2%}"
              f"  羽化 {st['feather']/total:6.2%}"
              + (f"  归零 {st['floor']}  无前景估计 {st['orphan']}"
                 if "floor" in st else ""))
        print(f"  体积 {os.path.getsize(dst)/1024:.0f}KB")

        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            pv = os.path.join(args.preview, stem + args.suffix + "_preview.png")
            make_preview(rgba, pv)
            print(f"  预览 -> {pv}")


if __name__ == "__main__":
    main()
