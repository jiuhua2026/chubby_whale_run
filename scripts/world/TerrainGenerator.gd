extends Node2D
class_name TerrainGenerator
## 程序化地形生成器（块制 + 可解性准入）。
##
## 工作方式：
##   1. 维护一个「已生成到第几列」的游标，每帧保证玩家前方有 generate_ahead 米的地形。
##   2. 每次要追加一块时，从模式库里筛出所有**接缝合法**的候选：
##        把「上一块的尾部 + 候选模式」拼起来丢给 Solvability，
##        通过才允许使用。这是保证"只用跳或滑就能过"的关键——不通过就不生成。
##   3. 玩家身后的块回收掉。
##
## 为什么按「块」而不是按「无限噪声」生成：
##   纯噪声地形无法保证可解性，只能靠事后修补，越修越乱。
##   用「人工核对过的模式 + 拼接时校验」把可解性变成编译期问题而不是运行期问题。

## 严格模式：连"需要掉进坑里再爬出来"的模式也不要。
## 垂直切片阶段建议保持 true，等手感稳了再放开换变化度。
var strict := true
## 平坦模式：只出平坦无障碍的地面。测试模式用它腾空一切干扰，
## 剩下的画面里只有角色本身，适合反复看动作。
var flat_only := false
## 起跑安全区列数（保证开局不会一上来就撞障碍）
var safe_start_cols := 24

const LEVEL_UNLOADED := -999

var _patterns: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _chunks: Array[TerrainChunk] = []
var _next_col := 0
var _tail_h := PackedInt32Array()
var _tail_b := PackedInt32Array()
var _tail_flat_run := 0
var _tail_gap_px := 0
var _tail_gap_delta := 0
var _last_name := ""

const PROC_TRIES := 8
## 优先走手写模式库的概率：主干交给支持凸台/凹谷的合成器，手写库作经典节奏点缀。
const LIBRARY_MIX := 0.12
## 手工插桩队列：非空时优先按剧本出块（用于高潮追击段）
var _script_queue: Array[String] = []
## 统计：每个模式被拒的原因，调参时非常有用
var reject_stats := {}
## 统计：每个模式实际被用了多少次。理想分布是 tier 0 的模式随时间占比下降，
## 高难度模式逐步接管；如果某个模式始终为 0，说明它的准入条件永远满足不了。
var usage_stats := {}
## 每个模式「第一次被拒」的具体原因。只看拒绝次数分不清是地形真不合规还是校验器误报。
var reject_reasons := {}

# ---------------------------------------------------------------- 分段结构
## 地图由两种「段」交替组成，而不是每块独立掷骰子。**这是"割裂感"的关键所在**：
##
##   · **实体段**（SECTION_SOLID）：近似连续的路面 + 密集障碍，坑只是点缀。
##   · **断桥段**（SECTION_BROKEN）：**整段不放障碍**，地面被切成离散短台，
##     中间是"能挖多宽挖多宽"的坑。
##
## 为什么必须在"段"这一层做，而不是在块内多放几个坑（第二版的核心教训）：
##   障碍两侧各要一条平地保护带（真事故逼出来的，见 TerrainComposer 文件头），
##   而**地形预算是一定的** —— 坑和障碍在抢同一段长度。只要它们还挤在同一块里，
##   坑就只能是"两次呼吸之间的零头"。实测上一版**最长连续无断裂段 157 列
##   （约 7.8 个屏幕宽）、39% 的块一个坑都没有** —— 玩家看到的还是"一整条路"。
##   段级交替把疏密对比从"块内随机"升级到"整屏尺度"：
##   连续 2~3 块、上百列都断成一段一段，想忽略都难。
##
## 代价：断桥段不放障碍 ⇒ 障碍密度全靠实体段补回来，
## 所以 `TerrainComposer._obstacle_target` 的分档同步上调了约 1.4 倍。
const SECTION_SOLID := 0
const SECTION_BROKEN := 1
## 一段持续几块。
##
## ⚠ 这是**割裂感 / 障碍密度 / 观感随机性**三者的共同主旋钮。跨度拉得很大
## （实体 1~5、断桥 1~4）是刻意的：**段长本身也要不可预判**。
## 上一版固定 2~3 块，玩两局就能摸出"跳一会儿、然后来一段障碍"的固定节拍
## —— 那正是"地图随机性不足"里最扎眼的一条。
const SOLID_CHUNKS_MIN := 1
const SOLID_CHUNKS_MAX := 5
const BROKEN_CHUNKS_MIN := 1
const BROKEN_CHUNKS_MAX := 3
## 段长的**硬上限**（乘完性格倍率之后再夹）。断桥段比实体段更紧，理由见 `_persona_chunks`。
const SOLID_CHUNKS_CAP := 5
const BROKEN_CHUNKS_CAP := 4

