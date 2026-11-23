extends Node
## 玩家成长与成就持久化（`user://progress.cfg`）。
##
## 与设置文件 `user://settings.cfg` 分离，防止清空设置时丢失成就。
## 仅在 `GameState.mode == NORMAL` 且非自动化测试（`save_enabled`）时统计与写盘。

signal achievement_unlocked(ach: Dictionary, art_id: String)

const PATH := "user://progress.cfg"

var save_enabled := true

var unlocked_achievements := {}

var stats := {
	"best_run_dist_m": 0,
	"best_run_dashes": 0,
	"total_dist_m": 0,
	"total_near_misses": 0,
	"total_dashes": 0,
	"total_runs": 0,
	"caught_count": 0,
	"chasm_count": 0,
	"wall_count": 0,
}

## 本局临时进度（每次正常模式开局重置）
var _run_dist_m := 0
var _run_dashes := 0
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
			unlocked_achievements[String(aid_v)] = true

	for k: String in stats.keys():
		stats[k] = maxi(0, int(cf.get_value("stats", k, 0)))


func save_progress() -> void:
	if not save_enabled or not Settings.record_save_enabled:
		return
	var cf := ConfigFile.new()
	cf.set_value("achievements", "unlocked", unlocked_achievements.keys())
	for k: String in stats.keys():
		cf.set_value("stats", k, int(stats[k]))
	cf.save(PATH)


func _reset_in_memory() -> void:
	unlocked_achievements = {}
	for k: String in stats.keys():
		stats[k] = 0
	_run_dist_m = 0
	_run_dashes = 0
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


func unlocked_achievement_count() -> int:
	return unlocked_achievements.size()


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

	var cur := mini(target, int(stats.get(stat_key, 0)))
	if done:
		cur = target
	var ratio := clampf(float(cur) / float(maxi(1, target)), 0.0, 1.0)
	var label := "已达成" if done else "%d / %d %s" % [cur, target, unit]
	return {"cur": cur, "target": target, "done": done, "ratio": ratio, "text": label}


# ---------------------------------------------------------------- 局内统计与解锁判定
func _can_track() -> bool:
	if GameState.mode != GameState.Mode.NORMAL:
		return false
	if _force_track_for_test:
		return true
	return Settings.record_save_enabled


func _on_begin_or_start() -> void:
	_run_dist_m = 0
	_run_dashes = 0
	_from_ready = true
	_tracking_run = _can_track()


func _on_run_started() -> void:
	if _from_ready:
		_from_ready = false
		return
	_run_dist_m = 0
	_run_dashes = 0
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
	_check_unlocks()


func _on_near_miss() -> void:
	if not _can_track() or not _tracking_run:
		return
	stats["total_near_misses"] = int(stats["total_near_misses"]) + 1
	_check_unlocks()


func _on_dash() -> void:
	if not _can_track() or not _tracking_run:
		return
	_run_dashes += 1
	stats["total_dashes"] = int(stats["total_dashes"]) + 1
	if _run_dashes > int(stats["best_run_dashes"]):
		stats["best_run_dashes"] = _run_dashes
	_check_unlocks()


func _on_run_ended(reason: String, _distance: float, _score: int) -> void:
	if not _can_track() or not _tracking_run:
		return
	_tracking_run = false
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
			ok = int(stats.get(stat_key, 0)) >= target
		if ok:
			_grant_achievement(ach)
			changed = true
	if changed:
		save_progress()


func _grant_achievement(ach: Dictionary) -> void:
	var aid := String(ach["id"])
	unlocked_achievements[aid] = true
	var art_id := String(ach.get("reward_art", ""))
	achievement_unlocked.emit(ach, art_id)
