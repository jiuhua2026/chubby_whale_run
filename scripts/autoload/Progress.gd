extends Node
## 玩家成长与成就持久化（`user://progress.cfg`）。
##
## 与设置文件 `user://settings.cfg` 分离，防止清空设置时丢失成就。
## 仅在 `GameState.mode == NORMAL` 且非自动化测试（`save_enabled`）时统计与写盘。

signal achievement_unlocked(ach: Dictionary, art_id: String)
signal skin_changed(skin_id: String)
signal shop_changed()
signal meal_buff_changed(dish_id: String)

const PATH := "user://progress.cfg"

var save_enabled := true

var equipped_skin := "default"
var unlocked_achievements := {}

## v2.0 海洋植物仓库、鲸尾兜扩容等级与小店经营存档
var ingredients := {"kelp": 0, "nori": 0, "seaweed": 0, "star_algae": 0}
var cooler_upgrade_lv := 0
var cooler_capacity := GameConfig.cooler_base_capacity
var total_boss_enrages := 0
var shell_coins := 0
var shop_fryer_lv := 0
var shop_decor_lv := 0
var active_meal_buff := ""
var shop_starter_claimed := false
var shop_total_served := 0
var shop_best_revenue := 0
var shop_disguise_served := 0

var stats := {
	"best_run_dist_m": 0,
	"best_no_hit_dist_m": 0,
	"best_run_near_misses": 0,
	"best_run_dashes": 0,
	"total_dist_m": 0,
	"total_near_misses": 0,
	"total_dashes": 0,
	"total_chases_survived": 0,
	"total_runs": 0,
	"caught_count": 0,
	"chasm_count": 0,
	"wall_count": 0,
	"total_star_algae": 0,
	"total_proj_dodged": 0,
	"total_shop_crisp": 0,
}

## 本局临时进度（每次正常模式开局重置）
var _run_dist_m := 0
var _run_near_misses := 0
var _run_dashes := 0
var _run_hits := 0
var _tracking_run := false
var _from_ready := false
## 自动化测试期间关闭真实写盘，但在内存中跑完整触发流程
var _force_track_for_test := false


func _ready() -> void:
	load_progress()
	GameState.ready_started.connect(_on_begin_or_start)
	GameState.run_started.connect(_on_run_started)
	GameState.distance_meter_changed.connect(_on_distance_meter)
	GameState.near_miss_awarded.connect(_on_near_miss)
	GameState.dash_started.connect(_on_dash)
	GameState.player_hit.connect(_on_player_hit)
	GameState.chase_ended.connect(_on_chase_ended)
	GameState.boss_enraged_started.connect(_on_boss_enraged)
	GameState.run_ended.connect(_on_run_ended)
	GameState.menu_opened.connect(_on_menu_opened)


# ---------------------------------------------------------------- 读写
func load_progress() -> void:
	_reset_in_memory()
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return

	var ac: Variant = cf.get_value("achievements", "unlocked", [])
	if typeof(ac) == TYPE_ARRAY:
		for aid_v in ac:
			var aid := String(aid_v)
			if not SkinCatalog.get_achievement(aid).is_empty():
				unlocked_achievements[aid] = true

	for k: String in stats.keys():
		stats[k] = maxi(0, int(cf.get_value("stats", k, 0)))

	var eq := String(cf.get_value("skins", "equipped", "default"))
	equipped_skin = eq if can_equip_skin(eq) else "default"

	for pk: String in ingredients.keys():
		ingredients[pk] = maxi(0, int(cf.get_value("shop", "ing_" + pk, 0)))
	# 以升级等级而非写死旧总格数持久化，自动修正旧版残留的 12 格存档为 9+1=10 格
	cooler_upgrade_lv = clampi(int(cf.get_value("shop", "cooler_upgrade_lv", 0)), 0, 3)
	cooler_capacity = GameConfig.cooler_base_capacity + cooler_upgrade_lv * 2
	total_boss_enrages = maxi(0, int(cf.get_value("shop", "total_boss_enrages", 0)))
	shell_coins = maxi(0, int(cf.get_value("shop", "shell_coins", 0)))
	shop_fryer_lv = clampi(int(cf.get_value("shop", "shop_fryer_lv", 0)), 0, 2)
	shop_decor_lv = clampi(int(cf.get_value("shop", "shop_decor_lv", 0)), 0, 2)
	var mb := String(cf.get_value("shop", "active_meal_buff", ""))
	active_meal_buff = mb if (mb != "" and not ShopCatalog.get_dish(mb).is_empty()) else ""
	shop_starter_claimed = bool(cf.get_value("shop", "shop_starter_claimed", false))
	shop_total_served = maxi(0, int(cf.get_value("shop", "shop_total_served", 0)))
	shop_best_revenue = maxi(0, int(cf.get_value("shop", "shop_best_revenue", 0)))
	shop_disguise_served = maxi(0, int(cf.get_value("shop", "shop_disguise_served", 0)))


