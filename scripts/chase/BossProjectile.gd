extends Node2D
class_name BossProjectile
## 黑鲸娘二阶段（红转黑锁血狂暴）右→左预警飞行物技能控制器。
##
## 设计：
##   · lane 0（低高度）：黑潮鲸牙浪刃（proj_low.png），必须按 `↑` 跳跃跨过；
##   · lane 1（中高度）：深渊漩涡飞轮（proj_mid.png），按 `↑` 跳或 `↓` 滑都能躲；
##   · lane 2（高高度）：黑鲸月牙裂空刃（proj_high.png），必须按 `↓` 滑铲钻过；
##   · 发射前右侧提前 0.95s 亮起红标（chase/skill_warning）与弹道预警线；
##   · 碰中飞行物直接致命结算（冲刺无敌期间撞入可击碎反弹）；
##   · 每次成功回避后，12% 纯随机概率在前方安全地面凝结 1 株稀有的「深渊星光藻」。

const TEX_PROJ_LOW := preload("res://sprites/boss_proj/proj_low.png")
const TEX_PROJ_MID := preload("res://sprites/boss_proj/proj_mid.png")
const TEX_PROJ_HIGH := preload("res://sprites/boss_proj/proj_high.png")

class WarnItem:
	var lane := 0
	var timer := 0.0
	var max_t := 0.90
	var base_y := 0.0
	var fx: PixelFxPlayer

class ProjItem:
	var lane := 0
	var world_x := 0.0
	var world_y := 0.0
	var t := 0.0
	var sp: Sprite2D
	var trail: Array[Vector2] = []

var _player: Player
var _terrain: TerrainGenerator
var _plant_parent: Node2D
var _warns: Array[WarnItem] = []
var _projs: Array[ProjItem] = []
var _last_lane := -1


func setup(p_player: Player, p_terrain: TerrainGenerator, p_plant_parent: Node2D) -> void:
	_player = p_player
	_terrain = p_terrain
	_plant_parent = p_plant_parent
	z_index = 46


func is_busy() -> bool:
	return not _warns.is_empty() or not _projs.is_empty()


func reset() -> void:
	for w in _warns:
		if w.fx != null and is_instance_valid(w.fx):
			w.fx.queue_free()
	_warns.clear()
	for p in _projs:
		if p.sp != null and is_instance_valid(p.sp):
			p.sp.queue_free()
	_projs.clear()
	_last_lane = -1
	queue_redraw()


func spawn_attack(p_lane: int = -1) -> void:
	if _player == null or not GameState.is_running():
		return
	var lane := p_lane
	if lane < 0:
		var cands := []
		for l in [0, 1, 2]:
			if l != _last_lane:
				cands.append(l)
		lane = int(cands[randi_range(0, cands.size() - 1)])
	_last_lane = lane

	var wi := WarnItem.new()
	wi.lane = lane
	wi.max_t = GameConfig.boss_proj_warn_time
	wi.timer = wi.max_t
	wi.base_y = _safe_surface_y(_player.global_position.x + 280.0)
	if _player.is_on_floor() and _player.global_position.y > wi.base_y + 18.0:
		wi.base_y = _player.global_position.y

	var fx := PixelFxPlayer.new()
	fx.z_index = 47
	fx.scale = Vector2(1.12, 1.12)
	fx.modulate = Color(1.0, 0.92, 0.92, 0.98)
	add_child(fx)
	if not fx.play("chase/skill_warning", false, 1.4, 0.0, false):
		fx.queue_free()
	else:
		wi.fx = fx
	_warns.append(wi)
	AudioManager.play_sfx("chase_warning", -2.5, 1.35)
	queue_redraw()


func _safe_surface_y(world_x: float) -> float:
	if _terrain != null:
		var lv := _terrain.level_at_world(world_x)
		if lv > TerrainGenerator.LEVEL_UNLOADED and lv <= 0:
			return float(lv * GameConfig.TILE)
	return 0.0


