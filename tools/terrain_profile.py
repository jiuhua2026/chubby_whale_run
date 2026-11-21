"""把 `-- --dump-terrain` 的 ASCII 地形倒成剖面图。

用途：验证「开局地图是否真的不同」「地形是否有割裂感」。
ASCII 只能逐列 diff，人眼读不出来；画成剖面一眼就能看出
「这段是长平台 / 这段是一串断开的台子 / 障碍挤不挤」。

用法：python tools/_work/terrain_profile.py out.png 标签=文件 [标签=文件 ...]
"""
import io
import re
import sys

from PIL import Image, ImageDraw, ImageFont

COLS = 420          # 每局画多少列
SCALE = 3           # 每列几像素
LEVEL_H = 26        # 每层高几像素
OBS_H = 16          # 障碍在剖面上画多高
PAD = 8

GROUND = (58, 84, 112)
GROUND_TOP = (110, 158, 196)
LOW = (226, 120, 84)        # 矮障碍（跳）
OVER = (108, 150, 226)      # 悬顶（滑）
BG = (16, 24, 36)
TXT = (222, 236, 248)
SUB = (140, 180, 214)


def load(path):
    lv, hz = [], []
    for line in io.open(path, encoding="utf-8"):
        m = re.search(r"h=([0-9]+) b=([.^v]+)", line)
        if m:
            lv.extend(int(c) for c in m.group(1))
            hz.extend(m.group(2))
    return lv[:COLS], hz[:COLS]


def main():
    out = sys.argv[1]
    jobs = [a.split("=", 1) for a in sys.argv[2:]]
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
    font_s = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 12)

    panels = []
    for tag, path in jobs:
        lv, hz = load(path)
        w = len(lv) * SCALE
        h = LEVEL_H * 3 + OBS_H + 30
        im = Image.new("RGB", (w, h), BG)
        d = ImageDraw.Draw(im)
        top = OBS_H + 4
        for c in range(len(lv)):
            x = c * SCALE
            y = top + lv[c] * LEVEL_H
            d.rectangle([x, y, x + SCALE - 1, top + LEVEL_H * 3 + 10], fill=GROUND)
            d.rectangle([x, y, x + SCALE - 1, y + 3], fill=GROUND_TOP)
        for c in range(len(hz)):
            if hz[c] == ".":
                continue
            x = c * SCALE
            y = top + lv[c] * LEVEL_H
            col = LOW if hz[c] == "^" else OVER
            d.rectangle([x, y - OBS_H, x + SCALE - 1, y - 1], fill=col)
        d.text((4, 3), tag, fill=TXT, font=font)
        n_obs = sum(1 for c in hz if c == "^")
        n_over = sum(1 for c in hz if c == "v")
        n_pit = sum(1 for c in lv if c != 0)
        d.text((4, h - 20),
               "%d 列：矮障碍 %d / 悬顶 %d（共 %d 组）　坑 %d 列（%.0f%%）"
               % (len(lv), n_obs, n_over,
                  _groups(hz), n_pit, 100.0 * n_pit / max(1, len(lv))),
               fill=SUB, font=font_s)
        panels.append(im)

    W = max(p.width for p in panels) + PAD * 2
    H = sum(p.height for p in panels) + PAD * (len(panels) + 1)
    s = Image.new("RGB", (W, H), (9, 13, 22))
    y = PAD
    for p in panels:
        s.paste(p, (PAD, y))
        y += p.height + PAD
    s.save(out)
    print("->", out, s.size)


def _groups(hz):
    n, i = 0, 0
    while i < len(hz):
        if hz[i] == ".":
            i += 1
            continue
        n += 1
        while i + 1 < len(hz) and hz[i + 1] != ".":
            i += 1
        i += 1
    return n


main()
