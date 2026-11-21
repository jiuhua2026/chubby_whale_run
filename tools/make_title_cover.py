"""主菜单封面 → 游戏内可直接 1:1 使用的 1280x720。

## 为什么必须预处理，不能直接把原图丢进 sprites/
项目里 `rendering/textures/canvas_textures/default_texture_filter=0`（**最近邻**）。
封面是 `TextureRect` + `STRETCH_KEEP_ASPECT_COVERED`，原图 1024x572 要拉到 1289 才铺满
⇒ 缩放比 **1.259 是非整数**，最近邻会让像素宽度在 1px / 2px 之间跳 ⇒ 边缘粗细不均、细节闪。

预处理成 **1280x720** 后，运行时缩放比正好 **1.0** ⇒ 不重采样，最锐利。

## 裁切口径
和 `STRETCH_KEEP_ASPECT_COVERED` 一致：先按高度铺满，再把多出来的宽度**左右均分裁掉**
（1024x572 → 铺到高 720 得 1288.6 宽 → 左右各裁 4px）。这样运行时不会再有额外裁切。
"""
import os
from PIL import Image

SRC = "image/title_cover/title_screen_pixel_art.png"
OUT = "sprites/title/title_screen_pixel_art.png"
W, H = 1280, 720          # 视口尺寸（project.godot: window/size/viewport_*）


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    sw, sh = im.size
    # 1) 等比铺满：取两边缩放比的较大者
    scale = max(W / sw, H / sh)
    nw, nh = round(sw * scale), round(sh * scale)
    im2 = im.resize((nw, nh), Image.LANCZOS)
    # 2) 居中裁到 1280x720
    left = (nw - W) // 2
    top = (nh - H) // 2
    im3 = im2.crop((left, top, left + W, top + H))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im3.save(OUT, optimize=True)
    print("源 %dx%d → 铺满 %dx%d（x%.3f）→ 居中裁 → %dx%d"
          % (sw, sh, nw, nh, scale, im3.width, im3.height))
    print("   裁掉：左右各 %dpx / 上下各 %dpx" % (left, top))
    print("→ %s  %.0f KB" % (OUT, os.path.getsize(OUT) / 1024.0))


if __name__ == "__main__":
    main()