## ★ **每局的地形性格**：开局抽一次，整局按它偏置"段长倍率 / 转段概率"。
##
## 为什么需要它：段级随机只保证**逐块不同**，可每局的宏观配比仍然一样
## （都是"实体 2~3 块 + 断桥 2~3 块"轮换），多玩几局就会觉得"还是那个套路"。
## 性格让"这一局整体偏断桥 / 偏障碍 / 忽长忽短"变成**可感知**的差异 ——
## 这是"每次生成的地图布局更加多样"里最直接有效的一招。
enum { PERSONA_BALANCED, PERSONA_CHASM, PERSONA_GAUNTLET, PERSONA_VOLATILE }
const PERSONA_NAME := ["均衡", "重断桥", "重障碍", "忽长忽短"]
## 每种性格：(实体段长倍率, 断桥段长倍率, 转断桥概率)。
##
## ⚠ 倍率作用在**段长**上，之后仍会被 `clampi(..., 1, 6)` 兜住 ——
##   段太长会让玩家长达十几秒见不到另一种地形，反而更单调。
## ⚠ 转断桥概率只对"重障碍"明显下调（0.55）：那是唯一会让障碍变多的性格，
##   压太低会连着好几屏都是障碍区，难度曲线会跳。
const PERSONA_MIX := [
	[1.0, 1.0, 0.85],
	[0.55, 1.2, 0.95],
	[1.6, 0.50, 0.55],
	[0.45, 0.45, 0.75],
]

## 实体段里"留割裂带"的概率（透传给 TerrainComposer.build）。比第一版的 0.7 低：
## 割裂感主要由断桥段承担，实体段再塞满坑会让障碍没地方放（两者抢同一份预算）。
## ⚠ 这个概率不是唯一的闸门 —— `TerrainComposer.MAX_SOLID_RUN` 会**强制**打断
## 过长的连续路面，所以调小它不会让地图重新变回"一整条路"，只会让坑的位置更随机。
## ⚠ 2026-09-29 从 0.45 提到 0.60：实心岛（`BROKEN_ISLAND_CHANCE`）和开局配额
##   一起把"开挖率"从 18.7% 稀释到 14.8% —— 那等于把"割裂感"退回老水平。
##   **但不能靠加长断桥段去补**（那正是"连续多次断崖"的来源），正确杠杆是
##   **提高实体段/岛内部的凹陷密度**：它加的是"地面起伏"，不是"连续深沟"，
##   而且顺便把凹面地形做得更足。实测这样能把开挖率拉回 19% 上下，
##   同时"最长连续无断裂段"仍压在 ~42 列（2.1 屏）。
const SOLID_FRAG_CHANCE := 0.68