func save_progress() -> void:
	if not save_enabled or not Settings.record_save_enabled:
		return
	var cf := ConfigFile.new()
	cf.set_value("achievements", "unlocked", unlocked_achievements.keys())
	cf.set_value("skins", "equipped", equipped_skin)
	for k: String in stats.keys():
		cf.set_value("stats", k, int(stats[k]))
	for pk: String in ingredients.keys():
		cf.set_value("shop", "ing_" + pk, int(ingredients[pk]))
	cf.set_value("shop", "cooler_upgrade_lv", cooler_upgrade_lv)
	cf.set_value("shop", "cooler_capacity", cooler_capacity)
	cf.set_value("shop", "total_boss_enrages", total_boss_enrages)
	cf.set_value("shop", "shell_coins", shell_coins)
	cf.set_value("shop", "shop_fryer_lv", shop_fryer_lv)
	cf.set_value("shop", "shop_decor_lv", shop_decor_lv)
	cf.set_value("shop", "active_meal_buff", active_meal_buff)
	cf.set_value("shop", "shop_starter_claimed", shop_starter_claimed)
	cf.set_value("shop", "shop_total_served", shop_total_served)
	cf.set_value("shop", "shop_best_revenue", shop_best_revenue)
	cf.set_value("shop", "shop_disguise_served", shop_disguise_served)
	cf.save(PATH)


func _reset_in_memory() -> void:
	equipped_skin = "default"
	unlocked_achievements = {}
	for pk: String in ingredients.keys():
		ingredients[pk] = 0
	cooler_upgrade_lv = 0
	cooler_capacity = GameConfig.cooler_base_capacity
	total_boss_enrages = 0
	shell_coins = 0
	shop_fryer_lv = 0
	shop_decor_lv = 0
	active_meal_buff = ""
	shop_starter_claimed = false
	shop_total_served = 0
	shop_best_revenue = 0
	shop_disguise_served = 0
	for k: String in stats.keys():
		stats[k] = 0
	_run_dist_m = 0
	_run_near_misses = 0
	_run_dashes = 0
	_run_hits = 0
	_tracking_run = false
	_from_ready = false


func begin_test_sandbox() -> void:
	save_enabled = false
	_force_track_for_test = true
	_reset_in_memory()


func end_test_sandbox() -> void:
	_force_track_for_test = false
	load_progress()


# ---------------------------------------------------------------- 成就查询
func is_achievement_unlocked(ach_id: String) -> bool:
	return unlocked_achievements.get(ach_id, false)


func is_skin_unlocked(skin_id: String) -> bool:
	var req := SkinCatalog.get_skin_required_achievements(skin_id)
	return unlocked_achievement_count() >= req


func can_equip_skin(skin_id: String) -> bool:
	return is_skin_unlocked(skin_id) and SkinCatalog.is_skin_playable(skin_id)


func set_equipped_skin(skin_id: String) -> bool:
	if not can_equip_skin(skin_id):
		return false
	if equipped_skin == skin_id:
		return true
	equipped_skin = skin_id
	save_progress()
	skin_changed.emit(equipped_skin)
	return true


func unlocked_achievement_count() -> int:
	return unlocked_achievements.size()


func _stat_value(stat_key: String) -> int:
	match stat_key:
		"total_boss_enrages":
			return total_boss_enrages
		"shop_total_served":
			return shop_total_served
		"shop_disguise_served":
			return shop_disguise_served
	return int(stats.get(stat_key, 0))


func achievement_progress(ach_id: String) -> Dictionary:
	var ach := SkinCatalog.get_achievement(ach_id)
	if ach.is_empty():
		return {"cur": 0, "target": 1, "done": false, "ratio": 0.0, "text": "0 / 1"}
	var done := is_achievement_unlocked(ach_id)
	var target := int(ach["target"])
	var stat_key := String(ach["stat"])
	var unit := String(ach.get("unit", ""))

	if stat_key == "combo_1000m_5dash":
		var sub_t := int(ach.get("sub_target", 5))
		var cur_m := int(stats["best_run_dist_m"])
		var cur_d := int(stats["best_run_dashes"])
		var r := 1.0 if done else 0.5 * (
			clampf(float(cur_m) / float(maxi(1, target)), 0.0, 1.0)
			+ clampf(float(cur_d) / float(maxi(1, sub_t)), 0.0, 1.0)
		)
		var txt := ("已达成" if done else "最佳 %d/%d m · 冲刺 %d/%d 次" % [cur_m, target, cur_d, sub_t])
		return {"cur": cur_m, "target": target, "sub_cur": cur_d, "sub_target": sub_t, "done": done, "ratio": r, "text": txt}

	var cur := mini(target, _stat_value(stat_key))
	if done:
		cur = target
	var ratio := clampf(float(cur) / float(maxi(1, target)), 0.0, 1.0)
	var label := "已达成" if done else "%d / %d %s" % [cur, target, unit]
	return {"cur": cur, "target": target, "done": done, "ratio": ratio, "text": label}


