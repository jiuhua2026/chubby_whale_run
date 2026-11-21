extends RefCounted
class_name TerrainPatterns
## 地形模式库。
##
## 作者格式（便于手写和 review）：
##   h_str —— 每列的地面层高，单字符：'0' 基准平地 / '1','2' 往下凹 / 'a'(-1),'b'(-2) 往上凸起的高台。
##   b_str —— 每列的障碍：'.' 无 / '^' 低障碍（必须跳）/ 'v' 悬顶障碍（必须滑）
##
## 重要：这里写的模式**不保证都能用**。准入由 Solvability 按当前速度现算，
## 不通过的模式会被静默跳过。所以可以放心往库里塞激进地形，
## 高速阶段它们自然出现，低速阶段自动被筛掉。
##
## 手算校验过的不变量（改模式时必须重新核对）：
##   · 相邻列层高差 ≤ 1
##   · 每个坑的「两端列距」× TILE ≤ 当前速度下的安全跳距
##   · 障碍必须落在连续平地上，且不在首列 / 末两列
##   · 相邻障碍组间距 ≥ 0.55 秒反应距离
##   · 悬顶段长度 ≥ 2 列

const LOW := 1        ## '^' 低障碍：跳过去
const OVERHEAD := 2   ## 'v' 悬顶：滑过去


static func _make(name: String, tier: int, h_str: String, b_str: String) -> Dictionary:
	if h_str.length() != b_str.length():
		push_error("地形模式 %s 的 h/b 长度不一致（%d vs %d），已跳过"
			% [name, h_str.length(), b_str.length()])
		return {}
	var h := PackedInt32Array()
	var b := PackedInt32Array()
	for i in h_str.length():
		var ch := h_str[i]
		match ch:
			'a', 'A':
				h.append(-1)
			'b', 'B':
				h.append(-2)
			_:
				h.append(int(ch))
	for i in b_str.length():
		match b_str[i]:
			'^':
				b.append(LOW)
			'v':
				b.append(OVERHEAD)
			_:
				b.append(0)
	return {"name": name, "tier": tier, "h": h, "b": b, "cols": h_str.length()}


static func all() -> Array[Dictionary]:
	var P: Array[Dictionary] = []
	var raw := _raw()
	for r: Array in raw:
		var p := _make(str(r[0]), int(r[1]), str(r[2]), str(r[3]))
		if not p.is_empty():
			P.append(p)
	return P


## [名称, 最低难度档, h_str, b_str]
##
## ⚠ **障碍间距必须按满速（655px/s）算，不能用起步速度手算。**
##   R4 要求组间距 ≥ `max(速度×0.55, 跳距×1.15)`，满速时 = **538px ≈ 8.4 列**，
##   而模式是**定长**的 —— 间距写死多少就是多少，速度一涨就再也过不了校验。
##   2026-09-28 实测：`low2_wide` / `low_then_slide` / `low_slide_low` / `dense_combo`
##   四条**一次都没被用过**，首次拒绝原因全是「R4 障碍组间距 384px < 反应距离 391px」
##   —— `low2_wide` 只差 **2px**。已把这几条的间距统一拉到 **≥10 列（640px）**。
##   （定长模式天然有这个毛病，所以现在主力是 `TerrainComposer` 现算间距，
##     见 TerrainGenerator.LIBRARY_MIX 的注释。）
static func _raw() -> Array:
	return [
		# ---------- tier 0：纯平地，起步与安全缓冲 ----------
		["flat8",           0, "00000000",         "........"],
		["flat10",          0, "0000000000",       ".........."],
		["low1",            0, "0000000000",       ".....^...."],
		# 两组矮障碍，间距 10 列（640px）—— 起步速度下也过得了
		["low2_wide",       0, "000000000000000",  "..^.........^.."],
		["mesa_plain",      0, "000aaaaa000",      "..........."],

		# ---------- tier 1：单个新机制，彼此不叠加 ----------
		["slide1",          1, "0000000000",       "....vv...."],
		["slide1_long",     1, "000000000000",     "....vvvv...."],
		["step_up1",        1, "0000011000",       ".........."],
		["step_down1",      1, "0110000000",       ".........."],
		["low_then_slide",  1, "000000000000000000", "..^.........vv...."],
		["valley3",         1, "000121000",        "........."],
		["mesa_low",        1, "00000aaaaaaa0000", "........^......."],
		["mesa_slide",      1, "00000aaaaaaaaa0000", "........vvv......."],
		["ridge_step",      1, "0000aabbbba0000",  "..............."],

		# ---------- tier 2：坑 + 组合 ----------
		# 层高方向记牢：0 是基准层，正数往下凹，'a'(-1)/'b'(-2) 往上凸。
		["valley4_low",     2, "0001221000000",    "..........^.."],
		["trench4",         2, "00011000",         "........"],
		["mesa_and_dip",    2, "0000aaaaaaa0000001210000", ".......^................"],
		["mound_wave",      2, "0000aabbbba00012210000", "......................"],
		["low_slide_low",   2, "000000000000000000000000000",
			"..^.........vv..........^.."],

		# ---------- tier 3：大坑与高密度组合（速度上去后才会被准入） ----------
		["valley4",         3, "0001221000",       ".........."],
		["valley_pair",     3, "0001210000121000", "........^......."],
		["dense_combo",     3, "0000000000000000000000000000",
			"..^.........vvv..........^.."],
		["steps_and_slide", 3, "000001100000",     "..vv........"],
		# 长距离间隔版：障碍组间距 10 列（640px），满足高速阶段
		# 「至少一次完整跳跃距离」的准入要求（655px/s 时需要 538px）
		["long_gauntlet",   3, "00000000000000000000000000", "..^.........vv.........^.."],
	]
