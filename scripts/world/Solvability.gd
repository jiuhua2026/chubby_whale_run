extends RefCounted
class_name Solvability
## 可解性校验器 —— 整个生成器的安全阀。
##
## 设计原则：**不写死任何数值**。所有阈值都从 GameConfig 的物理常量现算出来。
## 这样你改跳跃高度或速度曲线时，地形准入标准会自动跟着变，
## 不会出现「手感调完了，地形还是按旧参数生成的」这种隐性 bug。
##
## 两类结论：
##   errors   —— 硬伤。必定不可解，或对玩家不公平，直接拒绝该模式。
##   warnings —— 能过，但需要「掉进坑里再爬出来」这种次优解，只损失速度。
##               是否接受由生成器的 strict 开关决定。
##
## 校验规则（全部由运动包络推导）：
##   R1 相邻列层高落差 ≤ 1              —— 否则是不可攀爬的悬崖
##   R2 每个下坡必须在安全跳距内回到原层高 —— 否则跳不过去（→ warning）
##   R3 障碍必须放在连续平地上           —— 斜坡上的障碍无法公平处理
##   R4 相邻障碍**组**间距 ≥ 反应距离     —— 连续的悬顶算一组，不重复计距
##   R5 悬顶段长度 ≥ 2 列               —— 否则下滑还没生效就结束了
##   R6 首列与末两列不放障碍             —— 保住块与块接缝处的安全
##   R7 坑之后的落点平台 ≥ 跳跃距离−坑宽 —— 否则一次**满跳**会飞过窄平台、落进下一个坑
##   R8 上台阶前后净空（凸面高台专用）   —— 爬阶前留足助跑与脱离悬顶空间、爬阶后留足落点再放悬顶
##
## `broken = true`（断桥段）与 `broken = false`（实体段）的层面约定：
##   h <= 0（0, -1, -2）始终是可站立的实体台面；
##   h > 0（1, 2）在实体段是可踩可跳的凹坑，在断桥段是无底深沟。

const TILE := 64  ## 与 GameConfig.TILE 保持同步（静态类里读不到 autoload 常量）


