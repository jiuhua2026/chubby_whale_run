# -*- coding: utf-8 -*-
"""冲刺特效预览：把 `-- --dashshot` 抓到的帧合成为 GIF。

用途
----
游戏是像素风、特效参数靠手感调，而 AI 侧只能无头验证（看不到画面）。
所以配了一个抓帧开关，本脚本负责把抓到的帧变成能直接看的动图：

    1) 先抓帧（注意**不要加 --headless**，headless 下视口纹理是空的）：
       Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 \
           --fixed-fps 60 --quit-after 6000 -- --selftest --dashshot
       冲刺一开始就会连抓 80 帧（覆盖完整的 1.0s 冲刺 + 尾巴）然后自己退出

    2) 再合成：
       C:/Python314/python.exe tools/dash_preview.py

输出
----
    tools/_preview/dash_fx_full.gif   全屏（看整体观感）
    tools/_preview/dash_fx_zoom.gif   局部放大 2x（看残影与粒子的形状）

参数
----
    --ms N      每帧停留毫秒，默认 40。抓帧是 60fps，直接按 16ms 播太快看不清，
                40ms 左右既能看清单帧又还留有速度感。
    --picks A,B 额外导出指定帧的局部放大 PNG（帧号从 1 开始），用于 A/B 对比。
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw, ImageFont

SRC = os.path.join("tools", "_preview", "_shot")
OUT = os.path.join("tools", "_preview")
FONT_CANDIDATES = ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"]


def load_font(size):
    for p in FONT_CANDIDATES:
        if os.path.isfile(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ms", type=int, default=40, help="每帧停留毫秒")
    ap.add_argument("--picks", default="", help="额外导出放大图的帧号，如 6,14,30")
    ap.add_argument("--tag", default="dash_fx",
                    help="输出文件名前缀。抓地形看障碍时用 --tag terrain，"
                         "免得覆盖掉冲刺的那两张")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(SRC, "*.png")))
    if not files:
        raise SystemExit("没找到抓帧，先跑一次 `-- --selftest --dashshot`（不要加 --headless）")

    imgs = [Image.open(f).convert("RGB") for f in files]
    W, H = imgs[0].size
    # 相机把角色固定在屏幕左侧 30%，脚底在 (H/2 - CAMERA_Y_OFFSET)
    cx, cy = int(W * 0.30), int(H * 0.5 + 210)
    print("帧数 %d  尺寸 %dx%d  角色锚点 (%d, %d)" % (len(imgs), W, H, cx, cy))

    def save_gif(frames, name):
        p = os.path.join(OUT, name)
        frames[0].save(p, save_all=True, append_images=frames[1:],
                       duration=args.ms, loop=0, optimize=True)
        print("  -> %-22s %sx%s  %dKB" % (name, frames[0].width, frames[0].height,
                                          os.path.getsize(p) // 1024))

    # 全屏：裁掉上下大片水域空白，只留能看到地形与特效的一段
    box_full = (0, max(0, cy - 420), W, min(H, cy + 130))
    save_gif([im.crop(box_full) for im in imgs], "%s_full.gif" % args.tag)

    # 局部放大 2x：看清残影的间距、淡出，以及粒子的方块形状
    box_zoom = (cx - 250, cy - 250, cx + 150, cy + 90)
    zoom = [im.crop(box_zoom).resize((800, 680), Image.NEAREST) for im in imgs]
    save_gif(zoom, "%s_zoom.gif" % args.tag)

    # 可选：挑几帧导出成放大 PNG，方便并排做 A/B
    for spec in [s for s in args.picks.split(",") if s.strip()]:
        n = int(spec)
        if not 1 <= n <= len(imgs):
            print("  跳过越界帧号", n)
            continue
        c = imgs[n - 1].crop(box_zoom).resize((800, 680), Image.NEAREST)
        dr = ImageDraw.Draw(c)
        dr.text((8, 6), "frame %d  t=%.2fs" % (n, (n - 1) / 60.0),
                fill=(200, 225, 245), font=load_font(24))
        p = os.path.join(OUT, "%s_pick_%02d.png" % (args.tag, n))
        c.save(p)
        print("   -> %s" % os.path.basename(p))


if __name__ == "__main__":
    main()