## ★ **开局配额**：头两段各自最多几块，且**必须一实体一断桥**。
##
## ## 为什么要这一条（2026-09-29，用户第三次提"开局形态单一"）
## 之前是「`_first_section` 把第一段**写死成断桥**」—— 当时的理由是对的
## （玩家对这游戏地形的印象在开局几秒形成，不能一上来就是两屏连续路面），
## 但代价是**每一局的开局都是断崖**：实测 **12/12 局**开局都是断崖段，
## 其中最长的一局开头是 **193 列 ≈ 3 个屏幕全是沟**（见 docs 4.16）。
## 刷几次自然就觉得"地图就这一种形态"。
##
## 反过来全随机也不行：会连抽两段实体，起步两屏全是连续路面 —— 那正是更早一版被否掉的问题。
##
## ⇒ 解法不是"取消强制"，而是**强制两段不同类型的短段**：
##   头两段各限 1~2 块、且类型相反 ⇒ 开局一定能看到"路断了"和"有障碍的连续路"
##   两种形态；而段内细节（节奏风格、沟宽、障碍组合）仍然是随机的。
##   ⚠ 这里**不乘性格倍率**：性格只作用于第三段之后，否则「重断桥」又会把开局撑成一条长沟。
## ⚠ 取 1（不是 2）：一块断桥块本身就有 20~48 列（1~2.4 个屏幕），
##   给 2 块就允许开局先来 4.8 个屏幕的纯沟 —— 实测仍有 1/12 局是这样。
##   ⇒ 头两段各**只给 1 块**，保证"沟 → 路"在一个屏幕左右就完成切换。
const OPENING_CHUNKS_MAX := 1
## 连续几块都是**断崖块**之后，**强制**插一块实心岛。
##
## 和 `TerrainComposer.MAX_SOLID_RUN` 是同一个道理：**概率挡不住连号**。
## 岛的概率 0.35 看着不低，但不加硬上限时"连着 2 块都不是岛"有 42%、3 块有 27% ——
## 实测就抓到过"开局 2 块断崖 = 92 列（4.6 个屏幕）纯沟"。
## 加上限之后，纯沟最多 2 块，之后必然夹一块"有起伏、有障碍、能站住"的岛。
const MAX_CHASM_CHUNKS := 2
## 开局那一块断桥块的**列数**上限。一块断桥块本身能干到 48 列（2.4 个屏幕），
## 对"开局第一印象"来说太长 ⇒ 单独压到 30 列（1.5 个屏幕）。
const OPENING_BROKEN_COLS_MAX := 30
## 连着第二块断桥块的列数上限（同上，见 `MAX_CHASM_CHUNKS`）。
## 两块相加最多 48+30 = 78 列（3.9 个屏幕），比放开时少掉 1/5。
const CHASM_CHAIN_COLS_MAX := 30
## 断崖段里**夹一块「实心岛」**的概率（见 `_append_chunk` 的断桥分支）。
##
## 这一条治的是"连续多次断崖这种单一形态"**本身**：
##   断桥段内部原来只有"平台 + 沟"一种构成（节奏风格只改间距），所以一段长断桥
##   从宏观上看就是**同一种东西重复**。夹进实心岛之后，一段断桥里会出现
##   「沟—沟—**有起伏、有障碍、能站住的岛**—沟」，两种形态交替。
##   实测它同时把"连续纯沟"的最长长度压下来（4 块断桥里平均夹 1.4 个岛）。
const BROKEN_ISLAND_CHANCE := 0.35

var _section := SECTION_SOLID
var _section_left := 0
## 本局的「地形性格」（见 PERSONA_*）。每局开局在 `reset()` 里重抽一次。
var _persona := PERSONA_BALANCED
## 开局配额的状态：0 = 头两段都还没定，1 = 第一段已定（第二段要取反），2 = 配额用完。
var _opening_stage := 0
## 头两段里**哪一段是断桥**。每局开局抽一次，所以"先沟后障碍"和"先障碍后沟"各占一半。
var _opening_start_broken := false
## 截至上一块，**已经连续几块是断崖块**（见 `MAX_CHASM_CHUNKS`）。
var _chasm_run := 0

## `-- --dump-terrain`：每生成一块就把它的 `h`/`b` 打印成 ASCII。
##
## 用途是验证「每局地形是否真的不同」—— `usage_stats` 只能告诉你用了哪些模式名，
## 看不出实际形状，更比不出"这一局和上一局像不像"。ASCII 倒出来就能逐列 diff。
var dump_terrain := false


