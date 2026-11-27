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
signal boss_hp_changed(hp: int, max_hp: int, enraged: bool)
signal boss_enraged_started()
signal plant_collected(plant_id: String, total: int, cap: int)
signal plant_dropped(plant_id: String, total: int, cap: int)

enum Mode { NORMAL, PRACTICE, TEST, HARD }
## MENU 是启动后的初始状态；READY 保留给"已选模式但还没开跑"的将来扩展
enum Phase { MENU, READY, RUNNING, DYING, ENDED }

const PLANT_BASIC_IDS := ["kelp", "nori", "seaweed"]
const PLANT_RARITY := ["kelp", "nori", "seaweed", "star_algae"]
const PLANT_NAMES := {
	"kelp": "嫩海带",
	"nori": "深海紫菜",
	"seaweed": "脆海藻",
	"star_algae": "星光藻",
}

var mode: Mode = Mode.NORMAL
var phase: Phase = Phase.MENU
var distance := 0.0
var score := 0
## 本次跑动中已经触发过几次追逐战
var chase_index := 0
## 死亡原因，便于统计与调试
var death_reason := ""
var _last_dist_m := -1
var _bonus_score := 0

## v2.0 Phase 1：Boss 状态与单局海洋植物「鲸尾兜」（9 格常规 + 1 格星光藻专属）
var boss_max_hp := GameConfig.boss_max_hp
var boss_hp := GameConfig.boss_max_hp
var boss_enraged := false
var basic_cap := GameConfig.cooler_basic_base_capacity
var star_cap := GameConfig.cooler_star_base_capacity
var cooler_cap := GameConfig.cooler_base_capacity
var run_plants := {"kelp": 0, "nori": 0, "seaweed": 0, "star_algae": 0}
var run_obstacles_broken := 0
var run_proj_dodged := 0
## v2.0 Phase 2：小店吃下的赛前套餐 Buff（仅正式出海 NORMAL 模式生效并消耗）
var active_run_buff := ""
var active_run_buff_dish := ""

## 分数换算：距离 + 追逐战奖励
const SCORE_PER_PX := 0.01
const SCORE_CHASE_BONUS := 500


## 练习模式：只少了追击，其余与 NORMAL 一致 —— **包括死亡边界**（掉坑/落后照样死）。
func is_practice() -> bool:
	return mode == Mode.PRACTICE


## 困难模式：黑鲸娘红转黑锁血狂暴 Boss 战 + 三高度飞行物 + 掉落星光藻 +20% 得分加成。
func is_hard_mode() -> bool:
	return mode == Mode.HARD


## 可正常采集植物、保存小店资源与统计纪录的模式（常规模式 + 困难模式）。
func is_savable_mode() -> bool:
	return mode == Mode.NORMAL or mode == Mode.HARD


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
	_bonus_score = 0
	boss_max_hp = GameConfig.boss_max_hp
	boss_hp = boss_max_hp
	boss_enraged = false
	var lv := Progress.cooler_upgrade_lv if Progress != null else 0
	basic_cap = GameConfig.cooler_basic_base_capacity + lv * 2
	star_cap = GameConfig.cooler_star_base_capacity
	cooler_cap = basic_cap + star_cap
	run_plants = {"kelp": 0, "nori": 0, "seaweed": 0, "star_algae": 0}
	run_obstacles_broken = 0
	run_proj_dodged = 0
	active_run_buff = ""
	active_run_buff_dish = ""
	Difficulty.reset()
	score_changed.emit(score)
	boss_hp_changed.emit(boss_hp, boss_max_hp, boss_enraged)
	plant_collected.emit("", 0, cooler_cap)


func total_plants() -> int:
	var n := 0
	for k in run_plants.keys():
		n += int(run_plants[k])
	return n


func basic_plants_count() -> int:
	var n := 0
	for bid: String in PLANT_BASIC_IDS:
		n += int(run_plants.get(bid, 0))
	return n


## 采集 1 株海洋植物入「鲸尾兜」：
##   · 常规 9 格专装基础三品（海带 / 紫菜 / 海藻），先到先得、绝不互相顶替；
##   · 第 10 格（star_cap = 1）专门保留给二阶段「星光藻」，同样绝不挤掉任何已有采集物。
func add_plant(plant_id: String) -> bool:
	if not run_plants.has(plant_id):
		return false
	if plant_id == "star_algae":
		var s_cnt := int(run_plants["star_algae"])
		if s_cnt >= star_cap:
			return false
		run_plants["star_algae"] = s_cnt + 1
		plant_collected.emit(plant_id, total_plants(), cooler_cap)
		return true
	if basic_plants_count() >= basic_cap:
		return false
	run_plants[plant_id] = int(run_plants[plant_id]) + 1
	plant_collected.emit(plant_id, total_plants(), cooler_cap)
	return true


