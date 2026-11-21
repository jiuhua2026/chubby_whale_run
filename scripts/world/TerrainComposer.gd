extends RefCounted
class_name TerrainComposer
## 程序化地形合成器 —— 按「小积木」现搭一块地形，而不是从固定模式库里查表。
##
## 存在理由（2026-09-28 实测）：
##   原来每块地形是「从 18 条手写模式里随机抽一条」，而模式里**障碍的位置、
##   数量、类型全是写死的字符串**。把统计倒出来，问题很明确：
##     · `low2_wide` / `low_then_slide` / `low_slide_low` / `dense_combo`
##       **一次都没被用过** —— 它们的障碍间距比 R4 要求的反应距离少 2~150px，
##       从开局起就被拒（`low2_wide` 只差 **2px**）；
##     · 剩下能用的 14 条里，12 条最多只有 1 个障碍，且障碍在块内的相对位置固定。
##   ⇒ 「开局地图雷同」「障碍位置数量类型没变化」是**结构性**的，调参数救不回来。
##
## 本类的输出**不保证可解** —— 和手写模式库完全一样，必须再过一遍 `Solvability`，
## 不通过就重摇。校验器始终是唯一的准入闸门。
##
## ## 结构（2026-09-28 第二版：把"段"提到块之上，见 `TerrainGenerator` 的 SECTION_*）
##
## ⚠ **上一版失败的原因，读这段就不会再犯**：上一版是在**单块内**混合坑和障碍，
## 也就是下面这张图 —— 坑被两条保护带挤在中间，只能是"两次呼吸之间的零头"：
##
##     （旧）短平台 │ 割裂带 │ ──保护带── 障碍 ──保护带── │ 割裂带 │ ──保护带── 障碍 ──保护带── │ 短平台
##
## 结果实测：**最长连续无断裂段 157 列（约 7.8 个屏幕宽）**、39% 的块一个坑都没有。
## 我上一轮统计的"每块坑段数 / 坑列占比"全都涨了，但**玩家看到的不是这些** ——
## 他看到的是"地面这条线有没有断"。局部多几个坑，改变不了"整条路还是一整块板"。
##
## 本版的做法：**坑和障碍不再抢同一块预算**，把它们分到不同的「段」里：
##
##     （新）实体段（3~4 块）：连续路面 + 密集障碍，坑只是点缀
##           断桥段（2~3 块）：**整段无障碍**，地面切成离散短台，坑能挖多宽挖多宽
##
## `build()` 负责实体段的一块，`build_broken()` 负责断桥段的一块。
##
## ## 保护带（只在实体段里付）
##
## **保护带 = 一段平地**，两条各管一件事。⚠ `Solvability` 的规则式校验器**两条都抓不到**
## —— 坑的 `hazard` 是 0，根本不算障碍组，R4 只比较「障碍 ↔ 障碍」：
##
##   · **前置保护带 → 防「坑 → 障碍」**：玩家跳过上一个坑之后**还在空中**
##     （状态=AIR，碰撞盒是站立的 104 高而不是滑铲的 54 高），这时撞上悬顶 ——
##     空中没法下滑，只能硬吃。所以障碍前面必须留够「起跳 → 落地 → 反应」，
##     长度就是 `min_hazard_spacing`（≥ 一次完整跳跃）。
##
##   · **后置保护带 → 防「障碍 → 坑」**：玩家正滑着钻过悬顶，前方一个坑会让他按跳，
##     而**跳跃会强制结束滑铲**，于是人在悬顶底下站起来了，当场撞头
##     （2026-09-28 用撞击调试器抓到的真事故：`滑键=是 玩家滑=是 状态=1`）。
##     所需的只是「发现坑 → 结束滑铲 → 站起来」，比前置带短一截，
##     见 `Difficulty.dip_after_clearance_px_for`。
##
## ⚠ **两条保护带只在"真的有坑"时才付**（`FRAG_CHANCE`）。没有坑的时候两组障碍之间
##   只需满足 R4 的 `min_hazard_spacing` —— 这一条同时就是"疏密对比"的来源：
##   留坑的间隔是不留的 2.6 倍。全部留坑实测障碍密度会稀掉 69%，全都空又均匀得没变化。
##
## ## 其余两条设计
##
##   · **割裂带**：1~2 段「浅坑 + 短平台」。在实体段里它只做"点缀起伏"，
##     真正的"离散空平台 / 不连续路段"由 `build_broken()` 整块整块地做。
##     块首块尾都落在平台上 ⇒ 接缝永远是 0→0，R1 自动成立，可解性推理被限制在块内。
##
##   · **障碍组数按难度档给分布**。⚠ 第一版的分布里刻意含 0（"整块不带障碍的空块"），
##     用来做疏密对比；现在**疏密对比搬到段这一层了**（断桥段整段无障碍），
##     所以实体段的分布改成**不含 0 且整体上调 ~1.4 倍** ——
##     否则约三分之一的块（断桥段）不放障碍，全局障碍密度会掉下去。
##
## ⚠ **割裂感的上限是物理给的，不是调参给的**：R2 判的是「一个 0 到下一个 0 的
##   跨度」，上限 = `max_safe_gap`。最低速 470px/s 时这条线只有 **3 格** ⇒
##   深度 1 的坑最多 2 列（128px）、深度 2 直接算不出来（`wmax` = 0）。
##   **开局那几千米在物理上就挖不出宽坑**，而玩家"这游戏地形很平"的印象正是
##   在开局形成的。所以断桥段只能靠**节奏**（平台尽量短）做割裂感。
##   ⚠ 2026-09-28 晚已把 `max_safe_gap_px_for` 的系数从 0.72 放宽到 0.83
##   （按"实际需要的水平位移"重推，见 `Difficulty.PIT_SAFETY`），
##   沟宽因此能从 3 列到 6 列（192~384px）变化 —— 但下限那一档仍是硬约束，抬不动了。

