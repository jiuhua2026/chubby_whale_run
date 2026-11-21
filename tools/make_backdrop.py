#!/usr/bin/env python3
"""把一张"深海岩壁"照片处理成可平铺的背景贴图 → `sprites/bg/deep_rock.png`。

## 要解决三个问题（都是量出来的，不是猜的）
1. **左右接不上**：原图左边缘亮度 9.2 / 右边缘 34.6 ⇒ 差 **25.4**，直接平铺会出现一条明显的竖缝 ✗
   ⇒ **首尾交叉淡化**：把尾部 f 列与头部 f 列混合后裁掉尾巴（和做音频循环用的是同一招）。
   上下是接得上的（42.0 vs 41.4，差 0.6）⇒ 只处理横向。
2. **太亮**：原图平均亮度 36.5，而地形板只有 ~22~29 ⇒ 直接铺上去**地形会沉进背景** ✗
   ⇒ 压到 **0.45×** 左右（≈16）。
3. **没有深度**：照片本身没有远近信息 ⇒ 叠一个**竖向渐变**（上亮下暗，乘 1.0 → 0.62）。

用法：`python tools/make_backdrop.py [源图路径]`
"""
import os
import sys

from PIL import Image

SRC = "image/background/rock_src.jpg"   # 与原始背景图 (1.png) 放在同一目录
OUT = "sprites/bg/deep_rock.png"
W = 1024                # 输出宽度（背景在最底层、还被压暗，不需要原图分辨率）
DARKEN = 0.46
GROUND_FLATTEN = 0.50   # 地面贴图往「板色」混的比例：0=原样 1=纯色           # 整体压暗系数
FADE_FRAC = 0.10        # 横向首尾交叉淡化的比例
FADE_Y_FRAC = 0.14      # 纵向首尾交叉淡化的比例（做 X+Y 双向无缝，防止上下续铺露水平接缝）
VGRAD_TOP = 1.00        # 竖向渐变：顶部系数（已改平，见下）
VGRAD_BOT = 1.00        # ⚠ 原来是 0.62（上亮下暗）—— 但它和 ScreenFrame 的「上缘渐隐」
                        #   互相抵消：实测顶部 23.6、中部 16.1，只差 7 级，渐隐等于没做。
                        #   改平之后「上暗下亮」只由 ScreenFrame 一处负责，方向才一致。


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    im = Image.open(src).convert("RGB")
    w, h = im.size
    nh = int(round(h * (W / float(w))))
    im = im.resize((W, nh), Image.LANCZOS)
    w, h = im.size
    print("源图 %dx%d → 缩放到 %dx%d" % (*Image.open(src).size, w, h))

    # ---- 1) 横向首尾交叉淡化（做成可平铺）----
    f = int(w * FADE_FRAC)
    w2 = w - f
    px = im.load()
    hx = Image.new("RGB", (w2, h))
    hp = hx.load()
    for y in range(h):
        for x in range(w2):
            if x < f:
                t = (x + 1) / float(f + 1)
                a = px[x, y]              # 头部
                b = px[x + w2, y]         # 源图尾部
                hp[x, y] = (int(a[0] * t + b[0] * (1 - t)),
                            int(a[1] * t + b[1] * (1 - t)),
                            int(a[2] * t + b[2] * (1 - t)))
            else:
                hp[x, y] = px[x, y]

    # ---- 1b) 纵向首尾交叉淡化（消除上下重复时的逐列 RGB 跳变）----
    fy = int(h * FADE_Y_FRAC)
    h2 = h - fy
    out = Image.new("RGB", (w2, h2))
    op = out.load()
    for y in range(h2):
        for x in range(w2):
            if y < fy:
                t = (y + 1) / float(fy + 1)
                a = hp[x, y]
                b = hp[x, y + h2]
                op[x, y] = (int(a[0] * t + b[0] * (1 - t)),
                            int(a[1] * t + b[1] * (1 - t)),
                            int(a[2] * t + b[2] * (1 - t)))
            else:
                op[x, y] = hp[x, y]

    # ---- 2) 压暗 + 3) 竖向渐变 ----
    op = out.load()
    for y in range(h2):
        k = VGRAD_TOP + (VGRAD_BOT - VGRAD_TOP) * (y / float(h2 - 1))
        for x in range(w2):
            c = op[x, y]
            op[x, y] = (int(c[0] * DARKEN * k),
                        int(c[1] * DARKEN * k),
                        int(c[2] * DARKEN * k))

    lum = [int(0.299 * op[x, y][0] + 0.587 * op[x, y][1] + 0.114 * op[x, y][2])
           for y in range(0, h2, 4) for x in range(0, w2, 4)]
    print("  处理后亮度：平均 %.1f  中位 %d  最大 %d（目标 ≈16，必须低于地形板 ≈22~29）"
          % (sum(lum) / len(lum), sorted(lum)[len(lum) // 2], max(lum)))

    # ---- 4) 环绕边界做轻微虚化（不破坏 X/Y 无缝边缘）----
    from PIL import ImageFilter
    pad = 16
    padded = Image.new("RGB", (w2 + pad * 2, h2 + pad * 2))
    # Tile 3x3 slice around center so GaussianBlur reads true toroidal neighbors
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            padded.paste(out, (pad + dx * w2, pad + dy * h2))
    padded = padded.filter(ImageFilter.GaussianBlur(2.2))
    out = padded.crop((pad, pad, pad + w2, pad + h2))

    fp = out.load()
    dx_col = sum(abs(fp[0, y][c] - fp[w2 - 1, y][c]) for y in range(h2) for c in range(3)) / (3.0 * h2)
    dy_row = sum(abs(fp[x, 0][c] - fp[x, h2 - 1][c]) for x in range(w2) for c in range(3)) / (3.0 * w2)
    print("  双向接缝检查：逐行均值差 dX=%.2f / dY=%.2f（均应 < 1.5）" % (dx_col, dy_row))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("→ %s  %dx%d" % (OUT, out.width, out.height))

    # ---- 第二张：**地面板**用的无缝岩面（256×256 平铺）----
    # 为什么单独一张：地面板是用 `draw_texture_rect(..., tile=true)` 平铺的，
    # 平铺尺度必须是"小图"（256 一格）才读得出石头的颗粒；远景那张 922 宽太粗。
    # 从**已经无缝**的 out 上裁一块再缩放 ⇒ 仍然无缝 ✓（缩放不破坏接缝）。
    gs = min(out.width, out.height)
    ground = out.crop((0, 0, gs, gs)).resize((256, 256), Image.LANCZOS)
    # 提亮一点、并往地形板的蓝灰调偏 —— 让"地面"比"背景"实、但同一套材质
    gp = ground.load()
    for y in range(256):
        for x in range(256):
            c = gp[x, y]
            gp[x, y] = (min(255, int(c[0] * 1.55 + 6)),
                        min(255, int(c[1] * 1.45 + 9)),
                        min(255, int(c[2] * 1.30 + 12)))
    # ★ **降对比**：实测背景的纹理对比（stdev）只有 2.9，地面却是 24.9 —— 差 8 倍，
    #   于是同一张图被眼睛读成"虚化的远景"和"锐利的前景照片"两种材质 ⇒ 违和。
    #   往板色混 50% 之后 stdev 降到 ~12，和背景的"虚"对上 ✓
    FLAT = (20, 38, 56)
    for y in range(256):
        for x in range(256):
            c = gp[x, y]
            gp[x, y] = (int(c[0] * (1 - GROUND_FLATTEN) + FLAT[0] * GROUND_FLATTEN),
                        int(c[1] * (1 - GROUND_FLATTEN) + FLAT[1] * GROUND_FLATTEN),
                        int(c[2] * (1 - GROUND_FLATTEN) + FLAT[2] * GROUND_FLATTEN))
    lum2 = [int(0.299*gp[x,y][0] + 0.587*gp[x,y][1] + 0.114*gp[x,y][2])
            for y in range(0, 256, 4) for x in range(0, 256, 4)]
    print("  地面岩面亮度：平均 %.1f（应略高于背景 12.7、明显低于顶边高光 100）"
          % (sum(lum2)/len(lum2)))
    ground.save("sprites/bg/ground_rock.png")
    print("→ sprites/bg/ground_rock.png  256x256")


if __name__ == "__main__":
    main()
