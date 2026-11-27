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
var _proj: BossProjectile

var in_chase := false
var in_barrage := false
var _post_hit_rush := false
var _wave_timer := GameConfig.chase_first_delay_sec
var _chase_timer := 0.0
var _started_count := 0
var _last_theme := -1
var _proj_timer := 0.0
var _barrage_left := 0
var _p2_next_is_barrage := true
var _last_px := 0.0
var _stall_t := 0.0


func setup(wall: DeathWall, chaser: Chaser, gen: TerrainGenerator, player: Player, proj: BossProjectile = null) -> void:
	_wall = wall
	_chaser = chaser
	_gen = gen
	_player = player
	_proj = proj
	if not GameState.dash_started.is_connected(_on_player_dash_started):
		GameState.dash_started.connect(_on_player_dash_started)


func reset() -> void:
	in_chase = false
	in_barrage = false
	_post_hit_rush = false
	_wave_timer = GameConfig.chase_first_delay_sec
	_chase_timer = 0.0
	_started_count = 0
	_proj_timer = 0.0
	_barrage_left = 0
	_p2_next_is_barrage = true
	_last_px = 0.0
	_stall_t = 0.0
	if _gen != null:
		_gen.exit_barrage_runway()
	if _proj != null:
		_proj.reset()


func update(delta: float) -> void:
	if not GameState.is_running() or _player == null:
		return

	if absf(_player.global_position.x - _last_px) < 12.0 * delta:
		_stall_t += delta
	else:
		_stall_t = 0.0
	_last_px = _player.global_position.x

	if in_barrage:
		# 狂暴召弹期：黑鲸娘不再贴身追击，专心从右侧召唤右→左致命飞行物
		if _barrage_left > 0 and _proj != null:
			_proj_timer -= delta
			if _proj_timer <= 0.0:
				_barrage_left -= 1
				_proj_timer = GameConfig.boss_proj_interval
				_proj.spawn_attack()
		elif _proj == null or not _proj.is_busy():
			_finish_barrage()
		return

	if not in_chase:
		# ★ 全部改成时间驱动：掉入实体凹槽顶墙停滞时，加速波次并强切追击咬杀，绝不死锁
		_wave_timer -= delta * (3.5 if _stall_t >= 1.5 else 1.0)
		if _wave_timer <= 0.0:
			if GameState.boss_enraged and _p2_next_is_barrage and _stall_t < 1.5:
				_begin_barrage()
			else:
				_begin()
	else:
		if _stall_t < 0.8 or _post_hit_rush:
			_chase_timer -= delta
		if _chase_timer <= 0.0:
			_finish()


func countdown() -> float:
	## 距离下一次追击/波次的剩余时间（秒），给 HUD 做预警用
	return maxf(0.0, _wave_timer)


func _begin() -> void:
	in_chase = true
	in_barrage = false
	_post_hit_rush = false
	_chase_timer = GameConfig.boss_p2_chase_sec if GameState.boss_enraged else GameConfig.chase_segment_sec
	_chaser.begin(_player.global_position.x)
	if not GameState.boss_enraged:
		_wall.set_parked(true)
	if _gen != null:
		_gen.exit_barrage_runway()
		_gen.push_script(_setpiece())
	GameState.chase_started.emit(_started_count)
	_started_count += 1


func _begin_barrage() -> void:
	in_chase = false
	in_barrage = true
	_post_hit_rush = false
	_barrage_left = GameConfig.boss_p2_barrage_count
	_proj_timer = 1.65
	_p2_next_is_barrage = false
	if _gen != null:
		_gen.enter_barrage_runway(_player.global_position.x)
	if _chaser != null and _chaser.active:
		_chaser.retreat_for_barrage()


func _finish_barrage() -> void:
	in_barrage = false
	if _gen != null:
		_gen.exit_barrage_runway()
	GameState.award_chase()
	_wave_timer = GameConfig.boss_p2_wave_interval_sec


func _on_player_dash_started() -> void:
	if not GameState.is_running() or not in_chase or _chaser == null or not _chaser.active or _chaser.is_biting() or _post_hit_rush:
		return
	# 近身距离判定：必须等黑鲸娘已经贴近进范围(<=240px)，Space 冲击波才算弹中扣血
	if _chaser.gap() > GameConfig.boss_dash_hit_range:
		return
	if _player != null and _player.dash_fx != null:
		_player.dash_fx.spawn_dash_shockwave(Vector2((_player.global_position.x + _chaser.x) * 0.5, _player.global_position.y - 52.0))
	var enraged_now := GameState.damage_boss(GameState.effective_dash_damage())
	if not GameState.is_hard_mode():
		GameState.add_bonus_score(180)
	_chaser.knockback(GameConfig.boss_dash_knockback)
	# 困难模式第 1/2/3 次扣血与常规模式近身震退后，统一先迅速回逼追 ~1.8s，随后慢慢消散
	_post_hit_rush = true
	_chase_timer = GameConfig.boss_post_hit_rush_sec
	if enraged_now:
		_wall.retreat_for_boss()
		_chaser.play_enrage_burst()
		AudioManager.play_sfx("chase_warning", 3.5, 0.75)


func _finish() -> void:
	var was_post_hit := _post_hit_rush
	in_chase = false
	_post_hit_rush = false
	_chaser.end()
	if not GameState.boss_enraged:
		_wall.set_parked(false)
	else:
		_p2_next_is_barrage = true
	if _gen != null:
		_gen.clear_script()
	GameState.award_chase()
	GameState.chase_ended.emit(_started_count - 1)
	if GameState.boss_enraged and was_post_hit:
		# 第3格刚打空触发红转黑：图3回逼结束并慢慢消散后，很快切入第一轮狂暴召弹
		_wave_timer = 2.0
	else:
		_wave_timer = GameConfig.boss_p2_wave_interval_sec if GameState.boss_enraged else GameConfig.chase_interval_sec


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
