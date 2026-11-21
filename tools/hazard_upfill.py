# -*- coding: utf-8 -*-
"""重建悬顶贴图的「向上延伸段」——用**一整块材质**平铺，而不是一小片。

为什么需要它（`obstacle_prep.build_upfill()` 错在哪）
--------------------------------------------------------
原实现在贴图顶部 90 行里找一个「宽度稳定（实心像素数恒定、左右边界不漂）」的
4~16px 小段来平铺。这个判据**对绳子是对的**（绳子的编织节距就是十几像素），
但对**链条**完全错：

  · 「悬挂锚链」顶部是一节链环，链环只有中段那一小段侧面宽度是恒定的
    → 采到 8px 的链环侧面 → 平铺出来是一条**细锯齿带**，不像链子；
  · 「吊货滑车」顶部其实是一段链子，但往下 8px 就被滑轮挡住
    → 采到的是链节端部 / 滑轮轮缘的一小片 → 平铺出来是**木纹斜格带**。

原图里这两处都是**一节一节的链环**（用户 2026-09-27 指出「上端连接处太奇怪」）。

用法
----
    # 材质取自本图（本体最上面那一节链环）
    python tools/hazard_upfill.py 贴图.png --tile self:73,403,97,435 --mirror --step 0.6

    # 材质取自另一张图（滑车顶部自己被滑轮挡住，借锚链的链环）
    python tools/hazard_upfill.py 滑车.png \\
        --tile sprites/hazard/hazard_over_chain.png:73,403,97,435 \\
        --cx 69 --scale 1.29 --mirror --step 0.6

要点
----
· `--tile` 是**贴图坐标**里的一块材质（通常是本体最上面那一节链环）；
· `--step` 是平铺步长占块高的比例，**必须 < 1**：链环是环形（角上透明），
  首尾相接地平铺会露出一段段空隙，读成「一串断开的珠子」；
  相邻两块重叠 ~40%（step 0.6）才像互相扣住的链子。
· `--mirror` 隔一块纵向镜像，避免每块长得一模一样。
· `--cx` 是材质在**目标贴图**里的水平中心。取自本图时可省（默认用矩形中心）。

⚠ 只对**悬垂型**贴图用（它们的 y ∈ [0, 400) 是延伸段）。默认就地覆盖，先自动备份。
"""
import argparse
import os
import shutil
import sys

from PIL import Image, ImageChops

EXT_H = 400          # 延伸段高度（与 obstacle_prep 的 upfill 参数一致）


def load_tile(spec, self_path, key_bg=False):
    """解析 `self:x0,y0,x1,y1` 或 `路径:x0,y0,x1,y1` → (图, 矩形, 是否本图)。

    `key_bg=True` 时给**没有 alpha 的源图（JPG）**就地抠底 ——
    不然整块材质连背景一起贴上去，延伸段会变成一条不透明矩形带。
    抠底用的是 `obstacle_prep` 那套（采样四边主色 + 最大通道差 + 边缘连通判定）。
    """
    if ":" not in spec:
        sys.exit("--tile 格式应为 self:x0,y0,x1,y1 或 路径:x0,y0,x1,y1")
    src, rect = spec.rsplit(":", 1)
    try:
        x0, y0, x1, y1 = [int(v) for v in rect.split(",")]
    except ValueError:
        sys.exit("--tile 的矩形应为 x0,y0,x1,y1，给的是 %r" % rect)
    path = self_path if src.strip() == "self" else src.strip()
    im = Image.open(path)
    if key_bg and ("A" not in im.getbands() or im.getextrema()[3][0] == 255):
        import obstacle_prep as op
        rgb = im.convert("RGB")
        mask = ImageChops.invert(op.background_mask(
            op.bg_distance(rgb, op.sample_bg(rgb)), rgb.width, rgb.height))
        im = rgb.convert("RGBA")
        im.putalpha(mask)
    im = im.convert("RGBA")
    if not (0 <= x0 < x1 <= im.width and 0 <= y0 < y1 <= im.height):
        sys.exit("--tile 矩形 %s 超出 %s（%dx%d）" % (rect, path, im.width, im.height))
    return im.crop((x0, y0, x1, y1)), (x0, y0, x1, y1), src.strip() == "self"


