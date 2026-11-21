extends Node2D
class_name AmbientSeaFx
## 深海生态点缀（慢视差中远景）：鱼群、脉动水母与岩石上升气泡流。
##
## 层级约束：Backdrop (-50) < AmbientSeaFx (-30) < Terrain (0) < Player (2)。
## 亮度约束：通过压暗低对比冷青色板 + 半透明调制，确保远弱于前景地形板与障碍物。

const SPAN := 2400.0

class Slot:
	var node: PixelFxPlayer
	var parallax := 0.40
	var base_u := 0.0
	var base_y := 0.0
	var drift_vx := 0.0
	var bob_amp := 0.0
	var bob_freq := 0.0
	var bob_phase := 0.0

var _slots: Array[Slot] = []
var _cam_x := 0.0
var _time := 0.0


func _ready() -> void:
	z_index = -30
	_build_slots()
	_layout()


func _build_slots() -> void:
	# 远景鱼群（两层交错游动，慢视差）
	_add_slot("ambient/fish_school", 0.35, -720.0, -255.0, 1.5,
		Color(0.56, 0.74, 0.86, 0.44), 16.0, 4.0, 0.7, 0.10, false)
	_add_slot("ambient/fish_school", 0.42, 420.0, -185.0, 1.5,
		Color(0.60, 0.78, 0.90, 0.48), -14.0, 5.0, 0.6, 0.58, true)

	# 半透明脉动水母（轻度上下浮沉）
	_add_slot("ambient/jellyfish", 0.38, -260.0, -230.0, 1.5,
		Color(0.52, 0.72, 0.86, 0.46), 3.0, 9.0, 0.9, 0.25, false)
	_add_slot("ambient/jellyfish", 0.48, 860.0, -175.0, 1.75,
		Color(0.56, 0.76, 0.90, 0.50), -4.0, 10.0, 0.75, 0.72, true)

	# 岩隙上升气泡流（锚在远景礁峰与地形交界下方，随视差滚动）
	_add_slot("ambient/bubbles", 0.46, -540.0, 46.0, 1.5,
		Color(0.54, 0.74, 0.88, 0.42), 0.0, 0.0, 0.0, 0.15, false)
	_add_slot("ambient/bubbles", 0.52, 180.0, 58.0, 1.75,
		Color(0.58, 0.78, 0.92, 0.46), 0.0, 0.0, 0.0, 0.48, true)
	_add_slot("ambient/bubbles", 0.44, 960.0, 40.0, 1.5,
		Color(0.52, 0.72, 0.86, 0.40), 0.0, 0.0, 0.0, 0.82, false)


func _add_slot(
	fx_key: String,
	parallax: float,
	base_u: float,
	base_y: float,
	scale_xy: float,
	tint: Color,
	drift_vx: float,
	bob_amp: float,
	bob_freq: float,
	phase: float,
	flipped: bool
) -> void:
	var p := PixelFxPlayer.new()
	add_child(p)
	if not p.play(fx_key, false, 1.0, phase):
		p.queue_free()
		return
	p.scale = Vector2(scale_xy, scale_xy)
	p.modulate = tint
	p.set_flipped_h(flipped)

	var s := Slot.new()
	s.node = p
	s.parallax = parallax
	s.base_u = base_u
	s.base_y = base_y
	s.drift_vx = drift_vx
	s.bob_amp = bob_amp
	s.bob_freq = bob_freq
	s.bob_phase = phase * TAU
	_slots.append(s)


func follow(p_camera_x: float, _p_camera_y: float) -> void:
	_cam_x = p_camera_x
	_layout()


func _process(delta: float) -> void:
	_time += delta
	_layout()


func _layout() -> void:
	var half := SPAN * 0.5
	for s in _slots:
		var rel_x := wrapf(s.base_u + s.drift_vx * _time - _cam_x * s.parallax, -half, half)
		var bob := sin(_time * s.bob_freq + s.bob_phase) * s.bob_amp if s.bob_amp > 0.0 else 0.0
		s.node.position = Vector2(_cam_x + rel_x, s.base_y + bob)