func _ready() -> void:
	_patterns = TerrainPatterns.all()
	var s := _seed_from_args()
	if s >= 0:
		_rng.seed = s
	else:
		_rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--dump-terrain":
			dump_terrain = true
	if _patterns.is_empty():
		push_error("地形模式库为空，生成器无法工作")


## `-- --seed=N`：固定随机种子，用来复现某一局的地形。
##
## 为什么需要它：地形是随机的，"这一局的地形有问题"这句话在没有种子时
## 等于无法复现 —— 只能靠反复跑撞运气。修地形规则时这一点很要命。
func _seed_from_args() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			return int(a.substr("--seed=".length()))
	return -1


func reset() -> void:
	for c in _chunks:
		c.queue_free()
	_chunks.clear()
	_next_col = 0
	_tail_h = PackedInt32Array()
	_tail_b = PackedInt32Array()
	_tail_flat_run = 0
	_tail_gap_px = 0
	_tail_gap_delta = 0
	_last_name = ""
	_script_queue.clear()
	_section = SECTION_SOLID
	_section_left = 0
	# 每局重抽一次「地形性格」。放在 reset 而不是 _ready：一局结束时重开要换性格，
	# 否则"重开同一套地形"的感觉还是没解决。
	_persona = _rng.randi_range(0, PERSONA_MIX.size() - 1)
	# 开局配额（见 OPENING_CHUNKS_MAX）：先定"头两段谁先来"，再让 `_roll_section` 执行。
	# ⚠ **`_rng.seed` 只在 `_ready` 里 randomize 过一次**，之后每局重开只是继续用同一条
	#   随机流 ⇒ 每局地形不同、但**开局的形态一定对**。这正是"刷好几次都一个样"的地方。
	_opening_stage = 0
	_opening_start_broken = _rng.randf() < 0.5
	_chasm_run = 0
	reject_stats.clear()
	reject_reasons.clear()
	usage_stats.clear()
	print("[terrain] 本局种子 %d，地形性格「%s」（要复现这局：-- --seed=%d）"
		% [_rng.seed, PERSONA_NAME[_persona], _rng.seed])
	_append_safe_start()
	_append_chunk()


## 每帧调用：向前铺地形，向后回收
func update_for(player_x: float) -> void:
	var guard := 0
	while float(_next_col * GameConfig.TILE) < player_x + GameConfig.generate_ahead:
		if not _append_chunk():
			break
		guard += 1
		if guard > 32:
			push_warning("地形生成器单帧生成过多，已中断")
			break
	var limit := player_x - GameConfig.recycle_behind
	while not _chunks.is_empty() and _chunks[0].world_right() < limit:
		_chunks.pop_front().queue_free()


func chunk_count() -> int:
	return _chunks.size()


func total_cols_generated() -> int:
	return _next_col


## 手工插桩：把接下来的若干块换成指定模式的顺序。
## 这是「程序生成 + 手工插桩」里的插桩口——高潮追击段用它换取可控节奏。
func push_script(names: Array[String]) -> void:
	for n in names:
		_script_queue.append(n)


## 清空剧本队列。追击段结束时调用，避免残留条目污染普通路段。
func clear_script() -> void:
	_script_queue.clear()


func script_remaining() -> int:
	return _script_queue.size()


func _find_pattern(name: String) -> Dictionary:
	for p in _patterns:
		if p["name"] == name:
			return p
	return {}


