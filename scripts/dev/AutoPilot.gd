extends RefCounted
class_name AutoPilot
## 无头自检用的自动驾驶。
##
## 它不是游戏的一部分，而是一个**可解性证明器**：
##   规则式校验器（Solvability）只能保证「单条规则不被违反」，
##   但规则之间的组合仍可能产出实际过不去的地形（例如：一个矮障碍紧接一个坑，
##   各自合法、合起来无处起跳）。
##   让一个只会按「上 / 下 / 空格」三个键的驱动器真实跑过去，是唯一能证明"可解"的办法。
##
## 关键实现细节：它通过 Input.action_press / action_release 注入输入，
## 而不是直接改 Player 的状态。这样走的是和真人完全相同的输入路径，
## 连土狼时间、输入缓冲、可变跳跃高度都会被真实检验。

## 起跳提前量的比例系数（相对「到最高点所需的水平距离」）。
## 关键：**提前量必须随速度变化**。到最高点的时间是定值 rise_time，
## 所以高速时最佳的起跳点会明显外移——用固定值会在高速阶段跳晚。
##
## 窗口的上下界是这样算出来的（以 470px/s、1 格高障碍为例）：
##   玩家碰撞盒宽 44、障碍宽 64，所以玩家必须「feet 高于 64px」的横向区间是
##   [障碍左缘-22, 障碍右缘+22] = 108px。
##   全程跳跃下 feet>64px 的区间约 235px（t∈[0.089s, 0.589s]）。
##   把 235px 的窗口套住 108px 的目标区间，解出提前量 ∈ [64, 149]px
##   = apex_dist(170) 的 [0.38, 0.88]。实测 215px 就太早，落点正好扎在障碍尾缘。
const LEAD_LOW_RATIO_MIN := 0.32
const LEAD_LOW_RATIO_MAX := 0.82
## 坑：要尽量在坑边缘起跳，否则会在坑里落地
const LEAD_PIT_RATIO_MIN := 0.06
const LEAD_PIT_RATIO_MAX := 0.45
## 下滑提前量（px）
const SLIDE_LEAD := 260.0
## 通过悬顶后还要多滑一段，直到身体后半截彻底离开悬顶下方。
## 玩家碰撞盒宽 44，所以中心越过悬顶右缘后，后缘还可能在悬顶下方约 22px；
## 不留这段余量的话，一松手站起来就会撞头。
const SLIDE_TAIL := 70.0
## 一次跳跃的按键保持时间。
## 必须**超过上升段时长**（|jump_velocity|/gravity ≈ 0.362s），
## 否则会触发可变跳跃高度削减（jump_cut_mult），跳跃距离缩短约 10%，
## 落点会提前扎进障碍——这正是第一版自动巡航每次跳都撞的原因。
const JUMP_HOLD := 0.46

var enabled := false

var _player: Player
var _gen: TerrainGenerator
var _jump_hold := 0.0
var _sliding := false
## 下滑要保持到的世界 x。用「目标 x」而不是布尔标志，
## 才能正确处理"身体后缘还没离开悬顶"这段尾巴。
var _slide_until_x := -1.0
## 统计：被撞了几次。用于评估生成器与驱动器的配合质量
var hits := 0
var jumps := 0
var slides := 0
var dashes := 0
## 掉进断崖的次数。
##
## ⚠ **这是一个长期缺失的度量**（2026-09-28 断崖改版时补）：`--solvable` 会掐掉一切死亡判定，
## 所以"掉进坑里"**不会导致任何失败**，`hits` 也数不到它 —— 指标里完全看不见。
## 它只在正常模式暴露，而那时已经变成死亡结算，分不清是地形变难还是驱动器的锅。
##
## **由 `Main` 检测到坠落时调 `note_chasm_fall()` 累加**，自动驾驶本身不判定 ——
## 因为断崖现在（2026-09-28 晚起）是**真的洞**：坑列没有碰撞体，玩家会一直往下掉，
## 所以"踩在坑底"这个旧判据已经不存在了。
var pit_falls := 0
## 冲刺键的"按住"剩余时间。
## dash 是用 is_action_just_pressed 读的，所以要模拟一次真实的按下→松开，
## 不能一直按着（一直按着只会触发第一次 just_pressed）。
var _dash_hold := 0.0


