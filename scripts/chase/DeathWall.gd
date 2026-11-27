extends Node2D
class_name DeathWall
## 常态压力：从左后方不断前压的「深渊水压墙」。
##
## 表现层由三部分组成（避免死黑遮罩与硬直竖边）：
##   1. 深墨蓝半透明渐进暗幕（保留 ~14% 透光，让被吞没的地形与角色隐约留出深海剪影）；
##   2. 顺时针旋转 +90° 的四层错速 Bayer 像素浪壁（wall/pressure_wave 覆盖浪锋与墙体内部）；
##   3. 墙体内部向右奔涌的低对比湍流长丝 + 前缘高亮水压激流粒。

const DRAW_LEFT := 2400.0
const FADE_LEFT := 460.0
const FADE_RIGHT := 28.0
const STREAM_COUNT := 44

class SurgeMote:
	var off := Vector2.ZERO   ## 相对前缘 x 的偏移
	var vx := 0.0
	var vy := 0.0
	var len := 8.0
	var size := 2.0
	var t := 0.0
	var life := 0.5
	var streak := true
	var interior := false

var x := 0.0
var active := false:
	set(v):
		active = v
		visible = v
		if active:
			queue_redraw()

var _player: Player
var _parked := false   ## 高潮追击期间把墙「停车」，避免两种压力叠加导致必死
var _retreating := false
var _retreat_t := 0.0
var _wave_root: Node2D
var _fade_tex: GradientTexture2D
var _motes: Array[SurgeMote] = []
var _spawn_acc := 0.0


func _ready() -> void:
	visible = false
	_build_gradient()
	_build_waves()


func _build_gradient() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.44, 0.74, 0.90, 1.0])
	grad.colors = PackedColorArray([
		Color(0.008, 0.022, 0.052, 0.86),
		Color(0.008, 0.024, 0.056, 0.76),
		Color(0.010, 0.030, 0.068, 0.58),
		Color(0.014, 0.038, 0.082, 0.28),
		Color(0.016, 0.048, 0.098, 0.0),
	])
	_fade_tex = GradientTexture2D.new()
	_fade_tex.gradient = grad
	_fade_tex.fill_from = Vector2(0.0, 0.5)
	_fade_tex.fill_to = Vector2(1.0, 0.5)
	_fade_tex.width = 256
	_fade_tex.height = 4


func _build_waves() -> void:
	_wave_root = Node2D.new()
	_wave_root.name = "PressureWave"
	add_child(_wave_root)

	# 顺时针旋转 +90°：原图上方波峰朝右推进，原图下方厚重暗体融入左侧深海；
	# 内部叠加两层低对比暗涌 + 前缘两层亮青浪脊，消灭左侧大片死黑空洞。
	var specs := [
		{"ox": -375.0, "oy": -210.0, "sx": -2.65, "sy": 2.35, "spd": 1.15, "ph": 0.72, "col": Color(0.24, 0.46, 0.68, 0.44)},
		{"ox": -255.0, "oy": -210.0, "sx": 2.65,  "sy": 2.20, "spd": 1.38, "ph": 0.23, "col": Color(0.32, 0.58, 0.82, 0.52)},
		{"ox": -138.0, "oy": -210.0, "sx": 2.65,  "sy": 2.15, "spd": 1.65, "ph": 0.00, "col": Color(0.80, 0.92, 1.0, 0.84)},
		{"ox": -118.0, "oy": -210.0, "sx": -2.65, "sy": 1.75, "spd": 2.25, "ph": 0.47, "col": Color(0.88, 0.97, 1.0, 0.54)},
	]
	for sp in specs:
		var fx := PixelFxPlayer.new()
		fx.rotation = PI * 0.5
		fx.scale = Vector2(sp["sx"], sp["sy"])
		fx.modulate = sp["col"]
		fx.position = Vector2(sp["ox"], sp["oy"])
		_wave_root.add_child(fx)
		if not fx.play("wall/pressure_wave", false, sp["spd"], sp["ph"]):
			fx.queue_free()


func setup(player: Player) -> void:
	_player = player
	z_index = 40


func reset(player_x: float) -> void:
	x = player_x - GameConfig.wall_start_gap
	_parked = false
	_retreating = false
	_retreat_t = 0.0
	modulate = Color.WHITE
	_motes.clear()
	_spawn_acc = 0.0
	for _i in 24:
		var m := _make_mote(true)
		m.t = randf_range(0.0, m.life * 0.8)
		_motes.append(m)
	active = true
	_sync_wave()
	queue_redraw()


func set_parked(p: bool) -> void:
	_parked = p