# ---------------------------------------------------------------- 局内统计与解锁判定
func _can_track() -> bool:
	if not GameState.is_savable_mode():
		return false
	if _force_track_for_test:
		return true
	return Settings.record_save_enabled


func _on_begin_or_start() -> void:
	_run_dist_m = 0
	_run_near_misses = 0
	_run_dashes = 0
	_run_hits = 0
	_from_ready = true
	_tracking_run = _can_track()


func _on_run_started() -> void:
	if _from_ready:
		_from_ready = false
		return
	_run_dist_m = 0
	_run_near_misses = 0
	_run_dashes = 0
	_run_hits = 0
	_tracking_run = _can_track()


func _on_menu_opened() -> void:
	if _tracking_run:
		_tracking_run = false
		save_progress()


func _on_distance_meter(meters: int) -> void:
	if not _can_track() or not _tracking_run:
		return
	if meters <= _run_dist_m:
		return
	var dm := meters - _run_dist_m
	_run_dist_m = meters
	stats["total_dist_m"] = int(stats["total_dist_m"]) + dm
	if _run_dist_m > int(stats["best_run_dist_m"]):
		stats["best_run_dist_m"] = _run_dist_m
	if _run_hits == 0 and _run_dist_m > int(stats["best_no_hit_dist_m"]):
		stats["best_no_hit_dist_m"] = _run_dist_m
	_check_unlocks()


func _on_near_miss() -> void:
	if not _can_track() or not _tracking_run:
		return
	_run_near_misses += 1
	stats["total_near_misses"] = int(stats["total_near_misses"]) + 1
	if _run_near_misses > int(stats["best_run_near_misses"]):
		stats["best_run_near_misses"] = _run_near_misses
	_check_unlocks()


func _on_dash() -> void:
	if not _can_track() or not _tracking_run:
		return
	_run_dashes += 1
	stats["total_dashes"] = int(stats["total_dashes"]) + 1
	if _run_dashes > int(stats["best_run_dashes"]):
		stats["best_run_dashes"] = _run_dashes
	_check_unlocks()


func _on_player_hit(_kind: String) -> void:
	if not _can_track() or not _tracking_run:
		return
	_run_hits += 1


func _on_chase_ended(_index: int) -> void:
	if not _can_track() or not _tracking_run:
		return
	stats["total_chases_survived"] = int(stats["total_chases_survived"]) + 1
	_check_unlocks()


func _on_boss_enraged() -> void:
	if not _can_track() or not _tracking_run:
		return
	total_boss_enrages += 1
	_check_unlocks()


func _on_run_ended(reason: String, _distance: float, _score: int) -> void:
	if not _can_track() or not _tracking_run:
		return
	_tracking_run = false
	for pk: String in GameState.run_plants.keys():
		ingredients[pk] = int(ingredients.get(pk, 0)) + int(GameState.run_plants[pk])
	stats["total_star_algae"] = int(stats.get("total_star_algae", 0)) + int(GameState.run_plants.get("star_algae", 0))
	stats["total_proj_dodged"] = int(stats.get("total_proj_dodged", 0)) + int(GameState.run_proj_dodged)
	stats["total_runs"] = int(stats["total_runs"]) + 1
	match reason:
		"caught_by_chaser":
			stats["caught_count"] = int(stats["caught_count"]) + 1
		"fell_into_chasm":
			stats["chasm_count"] = int(stats["chasm_count"]) + 1
		"caught_by_wall":
			stats["wall_count"] = int(stats["wall_count"]) + 1
	_check_unlocks()
	save_progress()


func _check_unlocks() -> void:
	var changed := false
	for ach: Dictionary in SkinCatalog.ACHIEVEMENTS:
		var aid := String(ach["id"])
		if is_achievement_unlocked(aid):
			continue
		var ok := false
		var stat_key := String(ach["stat"])
		var target := int(ach["target"])
		if stat_key == "combo_1000m_5dash":
			ok = _run_dist_m >= target and _run_dashes >= int(ach.get("sub_target", 5))
		else:
			ok = _stat_value(stat_key) >= target
		if ok:
			_grant_achievement(ach)
			changed = true
	if changed:
		save_progress()