## 平台（层高 0 的连续段）的列数范围。
## 下限 2 不是随手取的：玩家碰撞盒宽 44px < 64px，1 列宽的平台在"落点必须容下
## 整个碰撞盒"这条上太紧，实测容易读成"刚落地就被下一段坑吃掉"。
const PLAT_MIN := 2
const PLAT_MAX := 4
## 凹陷宽度（列）。⚠ 这**不是** R2 判的"跨度" ——
## 跨度 = 下去的台阶 + 坑底 + 上来的台阶 + 收尾那列 0，见 `_dip_width()`。
## 旧注释在这里写成 "深度 1 → w+1、深度 2 → w+3"，正是那处 off-by-one 的来源。
##
## 上限从 3 提到 5（2026-09-28 晚）是为了让**沟宽真的能有长有短**：
## 实际能挖多宽由 `max_safe_gap_px_for()` 现算，这个常量只是静态天花板，
## 卡在 3 会让高速档的长沟永远出不来。
const DIP_MIN := 1
const DIP_MAX := 5
## 从哪一档开始允许挖 2 格深的坑（浅坑谁都能过，深坑要求更高的跳跃余量）。
## 取 0：深坑是"割裂感"最直接的来源 —— 浅坑在剖面图上只是一道小缺口。
## 速度撑不起时 `_dip_width()` 会返回 0，代码自动退回 1 格深，所以不必再设门槛。
const DEEP_DIP_FROM_TIER := 0
const DEEP_DIP_CHANCE := 0.45
## 实体段里一段割裂带默认有几组「坑 + 短平台」（`build()` 实际传 1~2，见调用处）。
## 断桥段不用这个值：它整块都是坑，由 `build_broken()` 自己控制。
const FRAG_UNITS_MIN := 2
const FRAG_UNITS_MAX := 3
## 割裂带内部短平台的列数范围（比主平台短：它只是把两个坑隔开，不是落点平台）
const FRAG_PLAT_MIN := 2
const FRAG_PLAT_MAX := 4
## 障碍**前面**放割裂带的概率（**实体段**用；断桥段整块都是割裂带，不看这个值）。
##
## ⚠ 它同时是**疏密对比的旋钮**：不留割裂带时两组障碍之间只需满足 R4 的
## `min_hazard_spacing`；留了就要额外付出「后置保护带 + 割裂带 + 前置保护带」。
##
## 第二版从 0.7 降到 0.35：割裂感改由**断桥段**承担，实体段再把坑塞满只会两败俱伤
## —— 坑和障碍抢同一段地形预算，坑多了障碍就稀。留 0.35 是为了实体段自己也有起伏。
const FRAG_CHANCE := 0.35
## 悬顶的列数范围（1 列装不下悬顶，R5 要求 ≥ 2；4 列长滑铲增强变化感）
const OVERHEAD_MIN := 2
const OVERHEAD_MAX := 4
## 悬顶出现的概率（其余是矮障碍，矮障碍固定单列完整贴图）
const OVERHEAD_CHANCE := 0.42
## 实体段内触发紧凑凸峰 / 凸台抬升与断桥高低错落的倾向
const MOUND_CHANCE := 0.36
const CONVEX_CHANCE := 0.28
const BROKEN_SHIFT_CHANCE := 0.48
## 保护带在最小长度之外额外多铺几列（0~这个值），拉大呼吸感，避免机械等距节拍。
const BAND_SLACK := 4
## **R4 间距的额外余量（列）。**
##
## R4 的要求随速度增长（`max(0.55·v, 1.15×跳跃距离)`），而地形是**提前**生成的：
## 一块刚生成时它的障碍间距刚好卡线，玩家再跑快几十 px/s，这条间距在
## "当下速度"下就变成 0 余量甚至不足。所以生成的间距必须留出**够它过期**的余量。
## 量级估算：速度增益 0.01 px/s 每 px · 一块约 40 列 = 2560px ⇒ 一块生命周期内
## 速度只涨 ~26px/s、R4 门槛涨 ~21px ⇒ **1 列（64px）余量足够**。
## 不给余量的后果（2026-09-28 实测）：尾巴间距卡在 0 余量 ⇒ 校验时被自身的
## 尾巴"违规"顶掉 ⇒ **所有候选（含纯平地）一起被拒** ⇒ 生成器走 `fallback_flat`。
const R4_MARGIN_COLS := 1
## 块长上限（列）。被「最多 4 组障碍 × 每组两条保护带」反推出来，
## 超过就说明这一档放不下这么多组，见 `_min_len`。
## 第二版从 52 提到 80：实体段要补上断桥段缺掉的障碍（`_obstacle_target`
## 分档上调到 2~4），而高速档每组障碍连保护带要吃 ~17 列，
## 4 组就要 70 列左右，52 会把它砍成 3 组、障碍密度补不回来。
const MAX_COLS := 80

# ---------------------------------------------------------------- 断桥段专用
## 一块断桥段的目标列数范围。**跨度拉大**（20~48 而不是 22~40）是为了让
## "这一段有多长"本身也成为不可预判的信息 —— 见文件头关于"宏观节拍"的说明。
const BROKEN_COLS_MIN := 20
const BROKEN_COLS_MAX := 48

