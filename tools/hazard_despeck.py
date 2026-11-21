# -*- coding: utf-8 -*-
"""障碍贴图「清碎块」——对**已经在用**的贴图做外科手术，其余像素一个不动。

为什么需要它（而不是直接重跑 obstacle_prep.py）
--------------------------------------------------
障碍贴图现在的成品是「早期 obstacle_prep 出的本体 + 当时单独跑的 patch_upfill 合成的延伸段」，
**用当前的 obstacle_prep.py 已经复现不出来**：重生成会把延伸段的绳子改细、改淡
（实测同一像素 alpha 243 → 131），那是对已验证成品的回退。
所以清碎块必须就地做：只删掉与主体不相连的小块，别的一个像素都不碰。

清什么
------
· 源图里紧挨着障碍的零散杂物（实测「断裂桅杆」底部一小卷绳圈 109px、
  「船体横撑」底部一个小绳梯 525px）；
· 缩放把 1~2px 连接掐断后留下的边缘残渣（矮障碍四张底边各有 1~12px 这种）。

判据：与最大连通块不相连、且面积 < max(24, 最大块 × 3%)。
实测被删的都 ≤2.4%，而**该保留的部件**（横撑的 4 根独立肋骨、各造型的海草小花）都 ≥10%，
中间空得很开。

用法
----
    python tools/hazard_despeck.py sprites/hazard/hazard_over_*.png
    python tools/hazard_despeck.py --probe sprites/hazard/*.png
"""
import argparse
import glob
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image

from obstacle_prep import SPECKS_ALPHA, SPECKS_ABS, SPECKS_FRAC, drop_specks

# 只有当底部空出的行数超过它，才把贴图裁短。
# 1px 的淡边留着无妨；裁了反而让障碍下沿的柔边变硬。
TRIM_MIN_GAP = 2


def alpha_bbox(tex, alpha_t=SPECKS_ALPHA):
    return tex.getchannel("A").point(lambda v: 255 if v > alpha_t else 0).getbbox()


def process(path, probe=False, backup_dir=None):
    im = Image.open(path).convert("RGBA")
    w, h0 = im.size
    out, dropped = drop_specks(im)
    bb = alpha_bbox(out)
    if bb is None:
        print("  %-26s ⚠ 全透明？跳过" % os.path.basename(path))
        return False
    gap = h0 - bb[3]
    trim = gap >= TRIM_MIN_GAP
    new = out.crop((0, 0, w, bb[3])) if trim else out
    changed = bool(dropped) or trim
    tag = ("清碎块 %d 个 %s" % (len(dropped), dropped[:6])) if dropped else "无碎块"
    tag += ("  裁掉底部 %d 行（%d→%d）" % (gap, h0, bb[3])) if trim else ""
    print("  %-26s %dx%d  %s%s"
          % (os.path.basename(path), w, new.height, tag, "" if changed else "  → 无需改动"))
    if not changed or probe:
        return changed
    if backup_dir:
        os.makedirs(backup_dir, exist_ok=True)
        shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))
    new.save(path)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="贴图路径（支持通配符）")
    ap.add_argument("--probe", action="store_true", help="只检测，不写文件")
    ap.add_argument("--backup-dir", default="tools/_work/hazard_backup")
    args = ap.parse_args()

    paths = []
    for f in args.files:
        paths.extend(sorted(glob.glob(f)) or [f])
    paths = [p for p in paths if os.path.isfile(p)]
    if not paths:
        sys.exit("没有匹配到文件")

    print("清碎块（判据：与最大块不相连且 < max(%d, 最大块×%.0f%%)）"
          % (SPECKS_ABS, SPECKS_FRAC * 100))
    n = sum(1 for p in paths if process(p, args.probe, args.backup_dir))
    print("共 %d/%d 张有改动%s" % (n, len(paths), "（--probe：未写文件）" if args.probe else ""))


if __name__ == "__main__":
    main()
