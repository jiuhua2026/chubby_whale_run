extends CanvasLayer
class_name AchievementToast
## 局内成就解锁顶部轻提示横幅：逐条排队滑出，不打断跑酷节奏。

const HOLD_SEC := 2.6

var _card: PanelContainer
var _title_lbl: Label
var _sub_lbl: Label
var _queue: Array[Dictionary] = []
var _showing := false
var _tw: Tween


func _ready() -> void:
	layer = 210
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_card = PanelContainer.new()
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.0
	_card.anchor_bottom = 0.0
	_card.offset_left = -220
	_card.offset_right = 220
	_card.offset_top = -90
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.085, 0.145, 0.94)
	sb.border_color = Color(0.95, 0.80, 0.38, 0.92)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_card.add_theme_stylebox_override("panel", sb)
	root.add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(vb)

	_title_lbl = _mk("", 17, Color(1.0, 0.88, 0.48), 3)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title_lbl)

	_sub_lbl = _mk("", 13, Color(0.84, 0.94, 1.0), 2)
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_sub_lbl)

	Progress.achievement_unlocked.connect(_on_unlocked)


func _on_unlocked(ach: Dictionary, art_id: String) -> void:
	_queue.append({"ach": ach, "art_id": art_id})
	if not _showing:
		_pop_next()


func _pop_next() -> void:
	if _queue.is_empty():
		_showing = false
		_card.visible = false
		return
	_showing = true
	var item: Dictionary = _queue.pop_front()
	var ach: Dictionary = item["ach"]
	var aid := String(item["art_id"])
	_title_lbl.text = "成就达成 · %s" % String(ach.get("name", ""))
	if aid != "":
		var art := SkinCatalog.get_artwork(aid)
		_sub_lbl.text = "解锁纪念画片：%s（可在主菜单「成就」欣赏）" % String(art.get("name", aid))
	else:
		_sub_lbl.text = "彩蛋成就已收录至主菜单「成就」"

	_card.visible = true
	_card.modulate.a = 0.0
	_card.offset_top = -84.0
	AudioManager.play_sfx("dash_ready", -2.0)

	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_card, "offset_top", 56.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_card, "modulate:a", 1.0, 0.22)
	_tw.chain()
	_tw.tween_interval(HOLD_SEC)
	_tw.chain()
	_tw.set_parallel(true)
	_tw.tween_property(_card, "offset_top", -84.0, 0.25).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(_card, "modulate:a", 0.0, 0.25)
	_tw.chain()
	_tw.tween_callback(_pop_next)


func is_showing() -> bool:
	return _showing


func pending_count() -> int:
	return _queue.size()


func _mk(text: String, size: int, col: Color, outline: int = 3) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.03, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	return l