## ★ **断桥段的节奏风格表 —— 这是"每块都不一样"的关键**（2026-09-28 晚补）。
##
## 上一版所有断桥块都用同一套平台宽度（3~5），于是整段读起来是**等间距**的：
## 玩家跳两次就能预判第三次跳在哪，那就不叫随机。现在每块**独立抽一种风格**，
## 于是一段断桥里会出现"急促 → 舒缓 → 中等"的来回切换。
##
##   plat_min/plat_max：常规平台列数
##   tight：抽到极短平台（2 列）的概率 —— 制造"这一段要连跳"的局部高压
##   breather：抽到长平台（6~9 列）的概率 —— 喘息点 / 起跳前的助跑道
##   deep：优先挖 2 格深坑的概率（深坑的碰撞跨度更大，所以急促风格用得更少）
##   **wide：坑宽的偏向**（0 偏短 / 0.5 均匀 / 1 偏长）
##
## ⚠ **`wide` 和 `plat_*` 是反着配的，这不是笔误** —— 被
##   `Difficulty.min_landing_px_for`（平台必须长到"满跳不飞过"）锁死的：
##   平台短 ⇒ 落点平台要长得靠"沟更宽"来抵（`P ≥ J − G`）⇒ **急促风格必须配长沟**。
##   所以"急促"= 短台 + 长沟（跳得远、落点小），"舒缓"= 长台 + 短沟（小步跳、有助跑道）。
##   配反了会被落点约束全部改回长平台，风格就名存实亡。
##
## ⚠ **绝不能把 TIGHT 变成常态**：实测（见 docs 4.13.1），平台压到 2~4 列时
##   "掉坑"从 7 次涨到 44 次。它是点缀，不是底色。
const BROKEN_RHYTHM_TIGHT := 0
const BROKEN_RHYTHM_MIX := 1
const BROKEN_RHYTHM_CALM := 2
## 块名后缀。带风格标记不只是好看 —— `--dump-terrain` 和 `usage_stats` 靠它
## 才看得出"这一局的节奏风格配比是什么"，比形状更早暴露"是不是又退化成一种节奏了"。
const BROKEN_RHYTHM_TAG := ["t", "m", "c"]
const BROKEN_RHYTHM_STYLE := [
	{"plat_min": 2, "plat_max": 3, "tight": 0.34, "breather": 0.06, "deep": 0.35,
		"wide": 0.88},
	{"plat_min": 3, "plat_max": 5, "tight": 0.22, "breather": 0.18, "deep": 0.60,
		"wide": 0.55},
	{"plat_min": 5, "plat_max": 9, "tight": 0.04, "breather": 0.30, "deep": 0.70,
		"wide": 0.22},
]

## 断桥段里**夹一个障碍**的概率。
##
## 为什么要开这个口子：断桥段整段不放障碍，玩两局就能学会"看到断崖就放松"——
## **可预判本身就是随机性不足**。夹进去之后"断桥段"不再等于"安全区"，
## 而且它天然产生一种新组合：**长平台 + 障碍，两侧都是深沟**。
## 障碍夹在一个够长的平台上（长度 = 前置保护带 + 障碍 + 后置保护带），
## 所以两条保护带的要求照旧满足，`Solvability` 那边也是同一套数字。
const BROKEN_OBSTACLE_CHANCE := 0.30

## 断桥段的坑跨度上限（列，含上下台阶与收尾那列 0）。
##
## 比 R2 允许的上限（`max_safe_gap_tiles`，最高速时是 6）**再留一格**：
## 断桥段要**连续**跳，每一次都吃满余量太苛刻 —— 留一格让长沟也有余量。
## 实际跨度范围因此是 **3~5 列 = 192~320px**（短沟 ↔ 长沟差 1.7 倍）。
##
## ⚠ **这个值决定深度 2 的坑存不存在**：深度 2 的跨度 = w + 4，
## 所以 `span_cap ≥ 5` 才可能出现 2 格深的坑。取 4 的话全程都只有浅坑
## （算出来的 w 是负数），"断"的观感会掉一半。
const BROKEN_GAP_CAP := 5

## 一段不带坑的连续路面，最长允许多少列 —— 超过就**强制**在下一个障碍组前插一个坑。
##
## 为什么需要一条硬上限，而不是靠 `frag_chance` 抽：
##   概率挡不住长块。`want` 2~4 的实体块本来就长（每组障碍连两条保护带要吃十几列），
##   再抽中"不留割裂带"，整块就是一条几十列的完整路面。**实测最长 63~77 列
##   （3.1~3.9 个屏幕宽）** —— 玩家连着两三秒收不到任何"路断了"的信号，
##   "割裂感"又回到上一版的老样子。
##   加这条上限之后，无论 `want` 和松弛度怎么随机，地面线都不会长时间不断；
##   而它是**上界**不是定值，所以坑的位置仍由概率决定、不会变成等间距。
##
## 为什么不是更小（比如 14）：一个障碍组本身就占 保护带 + 障碍 + 后置保护带
##   ≈ 18~22 列，上限压到 14 会让**每个**组间空隙都被迫挖坑，
##   实体段反而变成机械的等间距节奏。26 的效果是"通常靠概率、偶尔被强制"。
##
## ⚠ 检查点选在「刚铺完上一组的后置保护带、还没铺下一组的前置保护带」处，
##   并且**跨块接着算**（`carry`）—— 否则块接缝会变成规则的漏洞。
##
## 取 23 而不是更小：挖过一个坑之后，"坑尾平台 + 前置保护带 + 障碍 + 后置保护带"
## 本身就有 16~21 列平地（两条保护带是公平性硬要求，省不掉）。
## 上限压到 20 以下会让**每个**组间空隙都被迫挖坑 —— 节奏变成机械的等间距。
## 23 的效果是"隔一组挖一次"左右，仍有随机性。
const MAX_SOLID_RUN := 23