## 撞击障碍物时概率滑落 1 株已采集植物（方案 A：按兜内四种实际颗数加权随机摸出 1 颗）
func drop_random_plant(force: bool = false) -> String:
	var tot := total_plants()
	if tot <= 0:
		return ""
	if not force and randf() >= GameConfig.hit_plant_drop_chance:
		return ""
	var pick := randi_range(0, tot - 1)
	var acc := 0
	var dropped := ""
	for pid: String in PLANT_RARITY:
		var cnt := int(run_plants.get(pid, 0))
		if cnt <= 0:
			continue
		acc += cnt
		if pick < acc:
			dropped = pid
			run_plants[pid] = cnt - 1
			break
	if dropped == "":
		return ""
	plant_dropped.emit(dropped, total_plants(), cooler_cap)
	return dropped


## 对黑鲸娘一阶段红血条造成伤害（仅困难模式生效）；归零瞬间进入红转黑锁血二阶段并返回 true。
func damage_boss(dmg: int = 1) -> bool:
	if not is_hard_mode() or boss_enraged or dmg <= 0:
		return false
	boss_hp = maxi(0, boss_hp - dmg)
	if boss_hp == 0:
		boss_enraged = true
		boss_hp_changed.emit(0, boss_max_hp, true)
		boss_enraged_started.emit()
		return true
	boss_hp_changed.emit(boss_hp, boss_max_hp, false)
	return false


func effective_dash_charge_max() -> int:
	return 2 if active_run_buff == "fast_charge" else GameConfig.dash_charge_max


func effective_dash_damage() -> int:
	return 2 if active_run_buff == "power_dash" else 1


func effective_star_drop_chance() -> float:
	return 0.22 if active_run_buff == "star_luck" else GameConfig.boss_proj_star_drop_chance


func _apply_pre_run_meal_buff() -> void:
	if not is_savable_mode() or Progress == null:
		return
	var dish_id := Progress.consume_active_meal_buff()
	if dish_id == "":
		return
	var dish := ShopCatalog.get_dish(dish_id)
	if dish.is_empty():
		return
	active_run_buff_dish = dish_id
	active_run_buff = String(dish.get("buff_id", ""))


## 开跑。不传模式就沿用当前模式（重开时用）。
func start_run(p_mode: int = -1) -> void:
	if p_mode >= 0:
		mode = p_mode as Mode
	reset()
	_apply_pre_run_meal_buff()
	# 速度覆盖在 start_run 里统一重置，避免测试模式调过的速度漏进正式模式
	Difficulty.speed_override = -1.0
	phase = Phase.RUNNING
	run_started.emit()


## 进 1.25s 神庙式起跑短衔接（正常模式从主菜单进入及死后按 R 重开统一走这里）。
func begin_ready(p_mode: int = Mode.NORMAL) -> void:
	mode = p_mode as Mode
	reset()
	_apply_pre_run_meal_buff()
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


func _score_mult() -> float:
	var m := 1.2 if active_run_buff == "star_luck" else 1.0
	if mode == Mode.HARD:
		m *= 1.2
	return m


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
	var s := int(distance * SCORE_PER_PX * _score_mult()) + _bonus_score
	if s != score:
		score = s
		score_changed.emit(score)


func add_bonus_score(pts: int) -> void:
	if pts == 0:
		return
	var bonus_pts := roundi(float(pts) * _score_mult())
	_bonus_score += bonus_pts
	score = int(distance * SCORE_PER_PX * _score_mult()) + _bonus_score
	score_changed.emit(score)


func award_chase() -> void:
	add_bonus_score(SCORE_CHASE_BONUS)


## 结束本局。reason 用于区分「被边界吞掉」「被追兵咬到」等死法。
func end_run(reason: String) -> void:
	if phase == Phase.ENDED:
		return
	death_reason = reason
	phase = Phase.ENDED
	run_ended.emit(reason, distance, score)


func is_running() -> bool:
	return phase == Phase.RUNNING
