extends Node
class_name ChaseDirector
## 追逐总导演：在「常态死亡边界」和「高潮实体追击」之间切换。
##
## 两种模式的职责分工（对应"两者结合"的设计决定）：
##   常态 —— 死亡边界缓慢收网，玩家靠干净跑动维持间距。压力低，允许失误。
##   追击 —— 边界停车（不再叠加压力），黑鲸娘以"玩家速度 + 逼近速率"追杀。
##            这段是零容错：撞一次基本就没了。压力高，节奏紧。
##
## 边界「停车」是必要的。如果两种压力同时叠加，追击段会变成必死，
## 玩家会觉得"不是我菜，是游戏不给我活路"。

var _wall: DeathWall
var _chaser: Chaser
var _gen: TerrainGenerator
var _player: Player

var in_chase := false
var _next_chase_at := 0.0
var _chase_end_x := 0.0
var _started_count := 0
var _last_theme := -1


func setup(wall: DeathWall, chaser: Chaser, gen: TerrainGenerator, player: Player) -> void:
	_wall = wall
	_chaser = chaser
	_gen = gen
	_player = player


func reset() -> void:
	in_chase = false
	_next_chase_at = GameConfig.chase_first_at
	_chase_end_x = 0.0
	_started_count = 0


func update(_delta: float) -> void:
	if not GameState.is_running() or _player == null:
		return
	if not in_chase:
		if GameState.distance >= _next_chase_at:
			_begin()
	elif _player.global_position.x >= _chase_end_x:
		_finish()


func countdown() -> float:
	## 距离下一次追击还有多远，给 HUD 做预警用
	return maxf(0.0, _next_chase_at - GameState.distance)


func _begin() -> void:
	in_chase = true
	_chase_end_x = _player.global_position.x + GameConfig.chase_segment_len
	_chaser.begin(_player.global_position.x)
	_wall.set_parked(true)
	# 手工插桩：把接下来的地形换成脚本化的固定段落，
	# 让 climax 的节奏是可设计的，而不是随机的。
	_gen.push_script(_setpiece())
	GameState.chase_started.emit(_started_count)
	_started_count += 1


func _finish() -> void:
	in_chase = false
	_chaser.end()
	_wall.set_parked(false)
	# 清掉剧本里没用完的条目。否则追击段结束时的残留会漏进普通路段，
	# 让"高潮段落是手工设计的"这件事被污染——普通路段必须回到纯随机生成。
	_gen.clear_script()
	GameState.award_chase()
	GameState.chase_ended.emit(_started_count - 1)
	_next_chase_at = GameState.distance + GameConfig.chase_interval


## 追击段落剧本：多套轻快主题轮换（含凸台、宽矮障与下凹），
## 避免每次追击都跑同一张固定图；未通过当前档位校验的条会自动跳过转随机合成块。
func _setpiece() -> Array[String]:
	var themes: Array = [
		["flat8", "low1", "mesa_low", "slide1", "low_then_slide", "valley3", "flat8"],
		["flat8", "mesa_low", "flat8", "ridge_step", "low1", "mesa_slide", "flat8"],
		["flat8", "mound_wave", "valley4_low", "slide1_long", "mesa_and_dip", "dense_combo", "flat8"],
		["flat10", "low_slide_low", "mesa_plain", "trench4", "long_gauntlet", "ridge_step", "flat8"],
	]
	var pick := randi_range(0, themes.size() - 1)
	if themes.size() > 1 and pick == _last_theme:
		pick = (pick + 1 + randi_range(0, themes.size() - 2)) % themes.size()
	_last_theme = pick
	var out: Array[String] = []
	for s in themes[pick]:
		out.append(str(s))
	return out
