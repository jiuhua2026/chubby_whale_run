#!/usr/bin/env python3
"""生成追击用的粒子贴图 → `sprites/fx/{bubble,dust}.png`。

## 为什么不继续用 `draw_circle`
`draw_circle` 画的是**硬边实心圆**：没有高光、没有体积、不会折射 ⇒ 再放大也只是"彩色圆点"。
用户的反馈是"粒子很粗糙"，这就是根因之一。贴图能做的东西它做不了：
  · 气泡 = **高斯截面的环** + 一点内填充 + 左上**高光点**（读作"水里的泡"而不是"圆点"）
  · 浮尘 = 柔光斑（中心亮、边缘化开）

## 为什么用 Python 生成而不是找素材
两个图都很小（48² / 24²），形状是纯数学 ⇒ 生成比找素材快，而且**可复现、可调参**。
4× 超采样再降采样，边缘不会锯齿。

用法：`python tools/make_fx.py`
"""
import math
import os

from PIL import Image

OUT = "sprites/fx"
SS = 4          # 超采样倍数


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name)
    img.save(p)
    print("  %-14s %dx%d" % (name, img.width, img.height))


def bubble(size=48):
    """气泡：高斯环 + 极淡内填充 + 左上高光。"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    cx = cy = s * 0.5
    R = s * 0.31                       # 环半径（留出边距给柔边）
    ring_w = max(1.0, s * 0.035)
    hx, hy = cx - R * 0.46, cy - R * 0.50
    for y in range(s):
        for x in range(s):
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            if d > R * 1.5:
                continue
            ring = math.exp(-((d - R) / ring_w) ** 2) * 0.95   # 环：高斯截面
            fill = 0.10 * max(0.0, 1.0 - d / R)                # 内部：几乎透明
            hi = math.exp(-(math.hypot(x - hx, y - hy) / (s * 0.095)) ** 2) * 0.9
            a = min(1.0, ring + fill + hi)
            if a <= 0.004:
                continue
            k = hi / 0.9
            px[x, y] = (int((0.60 + 0.32 * k) * 255),
                        int((0.82 + 0.16 * k) * 255),
                        int((0.96 + 0.04 * k) * 255),
                        int(a * 255))
    return img.resize((size, size), Image.LANCZOS)


def dust(size=24):
    """浮尘：柔光斑（高斯衰减）。"""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    c = s * 0.5
    R = s * 0.46
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c) / R
            if d > 1.0:
                continue
            a = math.exp(-(d ** 2) * 2.6) * 0.9
            if a <= 0.004:
                continue
            px[x, y] = (int(0.56 * 255), int(0.76 * 255), int(0.92 * 255), int(a * 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    print("生成粒子贴图 → %s/" % OUT)
    save(bubble(), "bubble.png")
    save(dust(), "dust.png")
    print("完成。")


if __name__ == "__main__":
    main()