def rebuild(tex, tile, cx, mirror=True, scale=1.0, step=0.6):
    if abs(scale - 1.0) > 1e-3:
        w = max(1, int(round(tile.width * scale)))
        h = max(1, int(round(tile.height * scale)))
        tile = tile.resize((w, h), Image.LANCZOS)
    px = int(round(cx - tile.width * 0.5))
    th = tile.height
    # ⚠ 步长必须 < 块高：链环是**环形**的（角上透明），首尾相接地平铺会露出一段段空隙，
    #   读成「一串断开的珠子」。真实的链环是互相扣住的，所以要让相邻两块**重叠**。
    st = max(1, int(round(th * step)))

    out = Image.new("RGBA", (tex.width, EXT_H), (0, 0, 0, 0))
    k = 0
    y = EXT_H - th                 # 最下面那块直接贴着本体（y = EXT_H 的上方）
    while y + th > 0:
        src = tile.transpose(Image.FLIP_TOP_BOTTOM) if (mirror and k % 2) else tile
        out.paste(src, (px, y), src)
        y -= st
        k += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="要修的贴图（悬垂型）")
    ap.add_argument("--tile", required=True,
                    help="材质块：self:x0,y0,x1,y1 或 路径:x0,y0,x1,y1")
    ap.add_argument("--key-bg", action="store_true",
                    help="材质源是 JPG（无 alpha）时先抠掉背景，否则延伸段成一条不透明带")
    ap.add_argument("--cx", type=float, default=None,
                    help="材质在目标贴图里的水平中心（默认 = 矩形中心，取自本图时够用）")
    ap.add_argument("--mirror", action="store_true", help="隔一块纵向镜像（推荐）")
    ap.add_argument("--scale", type=float, default=1.0, help="材质缩放比")
    ap.add_argument("--step", type=float, default=0.6,
                    help="平铺步长 = 块高 × 它。1.0 = 首尾相接（链环会断开），0.6 推荐")
    ap.add_argument("--out", default="", help="输出路径（默认就地覆盖，先自动备份）")
    ap.add_argument("--backup-dir", default="tools/_work/hazard_backup")
    args = ap.parse_args()

    tex = Image.open(args.path).convert("RGBA")
    if tex.height <= EXT_H:
        sys.exit("贴图只有 %d px 高，不像悬垂型（延伸段就有 %d px）"
                 % (tex.height, EXT_H))
    tile, (x0, y0, x1, y1), is_self = load_tile(args.tile, args.path, args.key_bg)
    if is_self and y0 < EXT_H:
        sys.exit("材质矩形要取在身体区域（Y0 ≥ %d），给的是 %d" % (EXT_H, y0))
    cx = args.cx if args.cx is not None else (x0 + x1) * 0.5

    up = rebuild(tex, tile, cx, args.mirror, args.scale, args.step)
    out = tex.copy()
    out.paste(up, (0, 0))          # 只覆盖延伸段
    print("材质 %dx%d%s → 延伸段 %dx%d，水平中心 x=%.0f，%s，步长 %.2f×块高"
          % (x1 - x0, y1 - y0, "（借自 %s）" % args.tile.split(":")[0] if not is_self else "",
             up.width, EXT_H, cx, "纵向镜像" if args.mirror else "不镜像", args.step))

    dst = args.out or args.path
    if dst == args.path:
        os.makedirs(args.backup_dir, exist_ok=True)
        shutil.copy2(args.path, os.path.join(args.backup_dir,
                                             os.path.basename(args.path)))
    out.save(dst)
    print("->", dst)


if __name__ == "__main__":
    main()
