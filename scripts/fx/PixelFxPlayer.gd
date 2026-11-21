extends Sprite2D
class_name PixelFxPlayer
## 通用 pixelfx 雪碧图播放器（基于 Sprite2D + region_rect，强制 NEAREST 过滤）。
##
## 设计要点：
##   1. 从 FxCatalog.SPECS 读取导出的网格尺寸、帧率、锚点，零运行时 JSON 解析；
##   2. centered = false + offset = -origin，使节点坐标直接对齐 pixelfx 语义锚点；
##   3. 支持循环（背景生态）与一次性自动回收（受击/冲刺/扑咬），也可由外部手推 advance()。

signal finished

static var _tex_cache := {}

var fx_key := ""
var one_shot := false
var auto_free := true
var speed_scale := 1.0
var auto_process := true

var _spec := {}
var _t := 0.0
var _frame := -1
var _done := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	region_enabled = true


func play(p_key: String, p_one_shot := false, p_speed_scale := 1.0, p_phase := 0.0, p_auto_free := true) -> bool:
	if not FxCatalog.SPECS.has(p_key):
		push_warning("[PixelFxPlayer] 未知特效键：%s" % p_key)
		return false
	_spec = FxCatalog.SPECS[p_key]
	fx_key = p_key
	one_shot = p_one_shot
	auto_free = p_auto_free
	speed_scale = maxf(p_speed_scale, 0.01)
	_done = false

	var path := String(_spec["path"])
	if not _tex_cache.has(path):
		var loaded := load(path)
		if loaded == null:
			push_warning("[PixelFxPlayer] 贴图加载失败：%s" % path)
			return false
		_tex_cache[path] = loaded
	texture = _tex_cache[path]

	var total := int(_spec["frames"])
	var fps := float(_spec["fps"])
	var dur := float(total) / maxf(fps, 1.0)
	_t = clampf(p_phase, 0.0, 1.0) * dur
	_frame = -1
	_apply_offset()
	_apply_frame(0)
	advance(0.0)
	set_process(auto_process)
	return true


func set_flipped_h(flipped: bool) -> void:
	if flip_h == flipped:
		return
	flip_h = flipped
	if not _spec.is_empty():
		_apply_offset()


func _apply_offset() -> void:
	var fw := float(_spec["frame_w"])
	var org: Vector2 = _spec["origin"]
	var ox := -(fw - org.x) if flip_h else -org.x
	offset = Vector2(ox, -org.y)


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


func advance(delta: float) -> void:
	if _spec.is_empty() or _done:
		return
	_t += delta * speed_scale
	var total := int(_spec["frames"])
	var fps := float(_spec["fps"])
	var raw_idx := int(floor(_t * fps))
	if one_shot:
		if raw_idx >= total:
			_apply_frame(total - 1)
			_done = true
			finished.emit()
			if auto_free:
				queue_free()
			return
		_apply_frame(clampi(raw_idx, 0, total - 1))
	else:
		_apply_frame(posmod(raw_idx, total))


func _apply_frame(idx: int) -> void:
	if idx == _frame:
		return
	_frame = idx
	var fw := float(_spec["frame_w"])
	var fh := float(_spec["frame_h"])
	var cols := int(_spec["cols"])
	@warning_ignore("integer_division")
	var row := idx / cols
	var col := idx % cols
	region_rect = Rect2(float(col) * fw, float(row) * fh, fw, fh)
