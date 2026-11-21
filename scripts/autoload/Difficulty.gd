extends Node
## Difficulty —— 难度曲线与「安全余量」的唯一出口。
##
## 设计要点：本作的难度**不来自**速度本身（速度只会让反应窗口变窄），
## 而是来自「地形密度」和「追逐间距」。所以这里只输出两条曲线：
##   1. 玩家的目标速度
##   2. 死亡边界的基础速度
## 地形的难度分级（pattern 的 tier）由 TerrainPatterns 负责。

## 当前已跑距离（px），由 Main 每帧写入
var distance := 0.0
## 速度覆盖。>0 时完全接管玩家目标速度，难度曲线不再生效。
## 测试模式用它把速度固定住（还能调到很低做慢放），方便反复观察动作。
## -1 表示不覆盖。
var speed_override := -1.0


func reset() -> void:
	distance = 0.0


func current_tier() -> int:
	## 0 / 1 / 2 / 3 四档，用来筛选地形模式库
	@warning_ignore("integer_division")
	var t := int(distance / 6000.0)
	return clampi(t, 0, 3)


## 玩家在当前距离下的目标速度
func player_target_speed() -> float:
	if speed_override > 0.0:
		return speed_override
	return GameConfig.run_speed_start + minf(
		distance * GameConfig.run_speed_gain, GameConfig.run_speed_bonus_max)


## 死亡边界在当前距离下的基础速度（不含橡皮筋追赶项）
func wall_base_speed() -> float:
	return GameConfig.wall_speed_base + minf(
		distance * GameConfig.wall_speed_gain, GameConfig.wall_speed_bonus_max)


## 死亡边界的实际速度：基础速度 + 橡皮筋追赶。
## gap 越大追得越快，最终会稳定在玩家速度附近的一个平衡间距上。
func wall_speed(gap: float) -> float:
	var catchup := clampf(gap - GameConfig.wall_comfort_gap, 0.0, 700.0) \
		* GameConfig.wall_catchup_k
	return wall_base_speed() + catchup


## 平衡间距（用于调参时心算）：玩家速度与该边界速度相等时的 gap
func equilibrium_gap() -> float:
	var k := GameConfig.wall_catchup_k
	if k <= 0.0:
		return GameConfig.wall_comfort_gap
	return GameConfig.wall_comfort_gap \
		+ (player_target_speed() - wall_base_speed()) / k


# ---------------------------------------------------------------- 地形安全余量
## ⚠ 这三个函数是**地形准入的唯一事实来源**：`Solvability`（校验器）和
## `TerrainComposer`（程序化合成器）都必须调这里，不许各自重写公式。
## 历史上它们是各写一份的 —— 两份一旦漂移，就会出现"校验器认为合法、
## 合成器按另一套数字生成"这种不会报错的错位。
##
## 全部提供 `_for(speed)` 版本：生成器在**当前**速度下现算，所以调手感参数时
## 地形标准会自动跟着变（见 Solvability 文件头的设计原则）。

## 指定速度下允许的**最大坑跨距**（px）。这是"沟能挖多宽"的唯一闸门：
## `Solvability` 的 R2 和 `TerrainComposer` 的挖沟逻辑都读它。
##
## ## 为什么是 0.83（2026-09-28 晚从 0.72 放宽）
## 判据要落到**玩家实际需要的水平位移**上，而不是拍一个比例：
##
##   需要的位移 = 坑的可见宽度 + 玩家碰撞盒宽(44)
##              （起跳点只能贴着坑沿、落点也必须容得下整个身体）
##   可用的位移 = 一次完整跳跃的水平覆盖 = `GameConfig.jump_distance(speed)`
##
## 而 R2 量的是「从一个 0 到下一个 0」的**跨距**，它比可见坑宽**多算一列 0**：
##   跨距 = 可见坑宽 + 一列 = 可见坑宽 + 64 > 可见坑宽 + 44
## 所以 R2 的跨距本身就把玩家宽度盖进去了，两者可以直接比。
##
##   余量 = `jump_distance × K − 跨距`。取 K = 0.83：
##     最低速 470px/s：跨距上限 3 列(192px) → 需要 236px，可用 340px，**余量 104px（31%）**
##     最高速 655px/s：跨距上限 6 列(384px) → 需要 428px，可用 474px，**余量 46px（10%）**
##
## ⚠ **最高速那一档只剩 24% 余量，是"沟宽有长有短"的代价**：0.72 时全程最多 3 列
##   （起步那几千米甚至只有 2 列），沟宽没有任何变化空间 —— 而"沟宽要随机变化、
##   既有短沟也有长沟"是明确的需求。0.78 让可见沟宽覆盖 2~4 列（128~256px），
##   同时每一档都留有足够余量。
## ⚠ 先试过 0.83，**但实测退回 0.78**：0.83 时跑速上限那档的沟宽到 5 列（320px），
##   而窄平台（2 列）上"落地→再次起跳"的窗口不够，自动驾驶的「掉坑」从 6 次涨到 24 次。
##   见 `min_landing_px_for()` 与 `Solvability` 的 R7。
const PIT_SAFETY := 0.78
## 往高处跳（如 0 → -1）跨沟时给更宽松的休闲跑酷余量，避免卡边掉崖
const PIT_SAFETY_UP := 0.70