func setup(player: Player, gen: TerrainGenerator) -> void:
	_player = player
	_gen = gen
	player.hit_taken.connect(_on_hit)


## 撞击瞬间的上下文快照。自动驾驶本身是个粗糙的启发式驱动器，
## 它撞了不等于地形不可解；但撞击时的上下文能告诉我们**是驱动器的问题
## 还是地形的问题**——这是它作为验证工具的核心价值。
var _ctx := {}
## 最近若干帧的决策快照，撞击时一次性倒出来。
## 启发式驱动器撞了不代表地形不可解，但有了逐帧回放就能判断
## 到底是"驱动器判断错了"还是"地形规则漏了组合情况"。
var _ring: Array[String] = []
const RING := 40


func _on_hit(kind: String) -> void:
	hits += 1
	if hits <= 3:
		print("[autopilot] ===== 撞击#%d kind=%s 前的 %d 帧 =====" % [hits, kind, RING])
		for line in _ring:
			print("  " + line)
		print("[autopilot] ===== 回放结束 =====")


func reset() -> void:
	_jump_hold = 0.0
	_sliding = false
	_slide_until_x = -1.0
	hits = 0
	jumps = 0
	slides = 0
	dashes = 0
	pit_falls = 0
	_dash_hold = 0.0
	Input.action_release("jump")
	Input.action_release("slide")
	Input.action_release("dash")


func tick(delta: float) -> void:
	if not enabled or _player == null or not GameState.is_running():
		return

	_scan_and_act(delta)


## 记一次坠崖。由 `Main` 在「玩家掉出世界」时调用（见 Main 的 `FALL_KILL_DEPTH`）——
## 判定放在 Main 是因为它同时握有玩家、地形与模式（可解性模式下要救人而不是判死）。
func note_chasm_fall() -> void:
	pit_falls += 1


## 最近 n 帧的上下文快照（由后往前）。诊断"这一次是怎么死的"用 ——
## 和撞击回放同一套数据，只是调用点不同（见 `Main._dump_fall_context`）。
func recent(n: int) -> Array:
	var out: Array = []
	for i in range(_ring.size() - 1, maxi(-1, _ring.size() - 1 - n), -1):
		out.append(_ring[i])
	return out