## 黑鲸娘进入红转黑锁血二阶段：把水压浪墙拉进屏幕左缘可视区并向左侧爆散退场，让玩家一眼看见水压散去。
func retreat_for_boss() -> void:
	if _retreating:
		return
	active = true
	visible = true
	_retreating = true
	_retreat_t = 0.0
	_parked = false
	var vp := get_viewport()
	var vw := vp.get_visible_rect().size.x if vp != null else 1280.0
	if _player != null:
		var left_vis := _player.global_position.x - vw * GameConfig.camera_player_screen_ratio
		x = maxf(x, left_vis + 88.0)
	var host := get_parent() if get_parent() != null else self
	var base_y := _player.global_position.y if _player != null else 0.0
	for oy in [-260.0, -130.0, 0.0, 90.0]:
		var fx := PixelFxPlayer.new()
		fx.z_index = 41
		fx.scale = Vector2(1.70, 1.70)
		fx.modulate = Color(0.75, 0.94, 1.0, 0.94)
		fx.position = Vector2(x + 16.0, base_y + oy)
		host.add_child(fx)
		if not fx.play("chase/wall_retreat", true, 1.35, 0.0, true):
			fx.queue_free()
	_sync_wave()
	queue_redraw()


func gap() -> float:
	if _player == null:
		return 0.0
	return _player.global_position.x - x


func update(delta: float) -> void:
	if not active or _player == null or not GameState.is_running():
		return

	if _retreating:
		_retreat_t += delta
		x += (_player.speed - 460.0) * delta
		modulate.a = maxf(0.0, 1.0 - _retreat_t / 0.85)
		_sync_wave()
		queue_redraw()
		if _retreat_t >= 0.85:
			active = false
			visible = false
			_retreating = false
			modulate = Color.WHITE
		return

	if _parked:
		# 停车：跟着玩家走，间距不变
		x += _player.speed * delta
	else:
		x += Difficulty.wall_speed(gap()) * delta

	_step_motes(delta)
	_sync_wave()
	queue_redraw()

	if _player.global_position.x <= x:
		_player.kill("caught_by_wall")


func _sync_wave() -> void:
	if _wave_root != null:
		var py := _player.global_position.y if _player != null else 0.0
		_wave_root.position = Vector2(x, py)


func _make_mote(interior: bool) -> SurgeMote:
	var m := SurgeMote.new()
	m.interior = interior
	var base_y := _player.global_position.y if _player != null else 0.0
	if interior:
		m.streak = randf() < 0.72
		m.off = Vector2(randf_range(-430.0, -32.0), base_y + randf_range(-560.0, 140.0))
		m.life = randf_range(0.55, 1.05)
		if m.streak:
			m.vx = randf_range(120.0, 230.0)
			m.vy = randf_range(-8.0, 8.0)
			m.len = randf_range(24.0, 58.0)
			m.size = float([2, 2, 3].pick_random())
		else:
			m.vx = randf_range(55.0, 110.0)
			m.vy = randf_range(-38.0, -12.0)
			m.size = float([3, 4, 5].pick_random())
	else:
		m.streak = randf() < 0.58
		m.off = Vector2(randf_range(-28.0, 8.0), base_y + randf_range(-540.0, 120.0))
		m.life = randf_range(0.28, 0.55)
		if m.streak:
			m.vx = randf_range(75.0, 150.0)
			m.vy = randf_range(-10.0, 10.0)
			m.len = randf_range(8.0, 20.0)
			m.size = 2.0
		else:
			m.vx = randf_range(35.0, 80.0)
			m.vy = randf_range(-34.0, -10.0)
			m.size = float([2, 3, 3, 4].pick_random())
	return m


func _step_motes(delta: float) -> void:
	var alive: Array[SurgeMote] = []
	for m in _motes:
		m.t += delta
		if m.t < m.life:
			m.off.x += m.vx * delta
			m.off.y += m.vy * delta
			if not m.streak:
				m.vy -= 18.0 * delta
			alive.append(m)
	_motes = alive

	_spawn_acc += delta * 54.0
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if _motes.size() >= STREAM_COUNT:
			break
		_motes.append(_make_mote(randf() < 0.62))


func _draw() -> void:
	if not active:
		return
	var top := -1200.0
	var bottom := 1400.0
	draw_rect(Rect2(x - DRAW_LEFT, top, DRAW_LEFT - FADE_LEFT, bottom - top),
		Color(0.008, 0.022, 0.052, 0.86))
	if _fade_tex != null:
		draw_texture_rect(_fade_tex,
			Rect2(x - FADE_LEFT, top, FADE_LEFT + FADE_RIGHT, bottom - top), false)

	for m in _motes:
		var u := clampf(m.t / m.life, 0.0, 1.0)
		var k := 1.0 - u
		var env := sin(PI * u)
		var p := Vector2(roundf(x + m.off.x), roundf(m.off.y))
		if m.interior:
			var a := (0.24 if m.streak else 0.30) * env
			if m.streak:
				draw_rect(Rect2(p.x, p.y, roundf(m.len * (0.6 + 0.4 * k)), m.size),
					Color(0.24, 0.58, 0.82, a))
			else:
				draw_rect(Rect2(p.x, p.y, m.size, m.size),
					Color(0.30, 0.66, 0.88, a))
		else:
			var a := (0.55 * env + 0.12) * k
			if m.streak:
				draw_rect(Rect2(p.x, p.y, roundf(m.len * k), m.size),
					Color(0.42, 0.82, 0.98, a))
			else:
				draw_rect(Rect2(p.x, p.y, m.size, m.size),
					Color(0.56, 0.88, 1.0, a * 0.85))
