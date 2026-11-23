extends Node
## GameState —— 全局状态、模式、计分与信号总线。
##
## 所有跨模块通信都走这里的信号，避免节点互相直接引用。
##
## 三种运行模式：
##   NORMAL   —— 正式玩法。障碍 + 死亡边界 + 高潮追击。
##   PRACTICE —— 练习。**与 NORMAL 完全相同**（地形、障碍、死亡边界、难度增长全在），
##               只是没有黑鲸娘、也不触发追击段。给"想练手但不想被追"的人用。
##   TEST     —— 开发沙盒。平坦地面、无任何障碍、无死亡边界、永不死亡、速度可调，
##               只用来反复看角色的跑 / 跳 / 滑动作。**不进主菜单**（`--testmode` 才进）。

signal ready_started()
signal run_started()
signal run_ended(reason: String, distance: float, score: int)
signal score_changed(score: int)
signal distance_meter_changed(meters: int)
signal near_miss_awarded()
signal dash_started()
signal player_hit(kind: String)
signal chase_started(index: int)
signal chase_ended(index: int)
signal menu_opened()

enum Mode { NORMAL, PRACTICE, TEST }
## MENU 是启动后的初始状态；READY 保留给"已选模式但还没开跑"的将来扩展
enum Phase { MENU, READY, RUNNING, DYING, ENDED }

var mode: Mode = Mode.NORMAL
var phase: Phase = Phase.MENU
var distance := 0.0
var score := 0
## 本次跑动中已经触发过几次追逐战
var chase_index := 0
## 死亡原因，便于统计与调试
var death_reason := ""
var _last_dist_m := -1

## 分数换算：距离 + 追逐战奖励
const SCORE_PER_PX := 0.01
const SCORE_CHASE_BONUS := 500


## 练习模式：只少了追击，其余与 NORMAL 一致 —— **包括死亡边界**（掉坑/落后照样死）。
func is_practice() -> bool:
	return mode == Mode.PRACTICE


## 开发沙盒：平地、无碰撞、不死。⚠ 别拿它当"简单难度"，玩家不该看到它。
func is_sandbox() -> bool:
	return mode == Mode.TEST


func is_menu() -> bool:
	return phase == Phase.MENU


func reset() -> void:
	distance = 0.0
	score = 0
	chase_index = 0
	death_reason = ""
	_last_dist_m = -1
	Difficulty.reset()
	score_changed.emit(score)


## 开跑。不传模式就沿用当前模式（重开时用）。
func start_run(p_mode: int = -1) -> void:
	if p_mode >= 0:
		mode = p_mode as Mode
	reset()
	# 速度覆盖在 start_run 里统一重置，避免测试模式调过的速度漏进正式模式
	Difficulty.speed_override = -1.0
	phase = Phase.RUNNING
	run_started.emit()


## 进 1.25s 神庙式起跑短衔接（正常模式从主菜单进入及死后按 R 重开统一走这里）。
func begin_ready(p_mode: int = Mode.NORMAL) -> void:
	mode = p_mode as Mode
	reset()
	Difficulty.speed_override = -1.0
	phase = Phase.READY
	ready_started.emit()


## 起跑短衔接完成，无缝交出操控权进入正式奔跑（保持已有状态不二次重置）。
func commit_ready() -> void:
	if phase != Phase.READY:
		return
	phase = Phase.RUNNING
	run_started.emit()


func is_ready_phase() -> bool:
	return phase == Phase.READY


func to_menu() -> void:
	phase = Phase.MENU
	mode = Mode.NORMAL
	Difficulty.speed_override = -1.0
	reset()
	menu_opened.emit()


func add_distance(delta: float) -> void:
	if phase != Phase.RUNNING and phase != Phase.READY:
		return
	distance += delta
	# 必须同步给 Difficulty。漏掉这一行的话难度曲线永远停在 distance=0，
	# 速度不涨、tier 不升，高难度地形和悬顶障碍永远不会出现——
	# 而且不会报任何错，只表现为"这游戏怎么一直是同一个难度"。
	Difficulty.distance = distance
	var meters := int(floor(distance / 64.0))
	if meters != _last_dist_m:
		_last_dist_m = meters
		distance_meter_changed.emit(meters)
	var s := int(distance * SCORE_PER_PX)
	if s != score:
		score = s
		score_changed.emit(score)


func award_chase() -> void:
	score += SCORE_CHASE_BONUS
	score_changed.emit(score)


## 结束本局。reason 用于区分「被边界吞掉」「被追兵咬到」等死法。
func end_run(reason: String) -> void:
	if phase == Phase.ENDED:
		return
	death_reason = reason
	phase = Phase.ENDED
	run_ended.emit(reason, distance, score)


func is_running() -> bool:
	return phase == Phase.RUNNING
