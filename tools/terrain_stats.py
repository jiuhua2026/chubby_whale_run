# -*- coding: utf-8 -*-
"""terrain_stats.py —— 地形「割裂度」量测。

为什么需要它（2026-09-28 的教训）：
    上一轮我用「每块坑段数 / 坑列占比」证明"割裂感做出来了"，结果玩家看到的
    还是"一整条连续的路"。原因是我量的是**局部有没有坑**，而玩家感知的是
    **地面这条线有没有断、断得有多密**。

    所以本工具的核心指标是「最长连续无断裂段」和「断口节奏」，
    而不是"坑的总列数"。同一个坑占比，可以是"每屏一个小缺口"，
    也可以是"断成一串台子"，观感完全不同 —— 坑占比区分不了这两者。

用法：
    # 先跑一局把地形倒出来（Godot 侧）
    godot --headless --fixed-fps 60 --quit-after 20000 --path . \
        -- --solvable --dump-terrain 2>&1 | grep '^\\[terrain-dump\\]' > dump.txt

    # 再量
    python tools/terrain_stats.py dump.txt [dump2.txt ...]
    python tools/terrain_stats.py --pair old.txt new.txt      # 两两对比
"""

import io
import re
import sys
import collections

RE_ROW = re.compile(r"h=([0-9aAbB]+) b=([.^v]+)")


def load(path):
    """读 ASCII 地形 dump。返回 [(h_str, b_str), ...]。"""
    rows = []
    for line in io.open(path, encoding="utf-8"):
        m = RE_ROW.search(line)
        if m:
            rows.append((m.group(1), m.group(2)))
    return rows


def _is_pit(c):
    return c.isdigit() and c != "0"


def _pit_runs(h):
    """地面线的"断口"：连续 h>0 的列。返回每处的 (起始列, 宽度, 最大深度)。"""
    out = []
    i = 0
    while i < len(h):
        if not _is_pit(h[i]):
            i += 1
            continue
        s = i
        while i < len(h) and _is_pit(h[i]):
            i += 1
        depth = max(int(c) for c in h[s:i])
        out.append((s, i - s, depth))
    return out


def analyse(rows):
    """把一局的 dump 变成一组数字。所有指标的口径见模块 docstring。"""
    flat = "".join(h for h, _ in rows)
    breaks = _pit_runs(flat)
    n = len(flat)

    # 「最长连续无断裂段」（不含 h>0 凹坑/深沟）
    longest_flat = 0
    i = 0
    while i < n:
        if _is_pit(flat[i]):
            i += 1
            continue
        s = i
        while i < n and not _is_pit(flat[i]):
            i += 1
        longest_flat = max(longest_flat, i - s)

    widths = [w for _, w, _ in breaks]
    depths = collections.Counter(d for _, _, d in breaks)
    convex_a = sum(1 for c in flat if c in ("a", "A"))
    convex_b = sum(1 for c in flat if c in ("b", "B"))

    return {
        "cols": n,
        "chunks": len(rows),
        "breaks": len(breaks),
        "breaks_per_100": 100.0 * len(breaks) / max(1, n),
        "median_gap_cols": n / max(1, len(breaks)),
        "air_pct": 100.0 * sum(widths) / max(1, n),
        "convex_pct": 100.0 * (convex_a + convex_b) / max(1, n),
        "elev1_pct": 100.0 * convex_a / max(1, n),
        "elev2_pct": 100.0 * convex_b / max(1, n),
        "width_hist": dict(sorted(collections.Counter(widths).items())),
        "depth_hist": dict(sorted(depths.items())),
        "longest_flat": longest_flat,
        "no_pit_chunks": sum(1 for h, _ in rows if not any(_is_pit(c) for c in h)),
    }


