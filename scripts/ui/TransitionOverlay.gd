extends CanvasLayer
class_name TransitionOverlay
## 全屏像素溶解转场（320×180 整数 4× NEAREST 放大至 1280×720）。
##
## 在全遮蔽中点帧（frame >= 21）触发回调完成切场，随后揭开新画面。
## 树暂停期间也能正常推进（PROCESS_MODE_ALWAYS）。

const MID_FRAME := 21

var _fx: PixelFxPlayer
var _playing := false
var _mid_fired := false
var _on_mid: Callable


func _ready() -> void:
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_fx = PixelFxPlayer.new()
	_fx.auto_process = false
	_fx.finished.connect(_on_fx_finished)
	add_child(_fx)


func is_playing() -> bool:
	return _playing


func play_dissolve(on_mid: Callable, speed_scale := 2.4) -> void:
	if _playing:
		return
	_on_mid = on_mid
	_mid_fired = false
	_playing = true
	_fit_viewport()
	visible = true
	if not _fx.play("ui/pixel_dissolve", true, speed_scale, 0.0, false):
		_playing = false
		visible = false
		if _on_mid.is_valid():
			_on_mid.call()
		return


func _fit_viewport() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x > 0.0 and vs.y > 0.0:
		_fx.scale = Vector2(vs.x / 320.0, vs.y / 180.0)
	else:
		_fx.scale = Vector2(4.0, 4.0)
	_fx.position = Vector2.ZERO


func _process(delta: float) -> void:
	if not _playing:
		return
	_fx.advance(delta)
	if not _mid_fired and _fx._frame >= MID_FRAME:
		_mid_fired = true
		if _on_mid.is_valid():
			_on_mid.call()


func _on_fx_finished() -> void:
	if not _mid_fired and _on_mid.is_valid():
		_mid_fired = true
		_on_mid.call()
	_playing = false
	visible = false