func _lane_offset_y(lane: int) -> float:
	if lane == 0:
		return -28.0
	if lane == 1:
		return -76.0
	return -120.0


func update(delta: float) -> void:
	if _player == null or not GameState.is_running():
		return
	var vp := get_viewport()
	var vw := vp.get_visible_rect().size.x if vp != null else 1280.0
	var right_rel := vw * (1.0 - GameConfig.camera_player_screen_ratio)
	var px := _player.global_position.x

	# 1) 推进右侧预警
	var alive_warns: Array[WarnItem] = []
	for wi in _warns:
		wi.timer -= delta
		if _player.is_on_floor() and _player.global_position.y > wi.base_y + 18.0:
			wi.base_y = _player.global_position.y
		if wi.fx != null and is_instance_valid(wi.fx):
			wi.fx.position = Vector2(px + right_rel - 46.0, wi.base_y + _lane_offset_y(wi.lane) + 42.0)
		if wi.timer <= 0.0:
			if wi.fx != null and is_instance_valid(wi.fx):
				wi.fx.queue_free()
			_launch_projectile(wi, right_rel)
		else:
			alive_warns.append(wi)
	_warns = alive_warns

	# 2) 世界坐标系高速右 → 左推进飞行物并检测致命命中 / 完美躲避
	var alive_projs: Array[ProjItem] = []
	var p_top := _player.global_position.y - Player.STAND_H * (
		GameConfig.slide_height_ratio if _player.is_sliding() else 1.0)
	var p_bot := _player.global_position.y
	for pi in _projs:
		pi.t += delta
		var prev_wx := pi.world_x
		pi.world_x -= GameConfig.boss_proj_world_speed * delta
		var wx := pi.world_x
		pi.trail.append(Vector2(wx, pi.world_y))
		if pi.trail.size() > 6:
			pi.trail.pop_front()
		if pi.sp != null and is_instance_valid(pi.sp):
			pi.sp.position = Vector2(wx, pi.world_y)
			if pi.lane == 1:
				pi.sp.rotation -= delta * 9.5
			elif pi.lane == 2:
				pi.sp.rotation = sin(pi.t * 12.0) * 0.08
				var p2 := 1.0 + 0.05 * sin(pi.t * 16.0)
				pi.sp.scale = Vector2(1.0 / p2, 1.0 * p2)
			else:
				var pulse := 1.0 + 0.07 * sin(pi.t * 18.0)
				pi.sp.scale = Vector2(1.06 * pulse, 1.06 / pulse)

		var hit_x := minf(wx, prev_wx) <= px + 32.0 and maxf(wx, prev_wx) >= px - 32.0
		var half_h := 18.0 if pi.lane == 0 else (16.0 if pi.lane == 1 else 36.0)
		var hit_y := (pi.world_y - half_h) <= p_bot and (pi.world_y + half_h) >= p_top
		if hit_x and hit_y:
			if _player.is_dashing():
				_spawn_parry_burst(Vector2(wx, pi.world_y))
				GameState.add_bonus_score(80)
				AudioManager.play_sfx("hit", -2.0, 1.5)
				if pi.sp != null and is_instance_valid(pi.sp):
					pi.sp.queue_free()
				continue
			# 中弹即死！
			_spawn_lethal_burst(Vector2(wx, pi.world_y))
			AudioManager.play_sfx("chase_bite", 2.0)
			if pi.sp != null and is_instance_valid(pi.sp):
				pi.sp.queue_free()
			_player.kill("caught_by_boss_proj")
			return

		if wx < px - vw * 0.34:
			if pi.sp != null and is_instance_valid(pi.sp):
				pi.sp.queue_free()
			GameState.run_proj_dodged += 1
			GameState.add_bonus_score(60)
			if randf() < GameState.effective_star_drop_chance():
				_spawn_star_algae_reward()
			continue

		alive_projs.append(pi)
	_projs = alive_projs

	if not _warns.is_empty() or not _projs.is_empty():
		queue_redraw()