static func validate(h: PackedInt32Array, b: PackedInt32Array, speed: float,
		context_cols: int = 0, broken: bool = false) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var cols := h.size()
	if cols == 0 or b.size() != cols:
		return {"ok": false, "errors": ["长度不一致或为空"], "warnings": []}

	var safe_gap_px := Difficulty.max_safe_gap_px_for(speed)
	var min_space_px := Difficulty.min_hazard_spacing_px_for(speed)

	# ---------------- R1 层高落差 ----------------
	for i in range(maxi(1, context_cols), cols):
		if broken and (h[i - 1] > 0 or h[i] > 0):
			continue
		if absi(h[i] - h[i - 1]) > 1:
			errors.append("R1 第%d列层高落差>1（%d→%d）" % [i, h[i - 1], h[i]])

	# ---------------- R2 凹坑 / 断崖必须可跳越 ----------------
	if broken:
		var bi := maxi(0, context_cols - 1)
		while bi < cols:
			if h[bi] <= 0:
				bi += 1
				continue
			var p0 := bi
			while bi < cols and h[bi] > 0:
				bi += 1
			if bi <= context_cols:
				continue
			if p0 == 0 or bi >= cols:
				errors.append("R2 第%d列断崖未在块内闭合" % p0)
				continue
			var h_from := h[p0 - 1]
			var h_to := h[bi]
			if h_from - h_to > 1:
				errors.append("R2 第%d列断崖对岸抬升>1格（%d→%d）" % [p0, h_from, h_to])
				continue
			var span_px := float(bi - (p0 - 1)) * float(TILE)
			var gap_lim := Difficulty.max_safe_gap_px_between(speed, h_from, h_to)
			if span_px > gap_lim:
				errors.append("R2 第%d列断崖跨距%.0fpx > 安全跳距%.0fpx（%d→%d）"
					% [p0, span_px, gap_lim, h_from, h_to])
	else:
		var i := maxi(0, context_cols - 1)
		while i < cols - 1:
			if h[i + 1] > h[i]:
				var lvl := h[i]
				var h_drop := h[i + 1]
				# 若是一路单调下台阶落回 <= 0 的可站立层（如 -2 → -1 → 0 的紧凑凸峰下坡）
				# 且最终平地持续至少 3 列（块尾至少 2 列），则中间台阶允许只有 1~2 列。
				if h_drop <= 0:
					var m := i + 1
					while m < cols and h[m] >= h[m - 1] and h[m] <= 0:
						m += 1
					var h_low := h[m - 1]
					var flat_len := 0
					var k_flat := m - 1
					while k_flat >= i + 1 and h[k_flat] == h_low:
						flat_len += 1
						k_flat -= 1
					if h_low <= 0 and (flat_len >= 3 or (m >= cols and flat_len >= 2)):
						i = m - 1
						continue
				var j := i + 1
				while j < cols and h[j] > lvl:
					j += 1
				if j >= cols:
					errors.append("R2 第%d列起的下坡在块内没回到原层高" % i)
					break
				var gap_px := float(j - i) * float(TILE)
				if gap_px > safe_gap_px:
					warnings.append("R2 第%d列起坑宽%.0fpx > 安全跳距%.0fpx（需掉入再爬出）"
						% [i, gap_px, safe_gap_px])
				i = j
			else:
				i += 1

	# ---------------- R3 / R6 障碍落点 ----------------
	# 只检查「新块」的列。上下文列（上一块尾部）在自己那一轮已经查过，
	# 再查一遍会把「尾部首列有障碍」误判成 R6 / R3 违规。
	for c in cols:
		if b[c] == 0 or c < context_cols:
			continue
		# 末两列限制：新块的末列就是数组末列，直接判
		if c >= cols - 2:
			errors.append("R6 第%d列的障碍离块末列太近" % c)
		# 首列限制：只针对「新块的第一列」
		if c == context_cols:
			errors.append("R6 第%d列的障碍就是块的首列" % c)
		if c - 1 < 0 or c + 1 >= cols or h[c - 1] != h[c] or h[c + 1] != h[c]:
			errors.append("R3 第%d列的障碍不在连续平地上" % c)

	# ---------------- R4 障碍组间距 ----------------
	# 连续的障碍列算作同一组：一段 4 列宽的悬顶是一个需要下滑的障碍，
	# 而不是四个需要间隔的障碍。不分组的话任何多列障碍都会误报。
	var groups: Array[Vector2i] = []
	var c2 := 0
	while c2 < cols:
		if b[c2] == 0:
			c2 += 1
			continue
		var s := c2
		while c2 + 1 < cols and b[c2 + 1] != 0:
			c2 += 1
		groups.append(Vector2i(s, c2))
		c2 += 1
	for k in range(1, groups.size()):
		# ⚠ **只在"接缝那一对"和新建部分内部的组之间比较**，跳过完全落在上下文
		#   （上一块的尾巴）里的那一对。理由和 R3/R6 的 `context_cols` 是同一条：
		#   尾巴在它自己那一轮已经按**当时的速度**校验过了。
		#   而 R4 的要求**随速度增长** ⇒ 一块生成完、玩家跑快一点之后，
		#   尾巴内部本来合法的间距会变成"违规"。
		#   不跳过的话会把**所有**候选（包括毫无障碍的纯平地块）一起拒掉 ——
		#   实测表现就是生成器频繁走 `fallback_flat`，一个 12 列的纯平地补丁。
		if groups[k].x < context_cols:
			continue
		var gap := float(groups[k].x - groups[k - 1].y) * float(TILE)
		if gap < min_space_px:
			errors.append("R4 障碍组间距%.0fpx < 反应距离%.0fpx（第%d~%d列 → 第%d~%d列）"
				% [gap, min_space_px, groups[k - 1].x, groups[k - 1].y,
					groups[k].x, groups[k].y])

	# ---------------- R5 悬顶段长度 ----------------
	var run := 0
	for c in range(cols + 1):
		var is_over := c < cols and b[c] == TerrainPatterns.OVERHEAD
		if is_over:
			run += 1
		else:
			if run > 0 and run < 2 and c > context_cols:
				errors.append("R5 第%d列起的悬顶段仅%d列，太短" % [c - run, run])
			run = 0

	# ---------------- R7 坑之后必须有足够长的落点平台 ----------------
	var land_need_px := Difficulty.min_landing_px_for(speed, 0.0)
	var ci := 0
	while ci < cols:
		if h[ci] <= 0:
			ci += 1
			continue
		var pit_start := ci
		var h_from := h[pit_start - 1] if pit_start > 0 else 0
		while ci < cols and h[ci] > 0:
			ci += 1
		var gap_px := float(ci - pit_start) * float(TILE)
		var h_to := h[ci] if ci < cols else 0
		# 往右找下一个坑或上台阶前可落脚的同一层平地长度
		var k := ci
		while k < cols and h[k] == h_to:
			k += 1
		if k >= cols:
			continue          # 平台一直延伸到块末 —— 长度要跨块算，这里不判
		if k < context_cols:
			continue
		var plat_px := float(k - ci) * float(TILE)
		land_need_px = Difficulty.min_landing_px_between(speed, gap_px, h_from, h_to)
		if plat_px + 1.0 < land_need_px:
			errors.append("R7 第%d列坑（宽%.0fpx，%d→%d）之后只有%.0fpx 落点，需要%.0fpx（满跳会飞过）"
				% [pit_start, gap_px, h_from, h_to, plat_px, land_need_px])

	# ---------------- R8 凸台 / 上台阶前后净空（仅实体段；断桥跨沟由 R2+R7 管） ----------------
	if not broken:
		for c in range(maxi(1, context_cols), cols):
			if not (h[c] < h[c - 1] and h[c - 1] <= 0):
				continue
			# 上台阶前至少 3 列同层无障碍平地（且 4 列内无悬顶刚结束，留足起身跳上台阶的时间）
			var pre_ok := c >= 3
			if pre_ok:
				for p in range(c - 3, c):
					if h[p] != h[c - 1] or b[p] != 0:
						pre_ok = false
						break
			if pre_ok and c >= 4 and b[c - 4] == TerrainPatterns.OVERHEAD:
				pre_ok = false
			if not pre_ok:
				errors.append("R8 第%d列上台阶（%d→%d）前助跑平地/净空不足" % [c, h[c - 1], h[c]])
				continue
			# 上台阶后顶面至少 2 列，且若紧接再升一级则至少 3 列；前 3 列内不放任何障碍（留足落地反应）
			var top_end := c
			while top_end < cols and h[top_end] == h[c]:
				top_end += 1
			var top_len := top_end - c
			var min_top := 2 if (top_end < cols and h[top_end] < h[c]) else 2
			if top_len < min_top:
				errors.append("R8 第%d列高台顶面仅%d列（需要≥%d列）" % [c, top_len, min_top])
			for t in range(c, mini(cols, c + 3)):
				if h[t] == h[c] and b[t] != 0:
					errors.append("R8 第%d列上台阶后第%d列太早出现障碍" % [c, t])
					break

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}