## 手写模式库的准入上限（列）。库模式是**固定字符串，不经过 `build()` 的强制挖坑**，
## 必须在 `TerrainGenerator._pick_library()` 里单独拦一道。
## 实测不拦的后果：连续几句 `flat10` / `low1` / `low2_wide` 拼出 **61 列**
## 不间断的路面 —— 合成器怎么改都救不回来。
## 取值 = `MAX_SOLID_RUN` + 一个障碍组的完整占用（两条保护带 + 障碍 ≈ 19 列），
## 也就是"不比合成器造得更差"。
const MAX_SOLID_RUN_WITH_LIBRARY := MAX_SOLID_RUN + 19


## 摇一块**实体段**地形。返回 {name, h, b, cols}；失败返回空字典。
##
## tail_b：上一块的障碍串，用来算「本块头几列不许有坑」。
## tail_flat_run：**截至块首、已经连续多少列是平地**（由生成器跨块累加）。
##   `MAX_SOLID_RUN` 必须跨块算，否则每块各自合格、接缝拼起来依然是一整条长路。
##   ⚠ 这个数**不能**从 tail_b/tail_h 现算：生成器只保留尾部 8 列做接缝上下文
##   （`keep := mini(8, ...)`），尾巴之前的平地看不到 —— 实测就是这样漏掉了
##   上一块尾巴的 34 列平地，硬上限形同虚设。
##
## frag_chance：这一块里"留割裂带"的概率。由调用方按段类型给
## （实体段给 `SOLID_FRAG_CHANCE`）—— 放在参数里而不是写死常量，
## 是为了让"实体段 / 断桥段"的差异在调用处一眼可见。
static func build(rng: RandomNumberGenerator, tier: int, speed: float,
		tail_b: PackedInt32Array, tail_flat_run: int, tail_gap_px: float,
		frag_chance: float = FRAG_CHANCE, start_level: int = 0) -> Dictionary:
	var tile := float(GameConfig.TILE)
	var min_space_px := Difficulty.min_hazard_spacing_px_for(speed)
	var safe_gap_px := Difficulty.max_safe_gap_px_for(speed)
	var band_before := maxi(1, int(ceil(min_space_px / tile))) + R4_MARGIN_COLS
	var band_after := maxi(1, int(ceil(Difficulty.dip_after_clearance_px_for(speed) / tile)))
	var min_gap_cols := band_before
	var max_gap_tiles := int(floor(safe_gap_px / tile))

	# ---- 1) 这一块放几组障碍、各自类型与跨几列 ----
	var want := _obstacle_target(rng, tier)
	var spans: Array[int] = []
	var kinds: Array[int] = []
	var over_hi := 3 if tier == 0 else OVERHEAD_MAX
	for i in want:
		if rng.randf() < OVERHEAD_CHANCE:
			kinds.append(TerrainPatterns.OVERHEAD)
			spans.append(rng.randi_range(OVERHEAD_MIN, over_hi))
		else:
			kinds.append(TerrainPatterns.LOW)
			spans.append(1)
	while want > 0 and _min_len(want, spans, band_before, band_after) > MAX_COLS:
		want -= 1
		spans = spans.slice(0, want)
		kinds = kinds.slice(0, want)

	# ---- 2) 搭骨架（支持紧凑凸峰、凹陷与高低台混排） ----
	var cur_lv := clampi(start_level, -2, 0)
	var h: Array[int] = []
	var obs_at: Array[int] = []
	var head := maxi(maxi(rng.randi_range(PLAT_MIN, PLAT_MAX),
		_tail_clearance(tail_b, band_after)), _landing_cols(speed, tail_gap_px))
	_append_level(h, cur_lv, head)
	var carry := tail_flat_run
	if want == 0:
		if cur_lv == 0:
			for i in rng.randi_range(2, 3):
				if rng.randf() < 0.5:
					_append_convex_mound(h, rng)
				else:
					_append_fragment_zone(h, rng, tier, max_gap_tiles, speed)
		else:
			_append_level(h, cur_lv, rng.randi_range(3, 5))
			cur_lv += 1
			_append_level(h, cur_lv, rng.randi_range(4, 6))
	else:
		for k in want:
			if k > 0:
				_append_level(h, cur_lv, band_after)
			var run := carry + _trailing_flat(h)
			var force_crack := (cur_lv == 0) and run >= MAX_SOLID_RUN
			var roll := rng.randf()
			var crack_p := frag_chance * 0.48
			var mound_p := crack_p + MOUND_CHANCE
			var crack := force_crack or ((cur_lv == 0) and roll < crack_p)
			var want_mound := (not crack) and (cur_lv == 0) and roll < mound_p
			var want_convex := (not crack) and (not want_mound) and (cur_lv > -2) and (
				roll < mound_p + CONVEX_CHANCE if cur_lv == 0 else rng.randf() < CONVEX_CHANCE)
			if crack:
				carry = 0
				var credit := _append_fragment_zone(h, rng, tier, max_gap_tiles, speed,
					rng.randi_range(1, 2))
				# 30% 概率在凹坑后紧跟一个紧凑凸峰，组成凹凸波浪
				if rng.randf() < 0.30:
					credit = _append_convex_mound(h, rng, maxi(4, credit))
				_append_level(h, 0, maxi(1, band_before - credit + rng.randi_range(0, BAND_SLACK)))
			elif want_mound:
				var need_mpre := 4 if k > 0 else maxi(4, _tail_clearance(tail_b, 5))
				var have_mpre := _trailing_same_level(h, 0)
				if have_mpre < need_mpre:
					_append_level(h, 0, need_mpre - have_mpre)
				var credit_m := _append_convex_mound(h, rng)
				_append_level(h, 0, maxi(1, band_before - credit_m + rng.randi_range(0, BAND_SLACK)))
			else:
				# 在平地 / 高台之间抽升降变化（不堵坑：只在没挖坑时变更高度）
				var moved := false
				if cur_lv < 0 and (run >= MAX_SOLID_RUN or rng.randf() < 0.44):
					# 确认当前层已经有足够长度（>=3）再降阶梯，满足 R2 台阶识别
					if _trailing_same_level(h, cur_lv) >= 3:
						cur_lv += 1
						moved = true
						var pad_down := maxi(3, band_before - band_after) if k > 0 else maxi(3, band_before)
						_append_level(h, cur_lv, pad_down + rng.randi_range(0, BAND_SLACK))
				elif want_convex:
					# 上台阶前确保当前层至少 4 列无障碍、且与上一块末尾悬顶距离足够（R8a）
					var need_pre := 4 if k > 0 else maxi(4, _tail_clearance(tail_b, 5))
					var have_pre := _trailing_same_level(h, cur_lv)
					if have_pre < need_pre:
						_append_level(h, cur_lv, need_pre - have_pre)
					cur_lv -= 1
					moved = true
					# 上台阶后顶面至少留 3 列再放障碍（R8b）
					var min_top := maxi(3, band_before - 1) if k == 0 else 3
					_append_level(h, cur_lv, min_top + rng.randi_range(0, BAND_SLACK))
				if not moved:
					if k > 0:
						_append_level(h, cur_lv, maxi(1, band_before - band_after + rng.randi_range(0, BAND_SLACK)))
					else:
						_append_level(h, cur_lv, band_before + rng.randi_range(0, BAND_SLACK))
			var span: int = spans[k]
			obs_at.append(h.size())
			_append_level(h, cur_lv, span)
		_append_level(h, cur_lv, band_after)

	# 尾端：若在高台上，约半数概率顺滑降回一级，另一半保留高度供下一块无缝延续
	if cur_lv < 0 and rng.randf() < 0.55 and _trailing_same_level(h, cur_lv) >= 3:
		cur_lv += 1
		_append_level(h, cur_lv, rng.randi_range(3, PLAT_MAX + 1))
	else:
		_append_level(h, cur_lv, rng.randi_range(PLAT_MIN, PLAT_MAX))

	# ---- 3) 跨块 R4 的安全网 ----
	if not obs_at.is_empty():
		var need := _tail_clearance(tail_b, min_gap_cols)
		if obs_at[0] < need:
			var pad := need - obs_at[0]
			var h0: int = h[0]
			for i in pad:
				h.insert(0, h0)
			for k in obs_at.size():
				obs_at[k] += pad

	# ---- 4) 铺障碍 ----
	var b: Array[int] = []
	b.resize(h.size())
	b.fill(0)
	for k in obs_at.size():
		var pos: int = obs_at[k]
		var span: int = spans[k]
		var kind: int = kinds[k]
		for i in span:
			b[pos + i] = kind

	return {"name": "proc_o%d" % obs_at.size(), "h": _to_packed(h), "b": _to_packed(b),
		"cols": h.size()}