func _launch_projectile(wi: WarnItem, right_rel: float) -> void:
	var pi := ProjItem.new()
	pi.lane = wi.lane
	pi.world_x = _player.global_position.x + right_rel + 28.0
	pi.world_y = wi.base_y + _lane_offset_y(wi.lane)
	var sp := Sprite2D.new()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.texture = TEX_PROJ_LOW if wi.lane == 0 else (TEX_PROJ_MID if wi.lane == 1 else TEX_PROJ_HIGH)
	sp.z_index = 46
	sp.position = Vector2(pi.world_x, pi.world_y)
	sp.scale = Vector2(1.06, 1.06) if wi.lane == 0 else (Vector2(0.95, 0.95) if wi.lane == 1 else Vector2(1.0, 1.0))
	add_child(sp)
	pi.sp = sp
	_projs.append(pi)


func _spawn_parry_burst(world_pos: Vector2) -> void:
	var host := _plant_parent if _plant_parent != null else self
	var fx := PixelFxPlayer.new()
	fx.z_index = 48
	fx.scale = Vector2(1.25, 1.25)
	fx.position = world_pos + Vector2(0.0, 26.0)
	host.add_child(fx)
	if not fx.play("action/dash_shockwave", true, 1.5, 0.0, true):
		fx.queue_free()


func _spawn_lethal_burst(world_pos: Vector2) -> void:
	var host := _plant_parent if _plant_parent != null else self
	var fx := PixelFxPlayer.new()
	fx.z_index = 49
	fx.scale = Vector2(1.05, 1.05)
	fx.position = world_pos + Vector2(0.0, 48.0)
	host.add_child(fx)
	if not fx.play("chase/dark_explosion", true, 1.6, 0.1, true):
		fx.queue_free()


func _spawn_star_algae_reward() -> void:
	if _plant_parent == null or _player == null or _terrain == null:
		return
	var spawn_x := _player.global_position.x + 520.0
	var tile := float(GameConfig.TILE)
	for off in range(0, 6):
		var tx := spawn_x + float(off) * tile
		var lv := _terrain.level_at_world(tx)
		if lv > TerrainGenerator.LEVEL_UNLOADED and lv <= 0:
			var wy := float(lv * GameConfig.TILE) - 24.0
			var pick := PlantPickup.new()
			pick.setup("star_algae", Vector2(tx, wy), randf() * TAU)
			_plant_parent.add_child(pick)
			return


func _draw() -> void:
	if _player == null:
		return
	for pi in _projs:
		if pi.trail.size() >= 2:
			for i in range(pi.trail.size() - 1):
				var k := float(i + 1) / float(pi.trail.size())
				var col_t := Color(0.95, 0.22, 0.38, 0.42 * k) if pi.lane == 1 else Color(0.28, 0.85, 1.0, 0.38 * k)
				draw_line(pi.trail[i] + Vector2(24.0, 0.0), pi.trail[i + 1] + Vector2(24.0, 0.0), col_t, 5.0 * k)
	if _warns.is_empty():
		return
	var vp := get_viewport()
	var vw := vp.get_visible_rect().size.x if vp != null else 1280.0
	var left_x := _player.global_position.x - vw * GameConfig.camera_player_screen_ratio
	var right_x := left_x + vw
	for wi in _warns:
		var prog := 1.0 - clampf(wi.timer / maxf(wi.max_t, 0.01), 0.0, 1.0)
		var pulse := 0.55 + 0.45 * sin(prog * PI * 7.0)
		var y := wi.base_y + _lane_offset_y(wi.lane)
		var col := Color(1.0, 0.20, 0.34, (0.30 + 0.44 * prog) * pulse)
		draw_line(Vector2(left_x, y), Vector2(right_x, y), col, 2.5 if prog > 0.65 else 1.5)
		draw_rect(Rect2(left_x, y - 9.0, vw, 18.0), Color(1.0, 0.12, 0.24, 0.07 * pulse))