## 从 h_from 跨跳到 h_to（层高差 step_delta = h_to - h_from，负值表示目标更高）时的水平跳跃覆盖距离（px）。
func jump_distance_delta(speed: float, step_delta_tiles: int) -> float:
	if step_delta_tiles == 0:
		return GameConfig.jump_distance(speed)
	var apex := GameConfig.jump_apex_height()
	var climb_px := float(-step_delta_tiles * GameConfig.TILE)
	var fall_dist := apex - climb_px
	if fall_dist <= 2.0:
		return 0.0
	var t_rise := absf(GameConfig.jump_velocity) / GameConfig.gravity
	var t_fall := sqrt(2.0 * fall_dist / (GameConfig.gravity * GameConfig.fall_gravity_mult))
	return speed * (t_rise + t_fall)


func max_safe_gap_px_between(speed: float, h_from: int, h_to: int) -> float:
	var step_delta := h_to - h_from
	if step_delta < -1:
		return 0.0
	var safety := PIT_SAFETY_UP if step_delta < 0 else PIT_SAFETY
	return jump_distance_delta(speed, step_delta) * safety


func min_landing_px_between(speed: float, gap_px: float, h_from: int, h_to: int) -> float:
	return maxf(0.0, jump_distance_delta(speed, h_to - h_from) - gap_px)


func max_safe_gap_px_for(speed: float) -> float:
	return GameConfig.jump_distance(speed) * PIT_SAFETY


func max_safe_gap_px() -> float:
	return max_safe_gap_px_for(player_target_speed())


## 最大安全坑宽（格）
func max_safe_gap_tiles() -> int:
	return int(max_safe_gap_px() / float(GameConfig.TILE))


## ★ **坑之后的「落点平台」最少要有多少像素**（`gap_px` = 坑的可见宽度）。
##
## 这是 R2 完全管不到的第二种致命地形 —— 而掉进坑里现在是立即死亡，
## 所以"落不下"和"跳不过"一样要命：
##
##   推导（起跳点贴在坑左沿；自动驾驶和真人都是这么跳的）：
##     落点 = 起跳点 + 一次完整跳跃距离 J，要落在坑右沿之后、且身体完全在平台上
##       J ≥ G + 玩家宽(44)   ← 跳得过去，R2 管这条
##       J ≤ G + P + 2        ← **落得下**，P = 后续平台宽度
##     ⇒ P ≥ J − G
##
## ⚠ 实测（2026-09-28 晚）：把 `PIT_SAFETY` 从 0.72 放到 0.83 加宽了沟之后，
##   自动驾驶的「掉坑」从 6 次跳到 **24 次** —— 因为窄平台 + 宽沟时，
##   一次满跳会直接飞过那块平台、落进下一个沟里。补上这条约束才降回去。
## ⚠ 它同时决定了「节奏风格」怎么配才成立：**平台越短，沟就必须越宽**
##   （`TerrainComposer.BROKEN_RHYTHM_STYLE` 的 `wide` 就是按这条定的）。
func min_landing_px_for(speed: float, gap_px: float) -> float:
	return maxf(0.0, GameConfig.jump_distance(speed) - gap_px)


func min_landing_px(gap_px: float) -> float:
	return min_landing_px_for(player_target_speed(), gap_px)


## 生成器允许的最大上台阶高度（px）
func max_safe_step_px() -> float:
	return GameConfig.jump_apex_height() * 0.72


## 最大安全上台阶（格）
func max_safe_step_tiles() -> int:
	# 跳跃 apex ≈ 2.15 格，保守取 1 格上台阶（因为起跳后还要考虑水平位移）
	return maxi(1, int(max_safe_step_px() / float(GameConfig.TILE)))


## 指定速度下，连续障碍之间要求的最小间隔（px）。
## 两个条件取大者：
##   1. 反应距离 —— 玩家眼睛看到之后手还来得及按
##   2. 一次完整跳跃的覆盖距离 —— 保证清掉上一个障碍后**已经落地**，
##      因为空中无法起跳也无法开始下滑，滞空撞上下一个障碍是不公平的
func min_hazard_spacing_px_for(speed: float) -> float:
	return maxf(speed * 0.55, GameConfig.jump_distance(speed) * 1.15)


func min_hazard_spacing_px() -> float:
	return min_hazard_spacing_px_for(player_target_speed())


## 障碍**之后**需要留的平地（px）。比「障碍最小间距」短，因为要挡的是另一件事：
##
## `min_hazard_spacing` 管的是「上一次跳跃必须已经落地」；而障碍后面这段管的是
## 「玩家必须已经结束这个障碍要求的动作」—— 典型场景是玩家正滑着钻过悬顶，
## 前方不远处一个坑会让他按跳，而**跳跃会强制结束滑铲**，
## 于是人在悬顶底下站起来了，当场撞头（2026-09-28 用撞击调试器抓到的真事故）。
##
## 需要的只是「发现坑 → 结束滑铲 → 站起来」这一段，取
##   0.45 × 一次跳跃距离（起跳判定提前量的量级）
## + 2 格（一个身位：滑铲盒宽 55px，加上完全离开悬顶的余量）
## 与实测吻合：470px/s 时 285px（4.5 格）、655px/s 时 345px（5.4 格）。
func dip_after_clearance_px_for(speed: float) -> float:
	return GameConfig.jump_distance(speed) * 0.45 + 2.0 * float(GameConfig.TILE)


func dip_after_clearance_px() -> float:
	return dip_after_clearance_px_for(player_target_speed())
