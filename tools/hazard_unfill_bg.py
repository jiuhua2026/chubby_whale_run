# -*- coding: utf-8 -*-
"""清掉障碍贴图里「造型内部残留的底色」——对**已经在用**的贴图做外科手术。

症状
----
被造型围住的封闭区域（锚链的 A 形内部、滑车绳子围出的三角区、链环中间的孔）
贴到游戏里是一块**比背景略亮的蓝斑**。用户 2026-09-27：
「这两个地方没处理好 感觉应该是空的 但是现在有点泛蓝」。

原因
----
抠底的判据是「**从四边连通**到画面边缘的才算背景」（`obstacle_prep.background_mask`）。
这条判据对「造型外面的底」有效，但造型自己围出来的封闭区域连不到边缘 → 被当前景留下。

为什么就地做、不重跑 obstacle_prep.py
----------------------------------------
和碎块清理同理：现成贴图是「早期 obstacle_prep 出的本体 + 后来单独改的延伸段」，
当前脚本复现不出来（重生成会把延伸段的绳子改细改淡）。所以只动该动的像素。

用法
----
    python tools/hazard_unfill_bg.py --probe "sprites/hazard/*.png"
    python tools/hazard_unfill_bg.py "sprites/hazard/*.png"
"""
import argparse
import glob
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image

from obstacle_prep import (BG_UNFILL_MIN, BG_UNFILL_TOL, SPECKS_ALPHA,
                           unfill_enclosed_bg)

# 两个源图的底色（di.png / tian.png）实测都是这个，差 ≤2 级
DEFAULT_BG = (14, 32, 56)


def process(path, bg, tol, min_area, probe=False, backup_dir=None):
    im = Image.open(path).convert("RGBA")
    out, killed = unfill_enclosed_bg(im, bg, tol, min_area, SPECKS_ALPHA)
    if not killed:
        print("  %-26s %dx%d  没有残留底色 → 无需改动" % (os.path.basename(path),
                                                         im.width, im.height))
        return 0
    total = sum(killed)
    print("  %-26s %dx%d  清掉 %d 块（共 %d px）：%s"
          % (os.path.basename(path), im.width, im.height, len(killed), total,
             killed[:6]))
    if not probe:
        if backup_dir:
            os.makedirs(backup_dir, exist_ok=True)
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))
        out.save(path)
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="贴图路径（支持通配符）")
    ap.add_argument("--probe", action="store_true", help="只检测，不写文件")
    ap.add_argument("--bg", default="%d,%d,%d" % DEFAULT_BG,
                    help="底色 RGB（默认 %d,%d,%d）" % DEFAULT_BG)
    ap.add_argument("--tol", type=int, default=BG_UNFILL_TOL,
                    help="与底色的最大通道差（默认 %d）" % BG_UNFILL_TOL)
    ap.add_argument("--min-area", type=int, default=BG_UNFILL_MIN,
                    help="小于它的连通块不动（默认 %d）" % BG_UNFILL_MIN)
    ap.add_argument("--backup-dir", default="tools/_work/hazard_backup_bg")
    args = ap.parse_args()

    bg = tuple(int(v) for v in args.bg.split(","))
    paths = []
    for f in args.files:
        paths.extend(sorted(glob.glob(f)) or [f])
    paths = [p for p in paths if os.path.isfile(p)]
    if not paths:
        sys.exit("没有匹配到文件")

    print("清造型内部残留的底色（判据：不透明 + 与 %s 最大通道差 ≤%d + 面积 ≥%d）"
          % (str(bg), args.tol, args.min_area))
    tot = sum(process(p, bg, args.tol, args.min_area, args.probe, args.backup_dir)
              for p in paths)
    print("共清掉 %d px%s" % (tot, "（--probe：未写文件）" if args.probe else ""))


if __name__ == "__main__":
    main()