func _grant_achievement(ach: Dictionary) -> void:
	var aid := String(ach["id"])
	unlocked_achievements[aid] = true
	var art_id := String(ach.get("reward_art", ""))
	var cnt := unlocked_achievement_count()
	for a: Dictionary in SkinCatalog.ARTWORKS:
		var req := int(a.get("unlock_achievements", 0))
		if req > 0 and req == cnt:
			art_id = String(a["id"])
			break
	achievement_unlocked.emit(ach, art_id)


# ---------------------------------------------------------------- v2.0 深海鲸堡小店持久化接口
func grant_shop_starter_if_needed() -> bool:
	if shop_starter_claimed:
		return false
	shop_starter_claimed = true
	ingredients["kelp"] = int(ingredients.get("kelp", 0)) + 3
	ingredients["nori"] = int(ingredients.get("nori", 0)) + 2
	ingredients["seaweed"] = int(ingredients.get("seaweed", 0)) + 2
	save_progress()
	shop_changed.emit()
	return true


func has_ingredients(cost: Dictionary) -> bool:
	for k: String in cost.keys():
		if int(ingredients.get(k, 0)) < int(cost[k]):
			return false
	return true


func spend_ingredients(cost: Dictionary) -> bool:
	if not has_ingredients(cost):
		return false
	for k: String in cost.keys():
		ingredients[k] = maxi(0, int(ingredients.get(k, 0)) - int(cost[k]))
	save_progress()
	shop_changed.emit()
	return true


func refund_ingredients(cost: Dictionary) -> void:
	for k: String in cost.keys():
		ingredients[k] = int(ingredients.get(k, 0)) + int(cost[k])
	save_progress()
	shop_changed.emit()


func add_shell_coins(delta: int) -> void:
	shell_coins = maxi(0, shell_coins + delta)
	save_progress()
	shop_changed.emit()


func set_active_meal_buff(dish_id: String) -> void:
	active_meal_buff = dish_id if (dish_id != "" and not ShopCatalog.get_dish(dish_id).is_empty()) else ""
	save_progress()
	meal_buff_changed.emit(active_meal_buff)
	shop_changed.emit()


func consume_active_meal_buff() -> String:
	var dish_id := active_meal_buff
	if dish_id == "":
		return ""
	active_meal_buff = ""
	save_progress()
	meal_buff_changed.emit("")
	shop_changed.emit()
	return dish_id


func upgrade_shop_track(track_id: String) -> bool:
	var idx := -1
	for i in ShopCatalog.UPGRADES.size():
		if String(ShopCatalog.UPGRADES[i]["id"]) == track_id:
			idx = i
			break
	if idx < 0:
		return false
	var spec: Dictionary = ShopCatalog.UPGRADES[idx]
	var max_lv := int(spec["max_lv"])
	var costs: Array = spec["costs"]
	var cur := 0
	match track_id:
		"fryer":
			cur = shop_fryer_lv
		"decor":
			cur = shop_decor_lv
		"cooler":
			cur = cooler_upgrade_lv
	if cur >= max_lv or cur >= costs.size():
		return false
	var price := int(costs[cur])
	if shell_coins < price:
		return false
	shell_coins -= price
	match track_id:
		"fryer":
			shop_fryer_lv += 1
		"decor":
			shop_decor_lv += 1
		"cooler":
			cooler_upgrade_lv += 1
			cooler_capacity = GameConfig.cooler_base_capacity + cooler_upgrade_lv * 2
	save_progress()
	shop_changed.emit()
	return true


func record_shift_result(served: int, revenue: int, disguise_hits: int, crisp_hits: int = 0) -> void:
	shop_total_served += maxi(0, served)
	if revenue > shop_best_revenue:
		shop_best_revenue = revenue
	shop_disguise_served += maxi(0, disguise_hits)
	stats["total_shop_crisp"] = int(stats.get("total_shop_crisp", 0)) + maxi(0, crisp_hits)
	_check_unlocks()
	save_progress()
	shop_changed.emit()


## 营业中单次上菜或金脆即时累计小店成就计数，无需等到打烊才弹窗。
func record_shop_instant(served_delta: int = 0, disguise_delta: int = 0, crisp_delta: int = 0) -> void:
	var dirty := false
	if served_delta > 0:
		shop_total_served += served_delta
		dirty = true
	if disguise_delta > 0:
		shop_disguise_served += disguise_delta
		dirty = true
	if crisp_delta > 0:
		stats["total_shop_crisp"] = int(stats.get("total_shop_crisp", 0)) + crisp_delta
		dirty = true
	if dirty:
		_check_unlocks()
		save_progress()
		shop_changed.emit()