# ---------------------------------------------------------------- 断桥段

## 摇一块**断桥段**：整块只有离散的短平台与坑，**一个障碍都不放**。
##
## 为什么不复用 `build()` 里的割裂带？—— 因为障碍两侧的两条保护带是**必须**付的
## （见文件头），它把坑挤成"两次呼吸之间的零头"；单块尺度的坑最多也就是 6~20 列。
## 断桥段把整块的"平地预算"都让给坑，才能做出**连续多屏**的"断成一段一段的空平台"。
##
## ⚠ 但宽度是有天花板的（`max_safe_gap`，见文件头的物理上限说明），
## 所以这里的策略是「坑取到允许的上限 + 平台尽量短」，靠**节奏**做割裂感：
## 平台 3~5 列（偶尔 2 / 6~7）、坑跨 3~4 列 ⇒ 大约 40~50% 的地面被挖掉。
## `cols_max`：本块的目标列数上限（-1 = 用 `BROKEN_COLS_MAX`）。
## 调用方用它压短**特定位置的**断桥块 —— 开局那一块、以及连着第二块
## （见 `TerrainGenerator.OPENING_BROKEN_COLS_MAX` / `CHASM_CHAIN_COLS_MAX`）。
## 单一长度范围做不到这件事：上限是全局的，而"开局别太长"是位置性的要求。
static func build_broken(rng: RandomNumberGenerator, speed: float,
		tail_b: PackedInt32Array, tail_gap_px: float, cols_max := -1,
		start_level: int = 0, tail_gap_delta: int = 0) -> Dictionary:
	var tile := float(GameConfig.TILE)
	var band_after := maxi(1, int(ceil(Difficulty.dip_after_clearance_px_for(speed) / tile)))
	var band_before := maxi(1, int(ceil(Difficulty.min_hazard_spacing_px_for(speed) / tile))) \
		+ R4_MARGIN_COLS

	var rhythm := _roll_broken_rhythm(rng)
	var cur_lv := clampi(start_level, -2, 0)

	var h: Array[int] = []
	var head := maxi(maxi(_broken_platform_style(rng, rhythm),
		_tail_clearance(tail_b, band_after)), _landing_cols_between(speed, tail_gap_px, tail_gap_delta))
	_append_level(h, cur_lv, head)

	var obs_at := -1
	var obs_span := 0
	var obs_kind := 0
	var obs_slot := -1
	if rng.randf() < BROKEN_OBSTACLE_CHANCE:
		if rng.randf() < OVERHEAD_CHANCE:
			obs_kind = TerrainPatterns.OVERHEAD
			obs_span = rng.randi_range(OVERHEAD_MIN, OVERHEAD_MAX)
		else:
			obs_kind = TerrainPatterns.LOW
			obs_span = 1
		obs_slot = rng.randi_range(1, 2)

	var hi := BROKEN_COLS_MAX if cols_max < 0 else mini(cols_max, BROKEN_COLS_MAX)
	var target := rng.randi_range(mini(BROKEN_COLS_MIN, hi), hi)
	var hard := hi if cols_max >= 0 else -1
	var style: Dictionary = BROKEN_RHYTHM_STYLE[rhythm]
	var placed := 0
	while h.size() < target and (hard < 0 or h.size() < hard):
		# 在 [-2, 0] 之间抽取下一块断桥平台高度（单跳最多爬升 1 格）
		var next_lv := cur_lv
		if rng.randf() < BROKEN_SHIFT_CHANCE:
			var choices: Array[int] = []
			if cur_lv > -2:
				choices.append(cur_lv - 1)
			if cur_lv < 0:
				choices.append(cur_lv + 1)
			if not choices.is_empty():
				next_lv = choices[rng.randi_range(0, choices.size() - 1)]
		var gap_cols := _append_broken_chasm(h, rng, speed, cur_lv, next_lv, float(style["wide"]))
		if gap_cols <= 0:
			# 若往高处跳当前速度挖不出安全沟，退回同高度重试
			next_lv = cur_lv
			gap_cols = _append_broken_chasm(h, rng, speed, cur_lv, next_lv, float(style["wide"]))
		if gap_cols <= 0:
			break
		var gap_px := float(gap_cols) * tile
		var step_delta := next_lv - cur_lv
		cur_lv = next_lv
		placed += 1
		if obs_slot == placed - 1 and obs_span > 0:
			var need_land := _landing_cols_between(speed, gap_px, step_delta)
			_append_level(h, cur_lv, maxi(band_before, need_land))
			obs_at = h.size()
			_append_level(h, cur_lv, obs_span)
			_append_level(h, cur_lv, band_after)
			obs_slot = -1
		else:
			_append_level(h, cur_lv, maxi(_broken_platform_style(rng, rhythm),
				_landing_cols_between(speed, gap_px, step_delta)))
	if placed == 0:
		return {}

	var b := _packed_zeros(h.size())
	if obs_at >= 0:
		for i in obs_span:
			b[obs_at + i] = obs_kind
	return {"name": "proc_brk%d%s" % [placed, BROKEN_RHYTHM_TAG[rhythm]],
		"h": _to_packed(h), "b": b, "cols": h.size()}


