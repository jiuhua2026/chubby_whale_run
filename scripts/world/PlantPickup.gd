extends Area2D
class_name PlantPickup
## 跑酷赛道上的海洋植物采集物（嫩海带 / 深海紫菜 / 脆海藻 / 深渊星光藻）。
##
## 撞上即收进本局「深海保鲜箱」，播轻量拾取爆散光效；不阻挡玩家移动或触发掉速。

const PLANT_TEX := {
	"kelp": preload("res://sprites/plants/kelp.png"),
	"nori": preload("res://sprites/plants/nori.png"),
	"seaweed": preload("res://sprites/plants/seaweed.png"),
	"star_algae": preload("res://sprites/plants/star_algae.png"),
}

const PLANT_COLORS := {
	"kelp": Color(0.45, 0.96, 0.68, 0.92),
	"nori": Color(0.82, 0.56, 1.00, 0.94),
	"seaweed": Color(0.48, 0.96, 0.96, 0.95),
	"star_algae": Color(1.00, 0.88, 0.45, 1.00),
}

var plant_id := "kelp"
var _sprite: Sprite2D
var _base_y := 0.0
var _phase := 0.0
var _collected := false


func setup(p_plant_id: String, world_pos: Vector2, phase_offset: float = 0.0) -> void:
	plant_id = p_plant_id
	position = world_pos
	_base_y = world_pos.y
	_phase = phase_offset

	collision_layer = 0
	collision_mask = TerrainChunk.LAYER_PLAYER
	monitoring = true
	monitorable = false
	z_index = 1

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 32.0
	cs.shape = sh
	add_child(cs)

	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = PLANT_TEX.get(plant_id, PLANT_TEX["kelp"])
	_sprite.scale = Vector2(0.84, 0.84) if plant_id != "star_algae" else Vector2(0.94, 0.94)
	add_child(_sprite)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _collected:
		return
	_phase += delta
	if _sprite != null:
		# 根部扎在地形/台阶上随海流轻摆，不虚空上下漂浮
		_sprite.position.y = sin(_phase * 2.4) * 1.5
		_sprite.rotation = sin(_phase * 2.1) * 0.09
		if plant_id == "star_algae":
			var pulse := 0.86 + 0.14 * sin(_phase * 6.5)
			_sprite.modulate = Color(1.0 + 0.25 * pulse, 1.0 + 0.20 * pulse, 1.0 + 0.10 * pulse, 1.0)


func _on_body_entered(body: Node2D) -> void:
	if _collected or not (body is Player):
		return
	if not GameState.is_running() or GameState.is_sandbox():
		return
	if not GameState.add_plant(plant_id):
		# 保鲜箱已满且没有更低稀有度可替换：闪一下提醒，不销毁植物
		if _sprite != null:
			var tw := create_tween()
			tw.tween_property(_sprite, "modulate", Color(1.0, 0.45, 0.45, 0.7), 0.10)
			tw.tween_property(_sprite, "modulate", Color.WHITE, 0.16)
		return
	_collected = true
	set_deferred("monitoring", false)
	var pitch := 1.15
	match plant_id:
		"nori":
			pitch = 1.24
		"seaweed":
			pitch = 1.34
		"star_algae":
			pitch = 1.48
	AudioManager.play_sfx("near_miss", -1.5, pitch)
	_spawn_collect_fx()
	queue_free()


func _spawn_collect_fx() -> void:
	var host := get_parent()
	if host == null:
		return
	var fx := PixelFxPlayer.new()
	fx.z_index = 4
	fx.scale = Vector2(0.62, 0.62) if plant_id != "star_algae" else Vector2(0.85, 0.85)
	fx.modulate = PLANT_COLORS.get(plant_id, Color.WHITE)
	fx.position = global_position + Vector2(0.0, 12.0)
	host.add_child(fx)
	if not fx.play("action/dash_poof", true, 2.2, 0.0, true):
		fx.queue_free()