func _scan_and_act(delta: float) -> void:
	var px := _player.global_position.x
	var speed := maxf(_player.speed, 1.0)

	var jump_dist := GameConfig.jump_distance(speed)
	# 起跳到最高点所需的水平距离：与速度成正比，所以提前量也要跟着变
	var apex_dist := speed * (absf(GameConfig.jump_velocity) / GameConfig.gravity)
	var lead_low_lo := apex_dist * LEAD_LOW_RATIO_MIN
	var lead_low_hi := apex_dist * LEAD_LOW_RATIO_MAX
	var lead_pit_lo := 20.0
	var lead_pit_hi := jump_dist * LEAD_PIT_RATIO_MAX
	var lead_step_hi := speed * 0.34

	var span_px := jump_dist + 260.0
	var span_cols := int(ceil(span_px / float(GameConfig.TILE))) + 2

	# 往回多取两列：悬顶的判定必须能看到"刚过去"的那一列，
	# 否则玩家中心一越过悬顶就会松开下滑键。
	var cols := _gen.sample(px - float(GameConfig.TILE) * 2.0, span_cols + 2)
	var jump_now := false
	var step_ahead_x := INF
	var dbg_low := -1.0
	var dbg_over := -1.0
	var dbg_step := -1.0
	var dbg_pit := -1.0

	for i in cols.size():
		var c: Dictionary = cols[i]
		var cx := float(int(c["col"])) * float(GameConfig.TILE)
		var d := cx - px

		var lv := int(c["level"])
		if lv <= TerrainGenerator.LEVEL_UNLOADED:
			break  # 还没生成到，停止扫描

		var hazard := int(c["hazard"])
		var prev: Dictionary = cols[i - 1] if i > 0 else c
		var plv := int(prev["level"])
		if plv <= TerrainGenerator.LEVEL_UNLOADED:
			plv = lv

		if d > 0.0 and lv < plv and plv <= 0 and cx < step_ahead_x:
			step_ahead_x = cx

		# 悬顶：这是唯一需要看「身后」的判定——必须滑到身体后缘也离开为止；
		# 若身前正要跳上高台（cx >= step_ahead_x），先完成跳台再下滑
		if hazard == TerrainPatterns.OVERHEAD and d <= SLIDE_LEAD and cx < step_ahead_x:
			_slide_until_x = maxf(_slide_until_x,
				cx + float(GameConfig.TILE) + SLIDE_TAIL)
			if dbg_over < 0.0:
				dbg_over = d

		if d < 0.0:
			continue  # 以下都是"前方"判定，身后的列不参与

		# 低障碍：进入「到最高点的距离」窗口就跳
		if hazard == TerrainPatterns.LOW:
			if dbg_low < 0.0:
				dbg_low = d
			if d >= lead_low_lo and d <= lead_low_hi:
				jump_now = true

		# 上台阶（层高变小 = 更高）：凸台上升与走出凹坑都需要在助跑窗口内起跳，避免撞壁卡住
		if lv < plv:
			if dbg_step < 0.0:
				dbg_step = d
			if d >= 4.0 and d <= lead_step_hi:
				jump_now = true

		# 坑（进入 > 0 的凹坑/断崖）：在坑边缘起跳；若只是从凸台安全下阶梯（lv <= 0）则自然下落
		if lv > plv and lv > 0:
			if dbg_pit < 0.0:
				dbg_pit = d
			if d >= lead_pit_lo and d <= lead_pit_hi:
				jump_now = true

	var slide_now := px < _slide_until_x

	_ctx = {
		"低障碍": "%.0f" % dbg_low, "悬顶": "%.0f" % dbg_over,
		"上台阶": "%.0f" % dbg_step, "坑": "%.0f" % dbg_pit,
		"窗口": "%.0f~%.0f" % [lead_low_lo, lead_low_hi],
	}
	_ring.append("x=%.0f y=%.0f 地板=%s 跳键=%s 跳保持=%.2f 滑键=%s 滑到=%.0f 玩家滑=%s 速度=%.0f | 低=%.0f 顶=%.0f 阶=%.0f 坑=%.0f | 扫描=%s"
		% [px, _player.global_position.y, "是" if _player.is_on_floor() else "否",
			"是" if _jump_hold > 0.0 else "否", _jump_hold,
			"是" if _sliding else "否", _slide_until_x,
			"是" if _player.is_sliding() else "否", _player.speed,
			dbg_low, dbg_over, dbg_step, dbg_pit, str(cols.slice(0, 6))])
	if _ring.size() > RING:
		_ring.pop_front()

	# ---- 下滑输入 ----
	if slide_now and not _sliding:
		Input.action_press("slide")
		_sliding = true
		slides += 1
	elif not slide_now and _sliding:
		# 悬顶走过去之后再松开；Player 自己还有最短持续时间兜底
		Input.action_release("slide")
		_sliding = false

	# ---- 跳跃输入（按住一段时间拿全高，然后松开以获得可变跳跃高度） ----
	if _jump_hold > 0.0:
		_jump_hold -= delta
		if _jump_hold <= 0.0:
			Input.action_release("jump")
	elif jump_now and _player.is_on_floor():
		Input.action_press("jump")
		_jump_hold = JUMP_HOLD
		jumps += 1

	# ---- 冲刺输入：势能满就放 ----
	# 真人攒满也会放（放着不用没有意义），所以驱动器这么干是合理的近似。
	# 它同时让自检**覆盖到冲刺分支**，并顺带验证"冲刺不会破坏地形可解性"。
	if _dash_hold > 0.0:
		_dash_hold -= delta
		if _dash_hold <= 0.0:
			Input.action_release("dash")
	elif _player.dash_charge >= GameConfig.dash_charge_max \
			and not _player.is_dashing():
		Input.action_press("dash")
		_dash_hold = 0.05
		dashes += 1


func report() -> String:
	var fmt := "自动驾驶：跳 %d / 滑 %d / 冲 %d / 被撞 %d / 掉坑 %d"
	return fmt % [jumps, slides, dashes, hits, pit_falls]