## 抽这一块的断桥节奏风格。权重刻意偏向"中等"，两头当点缀 ——
## 全抽极端会变成另一种规律（要么一直连跳、要么一直大跨）。
static func _roll_broken_rhythm(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.33:
		return BROKEN_RHYTHM_TIGHT
	if r < 0.73:
		return BROKEN_RHYTHM_MIX
	return BROKEN_RHYTHM_CALM


## 断桥段专用：挖一个坑。**宽度在这个速度允许的范围内随机**（短沟 ↔ 长沟）。
## 返回**坑的可见宽度（px）**；0 表示这个速度下一格都挖不出。宽度受三层夹：
##   · R2 的上限 `max_gap_tiles`（随速度变，起步只有 4 格 —— 见 `Difficulty.PIT_SAFETY`）
##   · `DIP_MAX`（单次挖宽的静态天花板）
##   · `BROKEN_GAP_CAP`（断桥段自己留的余量，见常量注释）
##
## ⚠ 返回值不是"跨度"：跨度还包含收尾那列 0（R2 用的口径），
##   而**落点平台长度要减的是可见宽度**（见 `Difficulty.min_landing_px_for`）。
##   两个口径混用就会把平台算短一列、又掉进下一个沟。
##
## `wide`（0=偏短 / 1=偏长）来自节奏风格，见 `BROKEN_RHYTHM_STYLE`。
## 断桥段专用：挖一段无底深沟（支持起落高度差）。返回可见坑列数（0 表示挖不出）。
static func _append_broken_chasm(h: Array[int], rng: RandomNumberGenerator,
		speed: float, h_from: int, h_to: int, wide: float) -> int:
	var tile := float(GameConfig.TILE)
	var max_span := int(floor(Difficulty.max_safe_gap_px_between(speed, h_from, h_to) / tile))
	var span_cap := mini(max_span, 4 if h_to < h_from else BROKEN_GAP_CAP)
	var k_max := span_cap - 1
	if k_max < 1:
		return 0
	var k_min := 1 if (h_to < h_from or k_max < 2) else 2
	var k := k_min
	if k_max > k_min:
		k = clampi(k_min - 1 + _biased_width(rng, k_max - k_min + 1, wide), k_min, k_max)
	for _i in k:
		h.append(1)
	return k


## 在 [1, wmax] 里取宽度，`wide` 控制偏向：0 偏短、0.5 均匀、1 偏长。
## 用幂函数变形而不是"取两端的随机数" —— 后者会做出"要么最短要么最长、中间没有"
## 的哑铃分布，横跨沟的时候手感会两极分化。
static func _biased_width(rng: RandomNumberGenerator, wmax: int, wide: float) -> int:
	if wmax <= 1:
		return 1
	var t := rng.randf()
	# wide 0.5 时指数为 1（均匀）；<0.5 指数 >1（往 0 压 = 偏短）；>0.5 指数 <1（偏长）
	var tilt := (0.5 - wide) * 2.4
	var e := 1.0 + tilt if tilt >= 0.0 else 1.0 / (1.0 - tilt)
	t = pow(t, e)
	return clampi(1 + int(round(t * float(wmax - 1))), 1, wmax)


## 断桥段里两个坑之间的平台列数（**只看节奏风格**）。
##
## ⚠ 调用方还要跟 `Difficulty.min_landing_px_for()` 的结果取大者 ——
##   平台必须长到"一次满跳不会飞过它"，否则玩家会落进**下一个**坑里（现在是死亡）。
##   这条约束把"平台长度"和"沟宽"绑在一起：**平台越短，沟就必须越宽**。
##   所以风格表里**急促**风格的 `wide` 反而偏长（见那边的注释）。
static func _broken_platform_style(rng: RandomNumberGenerator, rhythm: int) -> int:
	var s: Dictionary = BROKEN_RHYTHM_STYLE[rhythm]
	var r := rng.randf()
	if r < float(s["tight"]):
		return 2
	if r < 1.0 - float(s["breather"]):
		return rng.randi_range(int(s["plat_min"]), int(s["plat_max"]))
	return rng.randi_range(6, 9)


## 落点平台的最小列数（由沟宽和起落高度差反推）。
static func _landing_cols(speed: float, gap_px: float) -> int:
	return _landing_cols_between(speed, gap_px, 0)


static func _landing_cols_between(speed: float, gap_px: float, step_delta: int) -> int:
	if gap_px <= 0.0:
		return 0
	return int(ceil(Difficulty.min_landing_px_between(speed, gap_px, 0, step_delta) / float(GameConfig.TILE)))


# ---------------------------------------------------------------- 打包工具
## Array[int] → PackedInt32Array。
## ⚠ 别在各处手写这个循环：`b` 和 `h` 的长度必须严格相等（`Solvability`
##   第一件事就是查长度），漏掉一处就是一个静默的"整块被拒"。
static func _to_packed(a: Array[int]) -> PackedInt32Array:
	var p := PackedInt32Array()
	p.resize(a.size())
	for i in a.size():
		p[i] = a[i]
	return p


static func _packed_zeros(n: int) -> PackedInt32Array:
	var p := PackedInt32Array()
	p.resize(n)
	return p


## 尾部有多少列是连续无坑台面（层高 <= 0，含高台 -1/-2）。
static func _trailing_flat(a: Array[int]) -> int:
	var n := 0
	for i in range(a.size() - 1, -1, -1):
		if a[i] > 0:
			break
		n += 1
	return n


## 尾部有多少列停在指定的同一层高 `lv`。
static func _trailing_same_level(a: Array[int], lv: int) -> int:
	var n := 0
	for i in range(a.size() - 1, -1, -1):
		if a[i] != lv:
			break
		n += 1
	return n


## 一块地形**开头**连续多少列是连续无坑台面。
static func leading_flat(a: PackedInt32Array) -> int:
	var n := 0
	for i in a.size():
		if a[i] > 0:
			break
		n += 1
	return n


# ---------------------------------------------------------------- 骨架积木

## 追加一段指定层高 `lv` 的平台
static func _append_level(h: Array[int], lv: int, m: int) -> void:
	for i in maxi(1, m):
		h.append(lv)


## 追加一段平台（层高 0）
static func _append_flat(h: Array[int], m: int) -> void:
	_append_level(h, 0, m)


## 一段割裂带：`units` 组「浅坑 + 短平台」（不传则用 FRAG_UNITS_* 随机）。
## 这是"离散的空平台 / 不连续路段"的基本单元。
##
## **返回收尾那段短平台的列数**：它是平地，所以本来就顶得上「前置保护带」的一部分，
## 调用方拿这个数去抵扣，可以少铺几列（实测约占保护带的三分之一，白白铺掉很浪费）。
static func _append_fragment_zone(h: Array[int], rng: RandomNumberGenerator,
		tier: int, max_gap_tiles: int, speed: float, units: int = -1) -> int:
	var tail_flat := 0
	var n := units if units > 0 else rng.randi_range(FRAG_UNITS_MIN, FRAG_UNITS_MAX)
	for i in n:
		var depth := 1
		if tier >= DEEP_DIP_FROM_TIER and rng.randf() < DEEP_DIP_CHANCE:
			depth = 2
		var w := _dip_width(rng, depth, max_gap_tiles)
		if w <= 0:
			depth = 1
			w = _dip_width(rng, 1, max_gap_tiles)
		var gap_px := 0.0
		if w > 0:
			_append_dip(h, depth, w)
			gap_px = float(w + 1 if depth == 1 else w + 3) * float(GameConfig.TILE)
		# ⚠ 这里也必须套用落点约束：割裂带内部**两个坑之间**就是一小段平台，
		#   不套的话一次满跳会飞过它、落进第二个坑 —— 那条命就没了。
		tail_flat = maxi(rng.randi_range(FRAG_PLAT_MIN, FRAG_PLAT_MAX),
			_landing_cols(speed, gap_px))
		_append_flat(h, tail_flat)
	return tail_flat


## 追加一座同屏可见的紧凑凸起山包 / 阶梯凸峰（1 级 4~6 列，或 2 级阶梯 6~9 列）。
## 返回尾部平地 0 的列数（供后续前置保护带抵扣）。
static func _append_convex_mound(h: Array[int], rng: RandomNumberGenerator,
		min_pre_flat: int = 4) -> int:
	var have := _trailing_same_level(h, 0)
	if have < min_pre_flat:
		_append_level(h, 0, min_pre_flat - have)
	if rng.randf() < 0.65:
		# 两级对称阶梯凸峰（0 → -1 → -2 → -1 → 0），与深凹谷上下镜像
		_append_level(h, -1, rng.randi_range(2, 3))
		_append_level(h, -2, rng.randi_range(2, 4))
		_append_level(h, -1, rng.randi_range(1, 2))
	else:
		# 单级紧凑凸台（0 → -1 → 0）
		_append_level(h, -1, rng.randi_range(3, 5))
	var tail_flat := rng.randi_range(3, 4)
	_append_level(h, 0, tail_flat)
	return tail_flat


## 追加一段凹陷。
## ⚠ 只写「下去的台阶 + 坑底 + 回来的台阶（不含最后那格 0）」——
##   收尾的 0 由后面那段平台提供，这样 h 的结构天然是 `平台 凹陷 平台 凹陷 …`，
##   块尾一定落在平台上（接缝 0→0）。
## 层高方向记牢：0 是最高层，数值越大越深。
static func _append_dip(h: Array[int], depth: int, w: int) -> void:
	for d in range(1, depth + 1):
		h.append(d)
	for i in w:
		h.append(depth)
	for d in range(depth - 1, 0, -1):
		h.append(d)


## 能挖多宽。返回 0 表示这个速度下挖不了（起步阶段安全跳距太小）。
##
## ⚠ **`overhead` 是「跨度」减「坑底宽度」，必须按跨度算**（2026-09-28 修）：
##   层高 0 是最高层，所以从上一个 0 到下一个 0 的跨度 =
##     下去的台阶 + 坑底 + 上来的台阶 + **回来的那一列 0**
##     深度 1：[1] + w + [] + **1** = w + 2
##     深度 2：[1,2] + w + [1] + **1** = w + 4
##   旧版按 w+1 / w+3 算（漏了收尾那列 0），于是**每个坑都比安全线宽 1 列 = 64px**，
##   被 R2 判成「需掉入再爬出」；`strict = true` 下这直接变成拒绝 ——
##   表现为合成器反复重摇、断桥段在低速档一格都挖不出（退回实体段）。
static func _dip_width(rng: RandomNumberGenerator, depth: int, max_gap_tiles: int) -> int:
	var overhead := 2 if depth == 1 else 4
	var wmax := mini(DIP_MAX, max_gap_tiles - overhead)
	if wmax < DIP_MIN:
		return 0
	return rng.randi_range(DIP_MIN, wmax)


# ---------------------------------------------------------------- 障碍投放

## 这一块（**实体段**）的目标障碍组数。
##
## 第二版的两个改动：
##   1. **去掉了 0**。第一版靠"整块不带障碍的空块"做疏密对比；现在这个角色
##      由断桥段承担（整段不放障碍，而且一放就是两三块），比单块的稀疏强得多。
##      而且约 1/3 的块是断桥段，实体段再来空块会让障碍密度塌掉。
##   2. **整体上调**，用来补上断桥段缺掉的障碍。
##      ⚠ 比例是按"断桥段占块数"倒推的，而那个比例现在由
##      `TerrainGenerator` 的 `SOLID/BROKEN_CHUNKS_*` **和每局的「地形性格」**共同决定
##      ⇒ **改那几个常量或 `PERSONA_MIX` 之后必须重量一次障碍密度**
##      （`tools/terrain_stats.py`），否则它会悄悄漂走，而且是不会报错的那种漂。
static func _obstacle_target(rng: RandomNumberGenerator, tier: int) -> int:
	var pool: Array[int]
	match tier:
		0:
			pool = [1, 2, 2, 3, 3, 3]
		1:
			pool = [1, 2, 3, 3, 3, 3]
		2:
			pool = [2, 2, 3, 3, 4, 4]
		_:
			pool = [2, 3, 3, 4, 4, 4]
	return pool[rng.randi_range(0, pool.size() - 1)]


## 放 `want` 组障碍最少需要多少列（按"不留割裂带"这条最省的路算）：
##   首尾平台 + 最后一组的后置保护带 + 每组「前置保护带 + 障碍」+ 组间最小余量。
## 超过 `MAX_COLS` 就把目标组数往下调 —— 高速档保护带更长，能放的组数自然更少。
static func _min_len(want: int, spans: Array[int], band_before: int, band_after: int) -> int:
	var t := PLAT_MIN * 2 + band_after
	for i in mini(want, spans.size()):
		t += band_before + spans[i]
	t += maxi(0, want - 1) * 4
	return t


## 上一块尾部的最后一组障碍，离本块首列还有几列。
## 用来给本块第一组障碍兜底（见 `build()` 第 3 步）。返回 1 表示尾部没有障碍。
static func _tail_clearance(tail_b: PackedInt32Array, min_gap_cols: int) -> int:
	for i in range(tail_b.size() - 1, -1, -1):
		if tail_b[i] != 0:
			# 尾部最后一组障碍的末列在第 i 列，距块首 (size - i) 列
			return maxi(0, min_gap_cols - (tail_b.size() - i))
	return 1
