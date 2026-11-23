extends Control
class_name AchievementsPanel
## 主菜单「3 成就」图鉴面板：
##   左侧：初始纪念「深海女仆」 + 15 项游戏成就（含实时进度条，支持滚动浏览）
##   右侧：深海聚光灯画片舞台（未解锁展示暗蓝神秘剪影 + 锁印，达成后彩绘点亮）

signal closed()

const SILHOUETTE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.035, 0.120, 0.235, 0.92);
void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, a * tint.a);
}
"""

var _entries: Array[Dictionary] = []
var _sel := 0
var _summary_lbl: Label
var _left_scroll: ScrollContainer
var _list_panels: Array[PanelContainer] = []
var _list_names: Array[Label] = []
var _list_tags: Array[Label] = []
var _preview_rect: TextureRect
var _silhouette_mat: ShaderMaterial
var _badge_panel: PanelContainer
var _badge_lbl: Label
var _lock_stamp: PanelContainer
var _lock_lbl: Label
var _art_title: Label
var _art_desc: Label
var _cond_lbl: Label
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _prog_lbl: Label
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

	_entries.clear()
	_entries.append({
		"kind": "base",
		"ach_id": "",
		"art_id": "default",
		"title": "深海女仆",
		"tag": "初始",
	})
	for ach: Dictionary in SkinCatalog.ACHIEVEMENTS:
		var aid := String(ach["id"])
		var rid := String(ach.get("reward_art", ""))
		_entries.append({
			"kind": "ach",
			"ach_id": aid,
			"art_id": rid if rid != "" else "default",
			"title": String(ach["name"]),
			"tag": String(ach.get("tag", "画片" if rid != "" else "成就")),
		})

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
	panel.custom_minimum_size = Vector2(880, 0)
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

	var title := _mk("深海成就与纪念画片", 24, Color(0.84, 0.94, 1.0), 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(title)

	_summary_lbl = _mk("", 14, Color(0.68, 0.85, 0.97), 2)
	_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(_summary_lbl)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	root_vb.add_child(body)

	# 左侧列表（可滚动浏览全部 16 项：初始纪念 + 15 项成就）
	_left_scroll = ScrollContainer.new()
	_left_scroll.custom_minimum_size = Vector2(286, 430)
	_left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(_left_scroll)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(270, 0)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	_left_scroll.add_child(left_col)

	for i in _entries.size():
		var item_box := PanelContainer.new()
		item_box.custom_minimum_size = Vector2(270, 42)
		item_box.mouse_filter = Control.MOUSE_FILTER_STOP
		item_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0.05, 0.10, 0.17, 0.86)
		rsb.border_color = Color(0.22, 0.42, 0.58, 0.55)
		rsb.set_border_width_all(1)
		rsb.set_corner_radius_all(6)
		rsb.content_margin_left = 12
		rsb.content_margin_right = 12
		rsb.content_margin_top = 6
		rsb.content_margin_bottom = 6
		item_box.add_theme_stylebox_override("panel", rsb)
		item_box.mouse_entered.connect(_on_item_hover.bind(i))
		item_box.gui_input.connect(_on_item_input.bind(i))
		left_col.add_child(item_box)
		_list_panels.append(item_box)

		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_box.add_child(hb)

		var nm := _mk(String(_entries[i]["title"]), 16, Color(0.84, 0.92, 0.98), 3)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(nm)
		_list_names.append(nm)

		var tg := _mk("", 12, Color(0.60, 0.75, 0.88), 2)
		tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tg)
		_list_tags.append(tg)

	# 右侧纪念立绘舞台与详情区
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 9)
	body.add_child(right_col)

	var stage := PanelContainer.new()
	stage.custom_minimum_size = Vector2(0, 268)
	stage.clip_contents = true
	var st_sb := StyleBoxFlat.new()
	st_sb.bg_color = Color(0.055, 0.145, 0.245, 1.0)
	st_sb.border_color = Color(0.30, 0.58, 0.78, 0.68)
	st_sb.set_border_width_all(1)
	st_sb.set_corner_radius_all(10)
	st_sb.set_content_margin_all(0)
	stage.add_theme_stylebox_override("panel", st_sb)
	right_col.add_child(stage)

	var stage_box := Control.new()
	stage_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_box.clip_contents = true
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(stage_box)

	# 深海透光渐变底
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

	# 顶部柔和聚光光晕
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

	# 底部海底石台面（与角色鞋底贴齐）
	var floor_rect := ColorRect.new()
	floor_rect.anchor_left = 0.0
	floor_rect.anchor_right = 1.0
	floor_rect.anchor_top = 1.0
	floor_rect.anchor_bottom = 1.0
	floor_rect.offset_top = -46
	floor_rect.color = Color(0.030, 0.092, 0.175, 0.96)
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(floor_rect)

	var floor_top_face := ColorRect.new()
	floor_top_face.anchor_left = 0.0
	floor_top_face.anchor_right = 1.0
	floor_top_face.anchor_top = 1.0
	floor_top_face.anchor_bottom = 1.0
	floor_top_face.offset_top = -46
	floor_top_face.offset_bottom = -26
	floor_top_face.color = Color(0.088, 0.245, 0.388, 0.96)
	floor_top_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(floor_top_face)

	var floor_rim := ColorRect.new()
	floor_rim.anchor_left = 0.0
	floor_rim.anchor_right = 1.0
	floor_rim.anchor_top = 1.0
	floor_rim.anchor_bottom = 1.0
	floor_rim.offset_top = -47
	floor_rim.offset_bottom = -45
	floor_rim.color = Color(0.38, 0.74, 0.96, 0.58)
	floor_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(floor_rim)

	var sh_grad := Gradient.new()
	sh_grad.colors = PackedColorArray([Color(0.01, 0.04, 0.09, 0.72), Color(0.01, 0.04, 0.09, 0.0)])
	sh_grad.offsets = PackedFloat32Array([0.0, 1.0])
	var sh_tex := GradientTexture2D.new()
	sh_tex.gradient = sh_grad
	sh_tex.fill = GradientTexture2D.FILL_RADIAL
	sh_tex.fill_from = Vector2(0.5, 0.5)
	sh_tex.fill_to = Vector2(0.5, 0.0)
	sh_tex.width = 96
	sh_tex.height = 32
	var sh_rect := TextureRect.new()
	sh_rect.texture = sh_tex
	sh_rect.anchor_left = 0.5
	sh_rect.anchor_right = 0.5
	sh_rect.anchor_top = 1.0
	sh_rect.anchor_bottom = 1.0
	sh_rect.offset_left = -74
	sh_rect.offset_right = 74
	sh_rect.offset_top = -42
	sh_rect.offset_bottom = -26
	sh_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(sh_rect)

	if ResourceLoader.exists("res://sprites/fx/bubble.png"):
		var b_tex: Texture2D = load("res://sprites/fx/bubble.png")
		for bi in 6:
			var b := TextureRect.new()
			b.texture = b_tex
			b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var sz := 10.0 + float((bi * 5) % 12)
			b.size = Vector2(sz, sz)
			var bx := 42.0 + float(bi) * 68.0
			var by := 40.0 + float((bi * 57) % 185)
			b.position = Vector2(bx, by)
			b.modulate = Color(0.76, 0.94, 1.0, 0.22 + 0.05 * float(bi % 3))
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage_box.add_child(b)
			_bubbles.append({"node": b, "base_x": bx, "y": by, "spd": 16.0 + float(bi % 3) * 6.0, "phase": float(bi) * 1.3})

	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_rect.offset_top = 6
	_preview_rect.offset_bottom = -34
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_box.add_child(_preview_rect)

	# 神秘剪影锁印徽章（仅未解锁项居中显示在剪影胸前）
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

	# 右上角状态角标
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

	_art_title = _mk("", 22, Color(1.0, 0.86, 0.50), 3)
	right_col.add_child(_art_title)

	_art_desc = _mk("", 14, Color(0.76, 0.86, 0.94), 2)
	_art_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_col.add_child(_art_desc)

	_cond_lbl = _mk("", 14, Color(0.62, 0.84, 0.98), 2)
	right_col.add_child(_cond_lbl)

	var prog_hb := HBoxContainer.new()
	prog_hb.add_theme_constant_override("separation", 10)
	right_col.add_child(prog_hb)

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

	var hint := _mk("↑↓ / 点击 切换查看　ESC 返回主菜单", 13, Color(0.56, 0.70, 0.84), 2)
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
			y = 262.0
		item["y"] = y
		node.position = Vector2(float(item["base_x"]) + sin(t * 1.4 + float(item["phase"])) * 6.0, y)


func open(initial_art_id: String = "") -> void:
	visible = true
	if initial_art_id != "":
		for i in _entries.size():
			if String(_entries[i]["art_id"]) == initial_art_id or String(_entries[i]["ach_id"]) == initial_art_id:
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


func refresh() -> void:
	var total_ach := SkinCatalog.ACHIEVEMENTS.size()
	var done_ach := Progress.unlocked_achievement_count()
	var lit_arts := 1 # 深海女仆初始点亮
	for ach: Dictionary in SkinCatalog.ACHIEVEMENTS:
		if String(ach.get("reward_art", "")) != "" and Progress.is_achievement_unlocked(String(ach["id"])):
			lit_arts += 1
	_summary_lbl.text = "成就达成 %d / %d　·　纪念画片 %d / %d　·　累计 %d m　·　擦身 %d 次　·　冲刺 %d 次" % [
		done_ach, total_ach, lit_arts, SkinCatalog.ARTWORKS.size(),
		int(Progress.stats["total_dist_m"]),
		int(Progress.stats["total_near_misses"]),
		int(Progress.stats["total_dashes"]),
	]

	_sel = clampi(_sel, 0, _entries.size() - 1)
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var is_sel := i == _sel
		var unlocked: bool = (String(e["kind"]) == "base") or Progress.is_achievement_unlocked(String(e["ach_id"]))
		var rsb := _list_panels[i].get_theme_stylebox("panel") as StyleBoxFlat
		if is_sel:
			rsb.bg_color = Color(0.11, 0.21, 0.34, 0.96)
			rsb.border_color = Color(1.0, 0.86, 0.46, 0.95)
			_list_names[i].add_theme_color_override("font_color", Color(1.0, 0.88, 0.50))
		else:
			rsb.bg_color = Color(0.05, 0.10, 0.17, 0.86)
			rsb.border_color = Color(0.22, 0.42, 0.58, 0.55)
			_list_names[i].add_theme_color_override("font_color",
				Color(0.86, 0.94, 1.0) if unlocked else Color(0.56, 0.68, 0.80))

		if e["kind"] == "base":
			_list_tags[i].text = "初始纪念"
			_list_tags[i].add_theme_color_override("font_color", Color(0.52, 0.94, 0.68))
		elif unlocked:
			_list_tags[i].text = "已解锁"
			_list_tags[i].add_theme_color_override("font_color", Color(1.0, 0.86, 0.48))
		else:
			_list_tags[i].text = String(e["tag"]) + " · 锁"
			_list_tags[i].add_theme_color_override("font_color", Color(0.54, 0.66, 0.78))

	var cur: Dictionary = _entries[_sel]
	var art_id := String(cur["art_id"])
	var art := SkinCatalog.get_artwork(art_id)
	var pv_path := String(art["preview"])
	if not _tex_cache.has(pv_path) and ResourceLoader.exists(pv_path):
		_tex_cache[pv_path] = load(pv_path)
	_preview_rect.texture = _tex_cache.get(pv_path, null)

	var bsb := _badge_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if cur["kind"] == "base":
		_preview_rect.material = null
		_lock_stamp.visible = false
		_badge_lbl.text = "初始同伴 · 纪念画片"
		_badge_lbl.add_theme_color_override("font_color", Color(0.56, 0.96, 0.70))
		bsb.border_color = Color(0.42, 0.86, 0.62, 0.85)
		_art_title.text = String(art["name"])
		_art_desc.text = String(art["desc"])
		_cond_lbl.text = "解锁条件：初始默认自带（局内始终以经典深海女仆出战）"
		_bar_fill.anchor_right = 1.0
		_bar_fill.color = Color(0.46, 0.92, 0.64, 0.98)
		_prog_lbl.text = "已收集"
		_prog_lbl.add_theme_color_override("font_color", Color(0.52, 0.96, 0.70))
		if _left_scroll != null and _sel >= 0 and _sel < _list_panels.size():
			_left_scroll.ensure_control_visible.call_deferred(_list_panels[_sel])
		return

	var ach_id := String(cur["ach_id"])
	var ach := SkinCatalog.get_achievement(ach_id)
	var pr := Progress.achievement_progress(ach_id)
	var done := bool(pr["done"])
	var has_exclusive_art := String(ach.get("reward_art", "")) != ""
	var is_easter := String(ach.get("tag", "")) == "彩蛋"

	if done:
		_preview_rect.material = null
		_lock_stamp.visible = false
		_badge_lbl.text = ("已点亮 · " + String(art["name"])) if has_exclusive_art else ("彩蛋达成" if is_easter else "成就达成")
		_badge_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
		bsb.border_color = Color(0.92, 0.78, 0.36, 0.85)
		_art_title.text = ("%s · %s" % [String(ach["name"]), String(art["name"])]) if has_exclusive_art else String(ach["name"])
		_art_desc.text = String(art["desc"]) if has_exclusive_art else ("深海旅途中的奇遇瞬间，已收录进深海纪念档案。" if is_easter else "深海航程中的高光战绩，已永久镌刻进成就档案。")
		_bar_fill.color = Color(0.46, 0.92, 0.64, 0.98)
		_prog_lbl.add_theme_color_override("font_color", Color(0.52, 0.96, 0.70))
	else:
		_preview_rect.material = _silhouette_mat
		_lock_stamp.visible = true
		_lock_lbl.text = "尚未解锁 · 神秘剪影" if has_exclusive_art else ("彩蛋尚未触发" if is_easter else "成就尚未达成")
		_badge_lbl.text = "未解锁（剪影）"
		_badge_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.94))
		bsb.border_color = Color(0.36, 0.66, 0.84, 0.78)
		_art_title.text = "%s · ???" % String(ach["name"]) if has_exclusive_art else String(ach["name"])
		_art_desc.text = "达成下方挑战条件即可点亮这张深海纪念画片。" if has_exclusive_art else ("深海里的特殊遭遇，达成条件即可点亮彩蛋记录。" if is_easter else "在正常模式达成下方挑战条件即可解锁该项深海成就。")
		_bar_fill.color = Color(0.36, 0.78, 0.96, 0.95)
		_prog_lbl.add_theme_color_override("font_color", Color(0.76, 0.88, 0.96))

	_cond_lbl.text = "达成条件：%s" % String(ach["desc"])
	_bar_fill.anchor_right = float(pr["ratio"])
	_prog_lbl.text = String(pr["text"])
	if _left_scroll != null and _sel >= 0 and _sel < _list_panels.size():
		_left_scroll.ensure_control_visible.call_deferred(_list_panels[_sel])


func _on_item_hover(i: int) -> void:
	if not visible or _sel == i:
		return
	_sel = i
	refresh()
	AudioManager.play_sfx("ui_move", -4.0)


func _on_item_input(event: InputEvent, i: int) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_sel = i
			refresh()
			AudioManager.play_sfx("ui_move", -2.0)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_up"):
		_sel = wrapi(_sel - 1, 0, _entries.size())
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_sel = wrapi(_sel + 1, 0, _entries.size())
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back_to_menu") or event.is_action_pressed("menu_confirm"):
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