def report(tag, rows):
    s = analyse(rows)
    print("%s" % tag)
    print("  块=%d 列=%d | 断口 %d 处（每 %.1f 列一个，中位间隔 %.1f 列）"
          % (s["chunks"], s["cols"], s["breaks"], s["median_gap_cols"],
             100.0 / max(0.001, s["breaks_per_100"])))
    print("  开挖率 %.1f%% | 凸台率 %.1f%%（-1层 %.1f%% / -2层 %.1f%%） | 断口宽度分布 %s | 断口深度分布 %s"
          % (s["air_pct"], s["convex_pct"], s["elev1_pct"], s["elev2_pct"],
             s["width_hist"], s["depth_hist"]))
    print("  **最长连续无断裂段 = %d 列（%.1f 个屏幕宽）** | 完全无坑的块 %d/%d"
          % (s["longest_flat"], s["longest_flat"] * 64.0 / 1280.0,
             s["no_pit_chunks"], s["chunks"]))
    return s


def obstacles(rows):
    """障碍密度：把各块的 b 串起来，按"组"统计。"""
    b = "".join(x for _, x in rows)
    h = "".join(x for x, _ in rows)
    groups = []
    shapes = collections.Counter()
    on_convex = 0
    i = 0
    while i < len(b):
        if b[i] == ".":
            i += 1
            continue
        s = i
        while i + 1 < len(b) and b[i + 1] != ".":
            i += 1
        groups.append((s, i))
        shapes[b[s:i + 1]] += 1
        if h[s] in ("a", "A", "b", "B"):
            on_convex += 1
        i += 1
    tot = len(h)
    gaps = [groups[k][0] - groups[k - 1][1] for k in range(1, len(groups))]
    gaps.sort()

    def q(p):
        return gaps[min(len(gaps) - 1, int(len(gaps) * p))] if gaps else 0

    return {
        "groups": len(groups),
        "cols_per_group": tot / max(1, len(groups)),
        "gap_p25": q(0.25), "gap_med": q(0.5), "gap_p75": q(0.75),
        "gap_max": gaps[-1] if gaps else 0,
        "shapes": dict(sorted(shapes.items())),
        "on_convex": on_convex,
    }


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    pair = "--pair" in argv
    if not args:
        print(__doc__)
        return 1
    loaded = [(a, load(a)) for a in args]
    if pair and len(loaded) == 2:
        print("=== 地形结构 ===")
        sa = report("旧：" + loaded[0][0], loaded[0][1])
        print()
        sb = report("新：" + loaded[1][0], loaded[1][1])
        print()
        print("=== 障碍密度 ===")
        oa, ob = obstacles(loaded[0][1]), obstacles(loaded[1][1])
        for k in ("groups", "cols_per_group", "gap_p25", "gap_med", "gap_p75", "gap_max"):
            print("  %-14s %-8s → %s" % (k, oa[k], ob[k]))
        print()
        print("=== 结论 ===")
        print("  开挖率      %.1f%% → %.1f%%" % (sa["air_pct"], sb["air_pct"]))
        print("  最长无断裂  %d 列 → %d 列（%.1f → %.1f 个屏幕宽）"
              % (sa["longest_flat"], sb["longest_flat"],
                 sa["longest_flat"] * 64.0 / 1280.0, sb["longest_flat"] * 64.0 / 1280.0))
        print("  障碍密度    每 %.1f 列一组 → 每 %.1f 列一组（%+.0f%%）"
              % (oa["cols_per_group"], ob["cols_per_group"],
                 100.0 * (ob["cols_per_group"] - oa["cols_per_group"]) / oa["cols_per_group"]))
        return 0
    for i, (name, rows) in enumerate(loaded, 1):
        print("=== 第 %d 局（%s）===" % (i, name))
        report("", rows)
        o = obstacles(rows)
        print("  障碍 %d 组 → 每 %.1f 列一组 | 凸台上 %d 组 | 形态=%s | 组间距 P25=%d 中位=%d P75=%d 最大=%d"
              % (o["groups"], o["cols_per_group"], o["on_convex"], o["shapes"],
                 o["gap_p25"], o["gap_med"], o["gap_p75"], o["gap_max"]))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