## 采样从世界坐标 x 开始、往后 span_cols 列的地形数据。
## 供自动驾驶（无头自检）使用——它是验证「地形真的只用跳/滑就能过」的唯一手段，
## 因为规则式校验器理论上可能漏掉组合情况，只有让一个只用两个键的驱动器
## 实际跑过去，才能证明生成器的输出确实可解。
func sample(x: float, span_cols: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c0 := int(floor(x / float(GameConfig.TILE)))
	for i in span_cols:
		var c := c0 + i
		var lv := LEVEL_UNLOADED
		var hz := 0
		for ch in _chunks:
			var off := c - ch.start_col
			if off >= 0 and off < ch.h.size():
				lv = ch.h[off]
				hz = ch.b[off]
				break
		out.append({"col": c, "level": lv, "hazard": hz})
	return out


## 世界坐标某列的地面层高；未生成时返回 LEVEL_UNLOADED
func level_at_world(x: float) -> int:
	var c := int(floor(x / float(GameConfig.TILE)))
	for ch in _chunks:
		var off := c - ch.start_col
		if off >= 0 and off < ch.h.size():
			return ch.h[off]
	return LEVEL_UNLOADED


# ---------------------------------------------------------------- 生成

func _append_safe_start() -> void:
	var h := PackedInt32Array()
	var b := PackedInt32Array()
	for i in safe_start_cols:
		h.append(0)
		b.append(0)
	_commit("safe_start", h, b)


## 追加一块。返回 false 表示无法生成（正常情况下不该发生）。
func _append_chunk() -> bool:
	# 测试模式：只铺平坦无障碍的地面。
	# 放在最前面短路，连模式库和校验器都不用跑——观察模式下不该有任何随机性。
	if flat_only:
		_commit_flat()
		return true

	var tier := Difficulty.current_tier()
	var speed := Difficulty.player_target_speed()

	# 0) 有剧本时优先走剧本（高潮追击段的手工插桩）
	if not _script_queue.is_empty():
		var want: String = _script_queue.pop_front()
		var sp := _find_pattern(want)
		if sp.is_empty():
			push_warning("剧本引用了不存在的模式：" + want)
		else:
			var mh: PackedInt32Array = _tail_h + sp["h"]
			var mb: PackedInt32Array = _tail_b + sp["b"]
			var sres := Solvability.validate(mh, mb, speed, _tail_h.size())
			if sres["ok"] and (not strict or sres["warnings"].is_empty()):
				_last_name = sp["name"]
				_commit(sp["name"], sp["h"], sp["b"])
				# 剧本（高潮追击）刚跑完不要紧接着来断桥段：追击段本来就是压力峰值，
				# 再叠一段"跳—落—跳"很容易变成必死。剧本期间每次都把它归零，
				# 于是剧本排空后必然先走 2 块实体路，给玩家一个缓冲。
				_section = SECTION_SOLID
				_section_left = 2
				return true
			push_warning("剧本模式 %s 未通过校验，转随机：%s"
				% [want, str(sres["errors"] + sres["warnings"])])

	# 1) 这一块属于实体段还是断桥段（见文件头的 SECTION_* 说明）
	if _section_left <= 0:
		_roll_section()
	_section_left -= 1

	if _section == SECTION_BROKEN:
		# ★ 先看这一块是不是「实心岛」（见 BROKEN_ISLAND_CHANCE）。
		#   岛**走下面的实体段路径生成**（连续路面 + 凹陷起伏 + 障碍），但**不碰 `_section`**，
		#   所以一段断桥里会夹着"能站住、有起伏、有障碍"的一小块，
		#   而不是一路"平台 + 沟"重复到底 —— 这是治"连续多次断崖这种单一形态"的正解。
		#   岛的 `broken = false` ⇒ 渲染成凹面、坑列有碰撞体，与断桥块形成对比。
		var force_island := _chasm_run >= MAX_CHASM_CHUNKS
		if not force_island and _rng.randf() >= BROKEN_ISLAND_CHANCE:
			# 长度上限：开局那一块压到 OPENING_BROKEN_COLS_MAX，连着第二块压到
			# CHASM_CHAIN_COLS_MAX（理由见那两个常量）。两者取较小值。
			# `_opening_stage == 1` = 正在生成"头两段里的第一段"（见 `_roll_section`）
			var cols_cap := -1
			if _opening_stage == 1:
				cols_cap = OPENING_BROKEN_COLS_MAX
			elif _chasm_run >= 1:
				cols_cap = CHASM_CHAIN_COLS_MAX
			var tail_lv := _tail_h[_tail_h.size() - 1] if _tail_h.size() > 0 else 0
			for i in PROC_TRIES:
				var cb := TerrainComposer.build_broken(_rng, speed, _tail_b, _tail_gap_px,
					cols_cap, tail_lv, _tail_gap_delta)
				if cb.is_empty():
					break
				var bres := _validate_merged(cb["h"], cb["b"], speed, true)
				if bres["ok"] and (not strict or bres["warnings"].is_empty()):
					_last_name = cb["name"]
					_commit(cb["name"], cb["h"], cb["b"], true)
					return true
				_note_reject("proc_brk(合成器)", bres["errors"] + bres["warnings"])
			# 断桥段连摇 8 次都过不了（现实里只在这个速度挖不出坑时发生）
			# → 立刻结束这一段，按实体段处理，而不是硬塞一块假的断桥。
			_section = SECTION_SOLID
			_section_left = 1

	# 2) 实体段：先把模式库算一遍（顺带刷新拒绝统计），再看走库还是走合成器。
	# ⚠ 只调一次 `_pick_library()` —— 它带拒绝统计的副作用，
	#   同一块里调两次会把 `reject_stats` 灌成两倍，之后调参就看不准了。
	#   ⚠ 正常断桥段**不查库**（库里的模式是"连续路面 + 障碍"，会稀释掉割裂感），
	#     但**实心岛会走到这里**（它本来就是"连续路面 + 障碍"）—— 那是刻意的。
	var lib := _pick_library(tier, speed)
	if not lib.is_empty() and _rng.randf() < LIBRARY_MIX:
		_last_name = lib["name"]
		_commit(lib["name"], lib["h"], lib["b"])
		return true

	# 主力：程序化合成。坑宽/障碍间距都按**当前速度**现算，所以不存在
	# 手写模式那种"间距写死了、速度一高就永远通不过"的死代码。
	var solid_tail_lv := _tail_h[_tail_h.size() - 1] if _tail_h.size() > 0 else 0
	for i in PROC_TRIES:
		var c := TerrainComposer.build(_rng, tier, speed, _tail_b, _tail_flat_run,
			_tail_gap_px, SOLID_FRAG_CHANCE, solid_tail_lv)
		if c.is_empty():
			continue
		var res := _validate_merged(c["h"], c["b"], speed)
		if res["ok"] and (not strict or res["warnings"].is_empty()):
			_last_name = c["name"]
			_commit(c["name"], c["h"], c["b"])
			return true
		# 合成器被拒的原因以前是**静默的** —— 它只会默默重摇 8 次然后退回模式库。
		# 于是"某个新加的规则把所有候选都拒了"这种问题只能靠猜。
		_note_reject("proc(合成器)", res["errors"] + res["warnings"])

	# 合成器连续失败 → 退回手写模式库
	if not lib.is_empty():
		_last_name = lib["name"]
		_commit(lib["name"], lib["h"], lib["b"])
		return true

	# 库也全被拒 → 退回平地，保证生成器永不死锁
	var flat := PackedInt32Array()
	var flatb := PackedInt32Array()
	for i in GameConfig.chunk_cols:
		flat.append(_tail_h[_tail_h.size() - 1] if _tail_h.size() > 0 else 0)
		flatb.append(0)
	_commit("fallback_flat", flat, flatb)
	return true


## 把候选块接到尾部上下文上，过一遍准入校验（R1~R6）。
## 手写模式库和程序化合成器**走的是同一个闸门** —— 校验器是唯一的准入标准，
## 换成合成器并不意味着可以绕过它。
func _validate_merged(h: PackedInt32Array, b: PackedInt32Array, speed: float,
		broken := false) -> Dictionary:
	return Solvability.validate(_tail_h + h, _tail_b + b, speed, _tail_h.size(), broken)


## 从手写模式库里挑一条能过的（同一条不连续用两次）。
## 返回空字典表示这一档没有能过校验的模式。
func _pick_library(tier: int, speed: float) -> Dictionary:
	var cands: Array[Dictionary] = []
	for p in _patterns:
		if int(p["tier"]) > tier:
			continue
		if p["name"] == _last_name and _patterns.size() > 1:
			continue  # 避免连续重复同一模式
		# 割裂感闸门：库里绝大多数是"连续路面 + 障碍"（flat8 / flat10 / low1 /
		# low2_wide / slide1 …），**它们不经过合成器的强制挖坑**。
		# 放行的话连续几句库模式就能拼出 60 列不断的路面（实测 brk2 那局就是），
		# 合成器那边无论怎么调都白搭。超限就跳过 → 交给合成器（它一定会挖坑）。
		if _tail_flat_run + TerrainComposer.leading_flat(p["h"]) \
				> TerrainComposer.MAX_SOLID_RUN_WITH_LIBRARY:
			continue
		var res := _validate_merged(p["h"], p["b"], speed)
		if not res["ok"]:
			_note_reject(p["name"], res["errors"])
			continue
		if strict and not res["warnings"].is_empty():
			_note_reject(p["name"], res["warnings"])
			continue
		cands.append(p)
	if cands.is_empty():
		return {}
	return cands[_rng.randi_range(0, cands.size() - 1)]


## 铺一块平坦无障碍的地面（测试模式专用）
func _commit_flat() -> void:
	var h := PackedInt32Array()
	var b := PackedInt32Array()
	for i in GameConfig.chunk_cols:
		h.append(0)
		b.append(0)
	_commit("test_flat", h, b)


## 决定接下来的这一段是实体段还是断桥段，并抽好它持续几块。
## 只在 `_section_left` 用完时调用（见 `_append_chunk` 第 1 步）。
func _roll_section() -> void:
	# ---- 开局配额：头两段一实体一断桥、各自都短（见 OPENING_CHUNKS_MAX）----
	if _opening_stage < 2:
		var want_broken := _opening_start_broken if _opening_stage == 0 			else not _opening_start_broken
		_opening_stage += 1
		_section = SECTION_BROKEN if want_broken else SECTION_SOLID
		# ⚠ 不乘性格倍率、也不套 1~6 的段长范围 —— 开局要的是"两种形态都能很快看到"
		_section_left = _rng.randi_range(1, OPENING_CHUNKS_MAX)
		return

	var mix: Array = PERSONA_MIX[_persona]
	if _section != SECTION_SOLID:
		# 断桥段之后**必然**回到实体段：连着两段断桥等于连着四五块不放障碍，
		# 障碍密度和难度都会塌一个台阶。
		_section = SECTION_SOLID
		_section_left = _persona_chunks(SOLID_CHUNKS_MIN, SOLID_CHUNKS_MAX, 0)
		return
	if _rng.randf() < float(mix[2]):
		_section = SECTION_BROKEN
		_section_left = _persona_chunks(BROKEN_CHUNKS_MIN, BROKEN_CHUNKS_MAX, 1)
	else:
		# 继续实体段（不换段）
		_section_left = _persona_chunks(SOLID_CHUNKS_MIN, SOLID_CHUNKS_MAX, 0)


## 按当前「地形性格」抽这一段持续几块。`which`：0 = 实体段、1 = 断桥段。
##
## ⚠ **上下限分开**（实体 5 / 断桥 4）：断桥段整段都是"平台 + 沟"，
##   段太长就变成"同一种东西重复好几屏" —— 实测「重断桥」性格 ×1.7 时
##   最长能开出 **5 块连续断崖（193 列 ≈ 3 个屏幕）**，那正是用户报的"单一形态"。
func _persona_chunks(lo: int, hi: int, which: int) -> int:
	var mult := float(PERSONA_MIX[_persona][which])
	var cap := SOLID_CHUNKS_CAP if which == 0 else BROKEN_CHUNKS_CAP
	return clampi(int(round(float(_rng.randi_range(lo, hi)) * mult)), 1, cap)


## broken：本块是否属于**断桥段**。它决定 `TerrainChunk` 用哪套画法/碰撞
## （断桥段 = 无底深沟 + 坑列无碰撞体；实体段 = 凹面起伏 + 坑列保留碰撞体）。
## ⚠ 用显式参数而不是解析 `name` 前缀（`proc_brk*`）：名字是给人看的调试信息，
##   让渲染逻辑依赖字符串前缀，改个命名就会静默改变玩法。
func _commit(name: String, h: PackedInt32Array, b: PackedInt32Array,
		broken := false) -> void:
	if not usage_stats.has(name):
		usage_stats[name] = 0
	usage_stats[name] += 1

	if dump_terrain:
		var hs := ""
		for v in h:
			if v == -1:
				hs += "a"
			elif v <= -2:
				hs += "b"
			else:
				hs += str(v)
		var bs := ""
		for v in b:
			bs += "." if v == 0 else ("^" if v == TerrainPatterns.LOW else "v")
		print("[terrain-dump] col%-4d %-14s h=%s b=%s" % [_next_col, name, hs, bs])

	var chunk := TerrainChunk.new()
	chunk.name = "Chunk_%d_%s" % [_next_col, name]
	add_child(chunk)
	chunk.setup(h, b, _next_col, broken)
	_chunks.append(chunk)

	# 保留尾部若干列作为下一块的接缝上下文
	var keep := mini(8, h.size())
	_tail_h = h.slice(h.size() - keep, h.size())
	_tail_b = b.slice(b.size() - keep, b.size())

	# ⚠ 下面三个计数都集中在这里维护（连续平地 / 最后一个坑宽 / 连续断崖块数）：
	#   生成分支太多了（库 / 合成器 / 剧本 / 兜底 / 实心岛），散在各个分支里漏一处，
	#   对应的硬上限（`MAX_SOLID_RUN`、落点兜底、`MAX_CHASM_CHUNKS`）就会**静默失效**。
	#   而"静默失效"正是这套地形规则里最难查的一类问题。
	_chasm_run = _chasm_run + 1 if broken else 0

	# 连续平地长度：本块**一个坑都没有**就接着上一块累加，否则从本块最后一个坑之后重新数。
	# 这正是"地面这条线还没断"的长度，交给合成器当 `MAX_SOLID_RUN` 的起点。
	var tf := 0
	for i in range(h.size() - 1, -1, -1):
		if h[i] > 0:
			break
		tf += 1
	_tail_flat_run = (_tail_flat_run + h.size()) if tf == h.size() else tf

	# 本块最后一个坑的宽度与起落差：先跳过尾部台面（<= 0），再数坑列（> 0）。
	var tg := 0
	var td := 0
	var i2 := h.size() - 1
	while i2 >= 0 and h[i2] <= 0:
		i2 -= 1
	if i2 >= 0:
		var e2 := i2
		while i2 >= 0 and h[i2] > 0:
			i2 -= 1
		tg = (e2 - i2) * GameConfig.TILE
		var h_from := h[i2] if i2 >= 0 else 0
		var h_to := h[e2 + 1] if e2 + 1 < h.size() else 0
		td = h_to - h_from
	_tail_gap_px = tg
	_tail_gap_delta = td

	_next_col += h.size()


func _note_reject(name: String, reasons: Array) -> void:
	if not reject_stats.has(name):
		reject_stats[name] = 0
	# 记下第一个拒绝原因。只看次数无法分辨"地形真的不合规"和"校验器误报"——
	# 例如无任何障碍的平坦模式也被拒，那一定是误报。
	if not reject_reasons.has(name):
		reject_reasons[name] = str(reasons[0]) if reasons.size() > 0 else "?"
	reject_stats[name] += 1
