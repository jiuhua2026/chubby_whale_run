extends Control
class_name AchievementsPanel
## 设置 →「深海成就」面板（参考《潜水员戴夫》海洋成就档案排版）：
##   顶部：总成就完成度进度条 + 下一皮肤里程碑提示 + 分类筛选页签（全部 / 历程 / 技巧 / 追击 / 彩蛋）
##   主体：双列成就徽章卡片网格（左：分类主题徽章；中：标题/条件/内置进度条；右：达成状态戳）

signal closed()

const CATEGORIES := ["全部", "历程", "技巧", "追击", "彩蛋"]

var _cat_idx := 0
var _summary_lbl: Label
var _total_bar_fill: ColorRect
var _tab_btns: Array[Button] = []
var _scroll: ScrollContainer
var _grid: GridContainer
var _cards: Array[Dictionary] = []


class BadgeIcon extends Control:
	var tag := "历程"
	var unlocked := false

	func _init(p_tag: String = "历程") -> void:
		tag = p_tag
		custom_minimum_size = Vector2(48, 48)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(p_unlocked: bool) -> void:
		if unlocked != p_unlocked:
			unlocked = p_unlocked
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var bg := Color(0.09, 0.22, 0.34, 0.95) if unlocked else Color(0.04, 0.08, 0.14, 0.95)
		var ring := Color(1.0, 0.84, 0.42, 0.95) if unlocked else Color(0.24, 0.38, 0.52, 0.60)
		var fg := Color(1.0, 0.90, 0.52, 1.0) if unlocked else Color(0.32, 0.46, 0.60, 0.72)
		var acc := Color(0.45, 0.92, 0.98, 1.0) if unlocked else Color(0.24, 0.38, 0.52, 0.55)

		draw_circle(c, r, bg)
		draw_arc(c, r, 0.0, TAU, 28, ring, 2.0, true)

		match tag:
			"技巧":
				# 双翼疾风符号
				var p1 := PackedVector2Array([
					c + Vector2(-11, 5), c + Vector2(-1, -10),
					c + Vector2(3, -1), c + Vector2(12, -6),
					c + Vector2(2, 10), c + Vector2(-3, 2),
				])
				draw_colored_polygon(p1, fg)
				draw_arc(c, r * 0.58, -PI * 0.8, -PI * 0.15, 10, acc, 2.0)
			"追击":
				# 警报三角盾徽
				var tri := PackedVector2Array([
					c + Vector2(0, -11), c + Vector2(11, 9), c + Vector2(-11, 9)
				])
				draw_colored_polygon(tri, fg)
				draw_line(c + Vector2(0, -4), c + Vector2(0, 2), bg, 2.5)
				draw_circle(c + Vector2(0, 5.5), 1.6, bg)
			"彩蛋":
				# 深海贝壳/彩蛋星芒
				draw_circle(c, 8.0, acc)
				draw_arc(c, 11.0, 0.0, TAU, 16, fg, 1.8)
				draw_circle(c + Vector2(-2.5, -2.5), 2.2, Color(1.0, 0.98, 0.9, 0.9) if unlocked else bg)
			_:
				# 历程：深海罗盘菱星
				var star := PackedVector2Array([
					c + Vector2(0, -12), c + Vector2(4, -4),
					c + Vector2(12, 0), c + Vector2(4, 4),
					c + Vector2(0, 12), c + Vector2(-4, 4),
					c + Vector2(-12, 0), c + Vector2(-4, -4),
				])
				draw_colored_polygon(star, fg)
				draw_circle(c, 3.0, acc)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_fit()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.08, 0.68)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(920, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.028, 0.068, 0.118, 0.97)
	sb.border_color = Color(0.32, 0.60, 0.78, 0.88)
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

	var title := _mk("深海成就", 24, Color(0.86, 0.95, 1.0), 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(title)

	_summary_lbl = _mk("", 14, Color(0.70, 0.86, 0.98), 2)
	_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(_summary_lbl)

	# 顶部总达成率进度条
	var total_bar_bg := ColorRect.new()
	total_bar_bg.color = Color(0.02, 0.05, 0.09, 0.95)
	total_bar_bg.custom_minimum_size = Vector2(0, 8)
	root_vb.add_child(total_bar_bg)

	_total_bar_fill = ColorRect.new()
	_total_bar_fill.color = Color(1.0, 0.84, 0.42, 0.96)
	_total_bar_fill.anchor_left = 0.0
	_total_bar_fill.anchor_top = 0.0
	_total_bar_fill.anchor_bottom = 1.0
	_total_bar_fill.anchor_right = 0.0
	total_bar_bg.add_child(_total_bar_fill)

	# 分类筛选页签（参考戴夫图鉴页签）
	var tab_hb := HBoxContainer.new()
	tab_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hb.add_theme_constant_override("separation", 10)
	root_vb.add_child(tab_hb)

	for ci in CATEGORIES.size():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(108, 30)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_tab_pressed.bind(ci))
		tab_hb.add_child(btn)
		_tab_btns.append(btn)

	# 主体：双列成就卡片滚动区
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(872, 412)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_vb.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)

	for ach: Dictionary in SkinCatalog.ACHIEVEMENTS:
		var aid := String(ach["id"])
		var tag := String(ach.get("tag", "历程"))

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(422, 86)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.05, 0.10, 0.17, 0.90)
		csb.border_color = Color(0.22, 0.42, 0.58, 0.60)
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(8)
		csb.content_margin_left = 12
		csb.content_margin_right = 12
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", csb)
		_grid.add_child(card)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)

		var badge := BadgeIcon.new(tag)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(badge)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info_vb.add_theme_constant_override("separation", 3)
		info_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(info_vb)

		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 8)
		top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_vb.add_child(top_row)

		var name_lbl := _mk(String(ach["name"]), 16, Color(0.90, 0.95, 1.0), 2)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(name_lbl)

		var tag_lbl := _mk("[%s]" % tag, 12, Color(0.58, 0.78, 0.92), 2)
		top_row.add_child(tag_lbl)

		var status_lbl := _mk("", 12, Color(0.62, 0.80, 0.92), 2)
		top_row.add_child(status_lbl)

		var desc_lbl := _mk(String(ach["desc"]), 12, Color(0.72, 0.83, 0.92), 2)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vb.add_child(desc_lbl)

		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 8)
		bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_vb.add_child(bar_row)

		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.02, 0.05, 0.10, 0.95)
		bar_bg.custom_minimum_size = Vector2(0, 7)
		bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_row.add_child(bar_bg)

		var bar_fill := ColorRect.new()
		bar_fill.color = Color(0.36, 0.78, 0.96, 0.95)
		bar_fill.anchor_left = 0.0
		bar_fill.anchor_top = 0.0
		bar_fill.anchor_bottom = 1.0
		bar_fill.anchor_right = 0.0
		bar_bg.add_child(bar_fill)

		var prog_lbl := _mk("", 12, Color(0.72, 0.86, 0.96), 2)
		prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		prog_lbl.custom_minimum_size = Vector2(72, 0)
		bar_row.add_child(prog_lbl)

		_cards.append({
			"ach_id": aid,
			"tag": tag,
			"card": card,
			"badge": badge,
			"name_lbl": name_lbl,
			"tag_lbl": tag_lbl,
			"status_lbl": status_lbl,
			"desc_lbl": desc_lbl,
			"bar_fill": bar_fill,
			"prog_lbl": prog_lbl,
		})

	var hint := _mk("←→ / 点击 切换分类　↑↓ / 滚轮 浏览列表　ESC / 回车 返回设置", 13, Color(0.56, 0.70, 0.84), 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vb.add_child(hint)

	refresh()


func _fit() -> void:
	size = get_viewport_rect().size


func open(_initial_art_id: String = "") -> void:
	visible = true
	_cat_idx = 0
	if _scroll != null:
		_scroll.scroll_vertical = 0
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
	var pct := roundi(100.0 * float(done_ach) / float(maxi(1, total_ach)))
	var next_hint := "全部造型已达标"
	for art: Dictionary in SkinCatalog.ARTWORKS:
		var req := int(art.get("unlock_achievements", 0))
		if done_ach < req:
			next_hint = "再解锁 %d 项可在「换装」点亮「%s」" % [req - done_ach, String(art["name"])]
			break

	_summary_lbl.text = "成就达成 %d / %d（%d%%）　·　%s　·　累计 %d m · 擦身 %d 次 · 冲刺 %d 次" % [
		done_ach, total_ach, pct, next_hint,
		int(Progress.stats["total_dist_m"]),
		int(Progress.stats["total_near_misses"]),
		int(Progress.stats["total_dashes"]),
	]
	_total_bar_fill.anchor_right = clampf(float(done_ach) / float(maxi(1, total_ach)), 0.0, 1.0)

	# 刷新分类页签计数与高亮
	for ci in CATEGORIES.size():
		var cat := String(CATEGORIES[ci])
		var cat_total := 0
		var cat_done := 0
		for c: Dictionary in _cards:
			if cat == "全部" or String(c["tag"]) == cat:
				cat_total += 1
				if Progress.is_achievement_unlocked(String(c["ach_id"])):
					cat_done += 1
		var btn := _tab_btns[ci]
		btn.text = "%s (%d/%d)" % [cat, cat_done, cat_total] if cat != "全部" else "全部 (%d)" % cat_total
		var on := (ci == _cat_idx)
		var tsb := StyleBoxFlat.new()
		tsb.set_border_width_all(1)
		tsb.set_corner_radius_all(6)
		tsb.content_margin_left = 10
		tsb.content_margin_right = 10
		tsb.content_margin_top = 4
		tsb.content_margin_bottom = 4
		if on:
			tsb.bg_color = Color(0.14, 0.27, 0.42, 0.96)
			tsb.border_color = Color(1.0, 0.85, 0.45, 0.95)
			btn.add_theme_color_override("font_color", Color(1.0, 0.90, 0.56))
		else:
			tsb.bg_color = Color(0.05, 0.11, 0.19, 0.86)
			tsb.border_color = Color(0.24, 0.44, 0.60, 0.58)
			btn.add_theme_color_override("font_color", Color(0.74, 0.86, 0.96))
		btn.add_theme_stylebox_override("normal", tsb)
		btn.add_theme_stylebox_override("hover", tsb)
		btn.add_theme_stylebox_override("pressed", tsb)

	var active_cat := String(CATEGORIES[_cat_idx])
	for c: Dictionary in _cards:
		var card := c["card"] as PanelContainer
		var tag := String(c["tag"])
		var show_card := (active_cat == "全部" or tag == active_cat)
		card.visible = show_card
		if not show_card:
			continue

		var aid := String(c["ach_id"])
		var pr := Progress.achievement_progress(aid)
		var done := bool(pr["done"])
		(c["badge"] as BadgeIcon).set_state(done)

		var csb := card.get_theme_stylebox("panel") as StyleBoxFlat
		var name_lbl := c["name_lbl"] as Label
		var status_lbl := c["status_lbl"] as Label
		var desc_lbl := c["desc_lbl"] as Label
		var bar_fill := c["bar_fill"] as ColorRect
		var prog_lbl := c["prog_lbl"] as Label

		bar_fill.anchor_right = float(pr["ratio"])
		prog_lbl.text = String(pr["text"])

		if done:
			csb.bg_color = Color(0.07, 0.16, 0.24, 0.94)
			csb.border_color = Color(0.92, 0.78, 0.36, 0.86)
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.50))
			desc_lbl.add_theme_color_override("font_color", Color(0.84, 0.92, 0.98))
			status_lbl.text = "✓ 已达成"
			status_lbl.add_theme_color_override("font_color", Color(0.52, 0.96, 0.68))
			bar_fill.color = Color(0.46, 0.92, 0.64, 0.98)
			prog_lbl.add_theme_color_override("font_color", Color(0.52, 0.96, 0.70))
		else:
			csb.bg_color = Color(0.04, 0.09, 0.16, 0.88)
			csb.border_color = Color(0.22, 0.40, 0.56, 0.55)
			name_lbl.add_theme_color_override("font_color", Color(0.84, 0.91, 0.98))
			desc_lbl.add_theme_color_override("font_color", Color(0.64, 0.76, 0.88))
			status_lbl.text = "未解锁"
			status_lbl.add_theme_color_override("font_color", Color(0.54, 0.66, 0.78))
			bar_fill.color = Color(0.36, 0.78, 0.96, 0.95)
			prog_lbl.add_theme_color_override("font_color", Color(0.72, 0.86, 0.96))


func _on_tab_pressed(ci: int) -> void:
	if _cat_idx == ci:
		return
	_cat_idx = ci
	if _scroll != null:
		_scroll.scroll_vertical = 0
	refresh()
	AudioManager.play_sfx("ui_move", -2.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_left"):
		_cat_idx = wrapi(_cat_idx - 1, 0, CATEGORIES.size())
		if _scroll != null:
			_scroll.scroll_vertical = 0
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_cat_idx = wrapi(_cat_idx + 1, 0, CATEGORIES.size())
		if _scroll != null:
			_scroll.scroll_vertical = 0
		refresh()
		AudioManager.play_sfx("ui_move", -2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_up"):
		if _scroll != null:
			_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - 96)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		if _scroll != null:
			_scroll.scroll_vertical += 96
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
