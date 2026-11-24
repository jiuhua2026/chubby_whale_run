extends Control
class_name WardrobePanel
## 主菜单「3 换装」深海衣橱面板：
##   左侧：深海聚光灯展示舞台 + 皮肤简介 + 解锁/实机状态 + 换装按钮
##   右侧：2×3 正面大头贴网格（6 套皮肤，未解锁呈神秘剪影，无实机动作标注「实机动作待开发」）

signal closed()

const SILHOUETTE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.035, 0.120, 0.235, 0.92);
void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, a * tint.a);
}
"""

var _skins: Array[Dictionary] = []
var _sel := 0

var _summary_lbl: Label
var _preview_rect: TextureRect
var _silhouette_mat: ShaderMaterial
var _badge_panel: PanelContainer
var _badge_lbl: Label
var _lock_stamp: PanelContainer
var _lock_lbl: Label
var _skin_title: Label
var _skin_desc: Label
var _cond_lbl: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _prog_lbl: Label
var _equip_btn: Button

var _card_panels: Array[PanelContainer] = []
var _card_avatars: Array[TextureRect] = []
var _card_names: Array[Label] = []
var _card_statuses: Array[Label] = []
var _card_locks: Array[Label] = []

var _bubbles: Array[Dictionary] = []
var _tex_cache := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_fit()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

	var sh := Shader.new()
	sh.code = SILHOUETTE_SHADER
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = sh

	_skins.clear()
	for art: Dictionary in SkinCatalog.ARTWORKS:
		_skins.append(art)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.08, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(900, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.030, 0.070, 0.120, 0.96)
	sb.border_color = Color(0.32, 0.58, 0.74, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 10)
	panel.add_child(root_vb)

	var title := _mk("深海换装衣橱", 24, Color(0.84, 0.94, 1.0), 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(title)

	_summary_lbl = _mk("", 14, Color(0.68, 0.85, 0.97), 2)
	_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(_summary_lbl)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	root_vb.add_child(body)

	# -------------------------------- 左侧：聚光灯立绘舞台 + 详情 + 换装按钮
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(410, 0)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	body.add_child(left_col)

	var stage := PanelContainer.new()
	stage.custom_minimum_size = Vector2(410, 260)
	stage.clip_contents = true
	var st_sb := StyleBoxFlat.new()
	st_sb.bg_color = Color(0.055, 0.145, 0.245, 1.0)
	st_sb.border_color = Color(0.30, 0.58, 0.78, 0.68)
	st_sb.set_border_width_all(1)
	st_sb.set_corner_radius_all(10)
	st_sb.set_content_margin_all(0)
	stage.add_theme_stylebox_override("panel", st_sb)
	left_col.add_child(stage)

	var stage_box := Control.new()
	stage_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_box.clip_contents = true
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(stage_box)

	var bg_grad := Gradient.new()
	bg_grad.colors = PackedColorArray([
		Color(0.095, 0.275, 0.435, 1.0),
		Color(0.055, 0.175, 0.300, 1.0),
		Color(0.032, 0.098, 0.185, 1.0),
	])
	bg_grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var bg_tex := GradientTexture2D.new()
	bg_tex.gradient = bg_grad
	bg_tex.width = 16
	bg_tex.height = 128
	bg_tex.fill_from = Vector2(0.5, 0.0)
	bg_tex.fill_to = Vector2(0.5, 1.0)
	var bg_rect := TextureRect.new()
	bg_rect.texture = bg_tex
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(bg_rect)

	var spot_grad := Gradient.new()
	spot_grad.colors = PackedColorArray([
		Color(0.32, 0.72, 0.96, 0.32),
		Color(0.20, 0.54, 0.80, 0.10),
		Color(0.10, 0.30, 0.50, 0.0),
	])
	spot_grad.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	var spot_tex := GradientTexture2D.new()
	spot_tex.gradient = spot_grad
	spot_tex.fill = GradientTexture2D.FILL_RADIAL
	spot_tex.fill_from = Vector2(0.5, 0.42)
	spot_tex.fill_to = Vector2(0.5, 0.96)
	spot_tex.width = 128
	spot_tex.height = 128
	var spot_rect := TextureRect.new()
	spot_rect.texture = spot_tex
	spot_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	spot_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spot_rect.stretch_mode = TextureRect.STRETCH_SCALE
	spot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(spot_rect)

	var floor_rect := ColorRect.new()
	floor_rect.anchor_left = 0.0
	floor_rect.anchor_right = 1.0
	floor_rect.anchor_top = 1.0
	floor_rect.anchor_bottom = 1.0
	floor_rect.offset_top = -44
	floor_rect.color = Color(0.030, 0.092, 0.175, 0.96)
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(floor_rect)

	var floor_top_face := ColorRect.new()
	floor_top_face.anchor_left = 0.0
	floor_top_face.anchor_right = 1.0
	floor_top_face.anchor_top = 1.0
	floor_top_face.anchor_bottom = 1.0
	floor_top_face.offset_top = -44
	floor_top_face.offset_bottom = -25
	floor_top_face.color = Color(0.088, 0.245, 0.388, 0.96)
	floor_top_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(floor_top_face)

	var floor_rim := ColorRect.new()
	floor_rim.anchor_left = 0.0
	floor_rim.anchor_right = 1.0
	floor_rim.anchor_top = 1.0
	floor_rim.anchor_bottom = 1.0
	floor_rim.offset_top = -45
	floor_rim.offset_bottom = -43
	floor_rim.color = Color(0.38, 0.74, 0.96, 0.58)
	floor_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(floor_rim)

	if ResourceLoader.exists("res://sprites/fx/bubble.png"):
		var b_tex: Texture2D = load("res://sprites/fx/bubble.png")
		for bi in 6:
			var b := TextureRect.new()
			b.texture = b_tex
			b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var sz := 10.0 + float((bi * 5) % 12)
			b.size = Vector2(sz, sz)
			var bx := 32.0 + float(bi) * 62.0
			var by := 36.0 + float((bi * 57) % 180)
			b.position = Vector2(bx, by)
			b.modulate = Color(0.76, 0.94, 1.0, 0.22 + 0.05 * float(bi % 3))
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage_box.add_child(b)
			_bubbles.append({"node": b, "base_x": bx, "y": by, "spd": 16.0 + float(bi % 3) * 6.0, "phase": float(bi) * 1.3})

	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_rect.offset_top = 6
	_preview_rect.offset_bottom = -32
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(_preview_rect)

	_lock_stamp = PanelContainer.new()
	_lock_stamp.set_anchors_preset(Control.PRESET_CENTER)
	_lock_stamp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lock_stamp.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lock_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.025, 0.075, 0.145, 0.88)
	lsb.border_color = Color(0.36, 0.64, 0.84, 0.78)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(8)
	lsb.content_margin_left = 14
	lsb.content_margin_right = 14
	lsb.content_margin_top = 6
	lsb.content_margin_bottom = 6
	_lock_stamp.add_theme_stylebox_override("panel", lsb)
	stage_box.add_child(_lock_stamp)

	_lock_lbl = _mk("尚未解锁 · 神秘剪影", 14, Color(0.76, 0.90, 1.0), 2)
	_lock_stamp.add_child(_lock_lbl)

	_badge_panel = PanelContainer.new()
	_badge_panel.anchor_left = 1.0
	_badge_panel.anchor_right = 1.0
	_badge_panel.anchor_top = 0.0
	_badge_panel.anchor_bottom = 0.0
	_badge_panel.offset_right = -10
	_badge_panel.offset_top = 10
	_badge_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.04, 0.12, 0.22, 0.88)
	bsb.border_color = Color(0.36, 0.66, 0.84, 0.8)
	bsb.set_border_width_all(1)
	bsb.set_corner_radius_all(6)
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bsb.content_margin_top = 4
	bsb.content_margin_bottom = 4
	_badge_panel.add_theme_stylebox_override("panel", bsb)
	stage_box.add_child(_badge_panel)

	_badge_lbl = _mk("", 13, Color(0.86, 0.94, 1.0), 2)
	_badge_panel.add_child(_badge_lbl)

	_skin_title = _mk("", 21, Color(1.0, 0.86, 0.50), 3)
	left_col.add_child(_skin_title)

	_skin_desc = _mk("", 14, Color(0.76, 0.86, 0.94), 2)
	_skin_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skin_desc.custom_minimum_size = Vector2(400, 38)
	left_col.add_child(_skin_desc)

	_cond_lbl = _mk("", 14, Color(0.62, 0.84, 0.98), 2)
	left_col.add_child(_cond_lbl)

	var prog_hb := HBoxContainer.new()
	prog_hb.add_theme_constant_override("separation", 10)
	left_col.add_child(prog_hb)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.02, 0.05, 0.10, 0.95)
	_bar_bg.custom_minimum_size = Vector2(0, 10)
	_bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog_hb.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.36, 0.78, 0.96, 0.95)
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.anchor_right = 0.0
	_bar_bg.add_child(_bar_fill)

	_prog_lbl = _mk("", 13, Color(0.76, 0.88, 0.96), 2)
	_prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prog_hb.add_child(_prog_lbl)

	_equip_btn = Button.new()
	_equip_btn.custom_minimum_size = Vector2(240, 36)
	_equip_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_equip_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_equip_btn.focus_mode = Control.FOCUS_NONE
	_equip_btn.add_theme_font_size_override("font_size", 14)
	_equip_btn.pressed.connect(_on_equip_pressed)
	left_col.add_child(_equip_btn)

	# -------------------------------- 右侧：2×3 皮肤大头贴网格
	var right_wrap := VBoxContainer.new()
	right_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_wrap.add_theme_constant_override("separation", 10)
	body.add_child(right_wrap)

	var grid_title := _mk("全部深海造型（成就数量达标解锁）", 15, Color(0.78, 0.90, 1.0), 2)
	grid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_wrap.add_child(grid_title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right_wrap.add_child(grid)

	for i in _skins.size():
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(132, 166)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.05, 0.11, 0.19, 0.90)
		csb.border_color = Color(0.25, 0.48, 0.66, 0.65)
		csb.set_border_width_all(2)
		csb.set_corner_radius_all(10)
		csb.content_margin_left = 8
		csb.content_margin_right = 8
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", csb)
		card.mouse_entered.connect(_on_card_hover.bind(i))
		card.gui_input.connect(_on_card_input.bind(i))
		grid.add_child(card)
		_card_panels.append(card)

		var cvb := VBoxContainer.new()
		cvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cvb.add_theme_constant_override("separation", 4)
		card.add_child(cvb)

		var av_box := PanelContainer.new()
		av_box.custom_minimum_size = Vector2(108, 108)
		av_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		av_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av_sb := StyleBoxFlat.new()
		av_sb.bg_color = Color(0.04, 0.10, 0.18, 0.95)
		av_sb.border_color = Color(0.22, 0.42, 0.58, 0.50)
		av_sb.set_border_width_all(1)
		av_sb.set_corner_radius_all(8)
		av_sb.set_content_margin_all(2)
		av_box.add_theme_stylebox_override("panel", av_sb)
		cvb.add_child(av_box)

		var av_holder := Control.new()
		av_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		av_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_box.add_child(av_holder)

		var av_rect := TextureRect.new()
		av_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		av_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		av_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_holder.add_child(av_rect)
		_card_avatars.append(av_rect)

		var lk := _mk("🔒", 18, Color(0.78, 0.90, 1.0, 0.92), 2)
		lk.set_anchors_preset(Control.PRESET_CENTER)
		lk.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lk.grow_vertical = Control.GROW_DIRECTION_BOTH
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_holder.add_child(lk)
		_card_locks.append(lk)

		var nm := _mk("", 14, Color(0.88, 0.94, 1.0), 2)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cvb.add_child(nm)
		_card_names.append(nm)

		var st := _mk("", 12, Color(0.65, 0.80, 0.92), 2)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cvb.add_child(st)
		_card_statuses.append(st)

	var hint := _mk("↑↓←→ / 点击 选择造型　E / 回车 换上出战　ESC 返回主菜单", 13, Color(0.56, 0.70, 0.84), 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(hint)

	refresh()


func _fit() -> void:
	size = get_viewport_rect().size


func _process(delta: float) -> void:
	if not visible or _bubbles.is_empty():
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	for item: Dictionary in _bubbles:
		var node := item["node"] as TextureRect
		var y := float(item["y"]) - float(item["spd"]) * delta
		if y < -18.0:
			y = 256.0
		item["y"] = y
		node.position = Vector2(float(item["base_x"]) + sin(t * 1.4 + float(item["phase"])) * 6.0, y)


func open(initial_skin_id: String = "") -> void:
	visible = true
	var target := initial_skin_id if initial_skin_id != "" else Progress.equipped_skin
	for i in _skins.size():
		if String(_skins[i]["id"]) == target:
			_sel = i
			break
	refresh()
	AudioManager.play_sfx("ui_confirm", 0.0)


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play_sfx("ui_confirm", -2.0)
	closed.emit()


func _load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex_cache.has(path) and ResourceLoader.exists(path):
		_tex_cache[path] = load(path)
	return _tex_cache.get(path, null)


func refresh() -> void:
	var done_ach := Progress.unlocked_achievement_count()
	var total_ach := SkinCatalog.ACHIEVEMENTS.size()
	var unlocked_skins := 0
	for art: Dictionary in _skins:
		if Progress.is_skin_unlocked(String(art["id"])):
			unlocked_skins += 1
	var eq_art := SkinCatalog.get_artwork(Progress.equipped_skin)
	_summary_lbl.text = "已解锁皮肤 %d / %d　·　当前成就 %d / %d　·　当前出战：%s" % [
		unlocked_skins, _skins.size(), done_ach, total_ach, String(eq_art.get("name", "深海女仆"))
	]

	_sel = clampi(_sel, 0, _skins.size() - 1)
	for i in _skins.size():
		var art: Dictionary = _skins[i]
		var sid := String(art["id"])
		var req := int(art.get("unlock_achievements", 0))
		var unlocked := Progress.is_skin_unlocked(sid)
		var playable := SkinCatalog.is_skin_playable(sid)
		var equipped := (Progress.equipped_skin == sid)
		var is_sel := (i == _sel)

		var av_path := String(art.get("avatar", art["preview"]))
		_card_avatars[i].texture = _load_tex(av_path)
		_card_avatars[i].material = null if unlocked else _silhouette_mat
		_card_locks[i].visible = not unlocked

		_card_names[i].text = String(art["name"]) if unlocked else "???"
		var csb := _card_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		if is_sel:
			csb.bg_color = Color(0.11, 0.22, 0.36, 0.96)
			csb.border_color = Color(1.0, 0.86, 0.46, 0.96)
			_card_names[i].add_theme_color_override("font_color", Color(1.0, 0.88, 0.50))
		elif equipped:
			csb.bg_color = Color(0.06, 0.16, 0.22, 0.92)
			csb.border_color = Color(0.42, 0.90, 0.65, 0.85)
			_card_names[i].add_theme_color_override("font_color", Color(0.86, 0.96, 1.0))
		else:
			csb.bg_color = Color(0.05, 0.10, 0.18, 0.86)
			csb.border_color = Color(0.22, 0.42, 0.58, 0.58)
			_card_names[i].add_theme_color_override("font_color",
				Color(0.86, 0.94, 1.0) if unlocked else Color(0.56, 0.68, 0.80))

		if not unlocked:
			_card_statuses[i].text = "需 %d 成就" % req
			_card_statuses[i].add_theme_color_override("font_color", Color(0.56, 0.68, 0.80))
		elif equipped:
			_card_statuses[i].text = "✓ 出战中"
			_card_statuses[i].add_theme_color_override("font_color", Color(0.52, 0.96, 0.68))
		elif playable:
			_card_statuses[i].text = "可出战"
			_card_statuses[i].add_theme_color_override("font_color", Color(1.0, 0.86, 0.48))
		else:
			_card_statuses[i].text = "实机待开发"
			_card_statuses[i].add_theme_color_override("font_color", Color(0.62, 0.82, 0.96))

	# 刷新左侧大舞台与详情
	var cur: Dictionary = _skins[_sel]
	var cur_id := String(cur["id"])
	var cur_req := int(cur.get("unlock_achievements", 0))
	var cur_unlocked := Progress.is_skin_unlocked(cur_id)
	var cur_playable := SkinCatalog.is_skin_playable(cur_id)
	var cur_equipped := (Progress.equipped_skin == cur_id)

	_preview_rect.texture = _load_tex(String(cur["preview"]))
	var bsb := _badge_panel.get_theme_stylebox("panel") as StyleBoxFlat

	if not cur_unlocked:
		_preview_rect.material = _silhouette_mat
		_lock_stamp.visible = true
		_lock_lbl.text = "尚未解锁 · 神秘剪影"
		_badge_lbl.text = "未解锁（需 %d 个成就）" % cur_req
		_badge_lbl.add_theme_color_override("font_color", Color(0.72, 0.84, 0.96))
		bsb.border_color = Color(0.36, 0.66, 0.84, 0.78)
		_skin_title.text = "??? · 神秘造型"
		_skin_desc.text = "累计达成足够数量的深海成就即可点亮此造型。"
		var remain := maxi(0, cur_req - done_ach)
		_cond_lbl.text = "解锁条件：已达成 %d / %d 个成就（还差 %d 个）" % [done_ach, cur_req, remain]
		_bar_fill.color = Color(0.36, 0.78, 0.96, 0.95)
		_bar_fill.anchor_right = clampf(float(done_ach) / float(maxi(1, cur_req)), 0.0, 1.0)
		_prog_lbl.text = "%d / %d" % [mini(done_ach, cur_req), cur_req]
		_prog_lbl.add_theme_color_override("font_color", Color(0.76, 0.88, 0.96))
	elif cur_playable:
		_preview_rect.material = null
		_lock_stamp.visible = false
		if cur_equipped:
			_badge_lbl.text = "✓ 当前出战中"
			_badge_lbl.add_theme_color_override("font_color", Color(0.56, 0.96, 0.70))
			bsb.border_color = Color(0.42, 0.86, 0.62, 0.88)
		else:
			_badge_lbl.text = "已解锁 · 可出战"
			_badge_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
			bsb.border_color = Color(0.92, 0.78, 0.36, 0.88)
		_skin_title.text = String(cur["name"])
		_skin_desc.text = String(cur["desc"])
		_cond_lbl.text = "解锁条件：初始默认自带（支持换装出战）" if cur_req == 0 else "解锁条件：已达成 %d 个成就 · 可换装出战" % cur_req
		_bar_fill.color = Color(0.46, 0.92, 0.64, 0.98)
		_bar_fill.anchor_right = 1.0
		_prog_lbl.text = "可出战"
		_prog_lbl.add_theme_color_override("font_color", Color(0.52, 0.96, 0.70))
	else:
		_preview_rect.material = null
		_lock_stamp.visible = false
		_badge_lbl.text = "已解锁 · 实机动作待开发"
		_badge_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
		bsb.border_color = Color(0.40, 0.72, 0.92, 0.82)
		_skin_title.text = String(cur["name"])
		_skin_desc.text = String(cur["desc"])
		_cond_lbl.text = "解锁条件：已达成 %d 个成就 · 实机动作待开发，敬请期待" % cur_req
		_bar_fill.color = Color(0.46, 0.92, 0.64, 0.98)
		_bar_fill.anchor_right = 1.0
		_prog_lbl.text = "已解锁"
		_prog_lbl.add_theme_color_override("font_color", Color(0.52, 0.96, 0.70))

	_update_equip_btn(cur_id, cur_unlocked, cur_playable, cur_equipped, cur_req)


func _update_equip_btn(skin_id: String, unlocked: bool, playable: bool, equipped: bool, req: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if not unlocked:
		_equip_btn.disabled = true
		_equip_btn.text = "未解锁（需达成 %d 个成就）" % req
		sb.bg_color = Color(0.06, 0.11, 0.18, 0.75)
		sb.border_color = Color(0.28, 0.42, 0.56, 0.55)
		_equip_btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.68, 0.80))
	elif not playable:
		_equip_btn.disabled = true
		_equip_btn.text = "实机动作待开发（敬请期待）"
		sb.bg_color = Color(0.06, 0.12, 0.20, 0.78)
		sb.border_color = Color(0.30, 0.50, 0.70, 0.60)
		_equip_btn.add_theme_color_override("font_disabled_color", Color(0.64, 0.80, 0.94))
	elif equipped:
		_equip_btn.disabled = true
		_equip_btn.text = "✓ 当前出战形象"
		sb.bg_color = Color(0.08, 0.24, 0.18, 0.90)
		sb.border_color = Color(0.45, 0.92, 0.65, 0.90)
		_equip_btn.add_theme_color_override("font_disabled_color", Color(0.56, 0.96, 0.72))
	else:
		_equip_btn.disabled = false
		_equip_btn.text = "换上此形象（点击 / E）"
		sb.bg_color = Color(0.14, 0.25, 0.40, 0.96)
		sb.border_color = Color(1.0, 0.85, 0.45, 0.95)
		_equip_btn.add_theme_color_override("font_color", Color(1.0, 0.90, 0.56))
	_equip_btn.add_theme_stylebox_override("normal", sb)
	_equip_btn.add_theme_stylebox_override("hover", sb)
	_equip_btn.add_theme_stylebox_override("pressed", sb)
	_equip_btn.add_theme_stylebox_override("disabled", sb)


func _on_equip_pressed() -> void:
	if _sel < 0 or _sel >= _skins.size():
		return
	var sid := String(_skins[_sel]["id"])
	if Progress.set_equipped_skin(sid):
		AudioManager.play_sfx("ui_confirm", 0.0)
		refresh()


func _on_card_hover(i: int) -> void:
	if not visible or _sel == i:
		return
	_sel = i
	refresh()
	AudioManager.play_sfx("ui_move", -4.0)


func _on_card_input(event: InputEvent, i: int) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _sel == i and not _equip_btn.disabled:
				_on_equip_pressed()
			else:
				_sel = i
				refresh()
				AudioManager.play_sfx("ui_move", -2.0)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var cols := 3
	if event.is_action_pressed("menu_left"):
		_sel = wrapi(_sel - 1, 0, _skins.size())
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_sel = wrapi(_sel + 1, 0, _skins.size())
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_up"):
		_sel = wrapi(_sel - cols, 0, _skins.size())
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_sel = wrapi(_sel + cols, 0, _skins.size())
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E) \
			or event.is_action_pressed("menu_confirm"):
		if not _equip_btn.disabled:
			_on_equip_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back_to_menu"):
		close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()
		get_viewport().set_input_as_handled()


func _mk(text: String, size: int, col: Color, outline: int = 3) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.03, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	return l
