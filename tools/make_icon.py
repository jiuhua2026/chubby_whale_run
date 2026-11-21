# -*- coding: utf-8 -*-
"""从角色精灵生成游戏图标（`icon.png` + `icon.ico`）。

为什么要那个浅色描边
--------------------
主角是**深蓝发色**，纯透明底的图标在深色任务栏/桌面上几乎看不出轮廓。
加一圈 2px 的浅色描边（在 92px 源尺度上）后，浅底深底都能看清 ——
这也是像素游戏图标的常见做法。

用法
----
    python tools/make_icon.py            # 输出到 sprites/icon/icon.png / icon.ico
    python tools/make_icon.py --preview  # 只看候选，不写文件
"""
import argparse
import os
import sys

from PIL import Image, ImageFilter

# 头 + 鲸鳍耳 + 光环：源帧 116x130 里这块是「能一眼认出是谁」的最小方形
CROP = (24, 0, 116, 92)
SRC = "sprites/run/run_01.png"
OUTLINE_GROW = 2
OUTLINE_COLOR = (226, 238, 255)
OUTLINE_ALPHA = 200
ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def build(src_path=SRC, crop=CROP, outline=True):
    sq = Image.open(src_path).convert("RGBA").crop(crop)
    n = max(sq.size)
    canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    canvas.paste(sq, ((n - sq.width) // 2, (n - sq.height) // 2), sq)
    if not outline:
        return canvas
    a = canvas.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    ring = a.filter(ImageFilter.MaxFilter(OUTLINE_GROW * 2 + 1))
    ring = Image.composite(Image.new("L", canvas.size, 255), ring, a)   # 挖掉本体
    layer = Image.new("RGBA", canvas.size, OUTLINE_COLOR + (0,))
    layer.putalpha(ring.point(lambda v: OUTLINE_ALPHA if v else 0))
    return Image.alpha_composite(layer, canvas)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="只出对比图，不写图标文件")
    ap.add_argument("--out-dir", default="sprites/icon")
    args = ap.parse_args()

    icon = build()
    if args.preview:
        cands = [("原样", build(outline=False)), ("描边 %dpx" % OUTLINE_GROW, icon)]
        panels = []
        for tag, im in cands:
            p = Image.new("RGB", (140, 200), (14, 22, 34))
            p.paste(im.resize((120, 120), Image.LANCZOS), (10, 6))
            for i, bgc in enumerate(((255, 255, 255), (32, 40, 56), (14, 22, 34))):
                tile = Image.new("RGB", (36, 36), bgc)
                tile.paste(im.resize((32, 32), Image.LANCZOS), (2, 2))
                p.paste(tile, (10 + i * 40, 140))
            panels.append(p)
        from PIL import ImageDraw, ImageFont
        s = Image.new("RGB", (len(panels) * 146 + 6, 206), (9, 13, 22))
        for i, p in enumerate(panels):
            ImageDraw.Draw(p).text((10, 178), cands[i][0], fill=(230, 240, 250),
                                   font=ImageFont.truetype(
                                       "C:/Windows/Fonts/msyh.ttc", 13))
            s.paste(p, (6 + i * 146, 3))
        s.save("tools/_preview/_icon_preview.png")
        print("->", "tools/_preview/_icon_preview.png")
        return

    os.makedirs(args.out_dir, exist_ok=True)
    png = os.path.join(args.out_dir, "icon.png")
    ico = os.path.join(args.out_dir, "icon.ico")
    icon.resize((256, 256), Image.LANCZOS).save(png)
    icon.save(ico, format="ICO", sizes=ICO_SIZES)
    print("-> %s（256x256，Godot 窗口图标）" % png)
    print("-> %s（%d 个尺寸，Windows 快捷方式图标）"
          % (ico, len(ICO_SIZES)))


if __name__ == "__main__":
    main()
