class_name HUD
extends CanvasLayer

## 像素风深海 HUD：去边框化左上浮标 + 渐变预警条 + 沉船石板死亡结算面板

var _hud_box: VBoxContainer
var _lbl_dist_val: Label
var _lbl_score_val: Label
var _bar_charge: ChargeBar
var _badge_space: PanelContainer
var _lbl_charge_state: Label
var _lbl_perf: Label

var _lbl_mode: Label
var _lbl_test: Label

var _warn_box: PanelContainer
var _warn_sb_amber: StyleBoxTexture
var _warn_sb_crimson: StyleBoxTexture
var _warn_icon: TextureRect
var _lbl_warn: Label
var _tex_warn_amber: Texture2D
var _tex_warn_chase: Texture2D
var _warn_chase := false
var _warn_t := 0.0

var _end_root: Control
var _end_dim: ColorRect
var _end_wrap: Control
var _end_card: PanelContainer
var _end_sb: StyleBoxTexture
var _badge_cause: TextureRect
var _tex_badge_bite: Texture2D
var _tex_badge_wall: Texture2D
var _tex_badge_chasm: Texture2D

var _lbl_title: Label
var _lbl_end_dist: Label
var _lbl_end_dist_best: Label
var _badge_dist_new: PanelContainer
var _lbl_end_score: Label
var _lbl_end_score_best: Label
var _badge_score_new: PanelContainer
var _lbl_end_note: Label
var _panel_delay := 0.0


class ChargeBar extends Control:
	var max_charge := 3
	var charge := 0
	var dashing := false
	var dash_ratio := 0.0
	var tex_base: Texture2D
	var tex_overlay: Texture2D
	var _anim_t := 0.0

	const TUBE_W := 136.0
	const TUBE_H := 26.0
	const CELL_X0 := 10.0
	const CELL_Y0 := 6.0
	const CELL_W := 36.0
	const CELL_H := 14.0
	const CELL_STRIDE := 40.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		_anim_t += delta
		queue_redraw()

	func _draw() -> void:
		if tex_base == null or tex_overlay == null:
			return
		draw_texture_rect(tex_base, Rect2(0.0, 0.0, TUBE_W, TUBE_H), false)

		var n := maxi(1, max_charge)
		var full := (charge >= n) or dashing
		var row_cols := [
			Color(0.94, 1.00, 1.00) if full else Color(0.55, 0.94, 1.00),
			Color(0.58, 0.98, 1.00) if full else Color(0.26, 0.78, 0.96),
			Color(0.22, 0.86, 1.00) if full else Color(0.14, 0.58, 0.86),
			Color(0.22, 0.86, 1.00) if full else Color(0.14, 0.58, 0.86),
			Color(0.22, 0.86, 1.00) if full else Color(0.14, 0.58, 0.86),
			Color(0.12, 0.62, 0.90) if full else Color(0.10, 0.42, 0.70),
			Color(0.08, 0.42, 0.72) if full else Color(0.06, 0.28, 0.50),
		]

		var sweep_phase := fmod(_anim_t, 1.65) / 0.52
		var sweep_active := full and not dashing and sweep_phase < 1.0
		var sweep_x := floorf(lerpf(6.0, 134.0, sweep_phase) * 0.5) * 2.0

		for i in range(n):
			var ratio := 0.0
			if dashing:
				ratio = clampf(dash_ratio * n - i, 0.0, 1.0)
			elif i < charge:
				ratio = 1.0
			if ratio <= 0.0:
				continue

			var x0 := CELL_X0 + i * CELL_STRIDE
			var px_w := floorf((CELL_W * ratio) * 0.5) * 2.0
			if px_w <= 0.0:
				continue

			for r in range(7):
				draw_rect(Rect2(x0, CELL_Y0 + r * 2.0, px_w, 2.0), row_cols[r])

			# 固定 45° 液晶斜切反光 + 满能周期性亮青扫光
			for r in range(1, 5):
				var fx := x0 + 6.0 - float(r - 1) * 2.0
				if fx >= x0 and fx + 4.0 <= x0 + px_w:
					draw_rect(Rect2(fx, CELL_Y0 + r * 2.0, 4.0, 2.0), Color(0.92, 1.0, 1.0, 0.28))

				if sweep_active:
					var sx := sweep_x - float(r) * 2.0
					var sl := maxf(sx, x0)
					var sr := minf(sx + 6.0, x0 + px_w)
					if sr > sl:
						draw_rect(Rect2(sl, CELL_Y0 + r * 2.0, sr - sl, 2.0), Color(1.0, 1.0, 1.0, 0.65))

			# 冲刺平滑消耗时在右截断前沿绘制 2px 纯白亮边
			if dashing and ratio < 1.0 and px_w >= 2.0:
				draw_rect(Rect2(x0 + px_w - 2.0, CELL_Y0, 2.0, CELL_H), Color(1.0, 1.0, 1.0, 0.96))

		draw_texture_rect(tex_overlay, Rect2(0.0, 0.0, TUBE_W, TUBE_H), false)

		if charge >= n and not dashing:
			var glow_a := 0.30 + 0.20 * sin(_anim_t * 5.0)
			draw_rect(Rect2(8.0, 4.0, 120.0, 18.0), Color(0.55, 0.96, 1.0, glow_a), false, 2.0)


static func _load_tex(path: String) -> Texture2D:
	return load(path) as Texture2D


static func _make_9slice(
	tex: Texture2D,
	ml: float, mt: float, mr: float, mb: float,
	cl: float, ct: float, cr: float, cb: float,
	stretch_x: StyleBoxTexture.AxisStretchMode = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH,
	stretch_y: StyleBoxTexture.AxisStretchMode = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = ml
	sb.texture_margin_top = mt
	sb.texture_margin_right = mr
	sb.texture_margin_bottom = mb
	sb.content_margin_left = cl
	sb.content_margin_top = ct
	sb.content_margin_right = cr
	sb.content_margin_bottom = cb
	sb.axis_stretch_horizontal = stretch_x
	sb.axis_stretch_vertical = stretch_y
	return sb


static func _make_label(
	txt: String,
	size: int,
	color: Color,
	outline_px: int = 4,
	shadow_px: int = 2
) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.96))
	l.add_theme_constant_override("outline_size", outline_px)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", shadow_px)
	return l


static func _make_keycap(text: String, tex_keycap: Texture2D, font_px: int = 14) -> PanelContainer:
	var box := PanelContainer.new()
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sb := _make_9slice(tex_keycap, 10.0, 10.0, 10.0, 12.0, 9.0, 3.0, 9.0, 6.0)
	box.add_theme_stylebox_override("panel", sb)
	var lbl := _make_label(text, font_px, Color(0.94, 0.97, 1.0), 3, 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	return box


static func _make_new_badge() -> PanelContainer:
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.74, 0.18, 0.95)
	sb.border_color = Color(0.18, 0.09, 0.02, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "NEW!"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.14, 0.07, 0.02))
	badge.add_child(lbl)
	badge.visible = false
	return badge


func _ready() -> void:
	layer = 10
	_build()
	GameState.ready_started.connect(_on_ready_started)
	GameState.run_ended.connect(_on_run_ended)
	GameState.run_started.connect(_on_run_started)
	GameState.menu_opened.connect(_on_menu_opened)
	get_viewport().size_changed.connect(_fit_end_root)
	_fit_end_root()
	call_deferred("_fit_end_root")


func _fit_end_root() -> void:
	if _end_root == null or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var sz := vp.get_visible_rect().size
	if sz.x > 0.0 and sz.y > 0.0:
		_end_root.set_position(Vector2.ZERO)
		_end_root.set_size(sz)
		if _end_dim != null:
			_end_dim.set_position(Vector2.ZERO)
			_end_dim.set_size(sz)
		if _end_wrap != null:
			var w := _end_wrap.custom_minimum_size.x
			var h := _end_wrap.custom_minimum_size.y
			_end_wrap.set_position(Vector2((sz.x - w) * 0.5, (sz.y - h) * 0.5 - 8.0))
			_end_wrap.set_size(Vector2(w, h))
			if _end_card != null:
				_end_card.set_position(Vector2(0.0, 22.0))
				_end_card.set_size(Vector2(w, h - 22.0))
			if _badge_cause != null:
				_badge_cause.set_position(Vector2((w - 52.0) * 0.5, 0.0))
				_badge_cause.set_size(Vector2(52.0, 44.0))


func _build() -> void:
	var tex_panel := _load_tex("res://sprites/ui/panel_frame.png")
	var tex_slot := _load_tex("res://sprites/ui/stat_slot.png")
	var tex_keycap := _load_tex("res://sprites/ui/keycap_frame.png")
	var tex_keycap_cyan := _load_tex("res://sprites/ui/keycap_cyan_frame.png")
	var tex_ribbon_amber := _load_tex("res://sprites/ui/warn_ribbon_amber.png")
	var tex_ribbon_crimson := _load_tex("res://sprites/ui/warn_ribbon_crimson.png")
	var tex_tube_base := _load_tex("res://sprites/ui/dash_tube_base.png")
	var tex_tube_overlay := _load_tex("res://sprites/ui/dash_tube_overlay.png")
	_tex_warn_amber = _load_tex("res://sprites/ui/icon_warn_amber.png")
	_tex_warn_chase = _load_tex("res://sprites/ui/icon_warn_chase.png")
	_tex_badge_bite = _load_tex("res://sprites/ui/badge_bite.png")
	_tex_badge_wall = _load_tex("res://sprites/ui/badge_wall.png")
	_tex_badge_chasm = _load_tex("res://sprites/ui/badge_chasm.png")

	# ── 1. 左上角无框浮标（直白中文距离/得分 + 海晶冲刺槽） ───────────────────────
	_hud_box = VBoxContainer.new()
	_hud_box.position = Vector2(20, 14)
	_hud_box.add_theme_constant_override("separation", 8)
	add_child(_hud_box)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 22)
	_hud_box.add_child(stats_row)

	var dist_pair := HBoxContainer.new()
	dist_pair.add_theme_constant_override("separation", 7)
	stats_row.add_child(dist_pair)
	var lbl_dist_cap := _make_label("距离", 16, Color(0.68, 0.86, 0.98), 4, 1)
	lbl_dist_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dist_pair.add_child(lbl_dist_cap)
	_lbl_dist_val = _make_label("0 m", 26, Color(0.96, 0.98, 1.0), 5, 2)
	_lbl_dist_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dist_pair.add_child(_lbl_dist_val)

	var score_pair := HBoxContainer.new()
	score_pair.add_theme_constant_override("separation", 7)
	stats_row.add_child(score_pair)
	var lbl_score_cap := _make_label("得分", 16, Color(0.94, 0.80, 0.42), 4, 1)
	lbl_score_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_pair.add_child(lbl_score_cap)
	_lbl_score_val = _make_label("0", 26, Color(1.0, 0.86, 0.30), 5, 2)
	_lbl_score_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_pair.add_child(_lbl_score_val)

	var charge_row := HBoxContainer.new()
	charge_row.add_theme_constant_override("separation", 8)
	_hud_box.add_child(charge_row)

	_bar_charge = ChargeBar.new()
	_bar_charge.tex_base = tex_tube_base
	_bar_charge.tex_overlay = tex_tube_overlay
	_bar_charge.custom_minimum_size = Vector2(ChargeBar.TUBE_W, ChargeBar.TUBE_H)
	_bar_charge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	charge_row.add_child(_bar_charge)

	_badge_space = _make_keycap("SPACE", tex_keycap_cyan, 12)
	_badge_space.visible = false
	_badge_space.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	charge_row.add_child(_badge_space)

	_lbl_charge_state = _make_label("冲刺中!", 15, Color(0.70, 0.98, 1.0), 4, 1)
	_lbl_charge_state.visible = false
	_lbl_charge_state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	charge_row.add_child(_lbl_charge_state)

	_lbl_perf = _make_label("", 12, Color(0.68, 0.86, 0.72), 3, 1)
	_lbl_perf.visible = false
	_hud_box.add_child(_lbl_perf)

	# ── 2. 右上角无框模式标 + 沙盒热键说明 ────────────────────────────────────────
	_lbl_mode = _make_label("正常模式", 16, Color(0.70, 0.85, 0.96, 0.84), 4, 1)
	_lbl_mode.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lbl_mode.offset_left = -220
	_lbl_mode.offset_right = -22
	_lbl_mode.offset_top = 18
	_lbl_mode.offset_bottom = 44
	_lbl_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_lbl_mode)

	_lbl_test = _make_label("", 13, Color(0.75, 0.95, 0.85, 0.88), 3, 1)
	_lbl_test.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lbl_test.offset_left = -520
	_lbl_test.offset_right = -22
	_lbl_test.offset_top = 52
	_lbl_test.offset_bottom = 270
	_lbl_test.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_test.visible = false
	add_child(_lbl_test)

	# ── 3. 顶部居中：水平羽化渐变海渊预警丝带 ────────────────────────────────────
	_warn_box = PanelContainer.new()
	_warn_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_warn_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warn_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_warn_box.offset_top = 14
	_warn_box.offset_bottom = 58
	_warn_sb_amber = _make_9slice(
		tex_ribbon_amber, 84.0, 8.0, 84.0, 8.0, 56.0, 6.0, 56.0, 6.0
	)
	_warn_sb_crimson = _make_9slice(
		tex_ribbon_crimson, 84.0, 8.0, 84.0, 8.0, 56.0, 6.0, 56.0, 6.0
	)
	_warn_box.add_theme_stylebox_override("panel", _warn_sb_amber)
	_warn_box.visible = false
	add_child(_warn_box)

	var warn_row := HBoxContainer.new()
	warn_row.add_theme_constant_override("separation", 10)
	warn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_warn_box.add_child(warn_row)

	_warn_icon = TextureRect.new()
	_warn_icon.texture = _tex_warn_amber
	_warn_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_warn_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_warn_icon.custom_minimum_size = Vector2(28, 28)
	_warn_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	warn_row.add_child(_warn_icon)

	_lbl_warn = _make_label("", 21, Color(1.0, 0.92, 0.44), 5, 2)
	_lbl_warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warn_row.add_child(_lbl_warn)

	# ── 4. 死亡结算弹窗（深海沉船石板 + 顶部死因徽章 + 凹槽记录 + 像素键帽） ────────
	_end_root = Control.new()
	_end_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_root.visible = false
	add_child(_end_root)

	_end_dim = ColorRect.new()
	_end_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_dim.color = Color(0.01, 0.03, 0.08, 0.60)
	_end_root.add_child(_end_dim)

	_end_wrap = Control.new()
	_end_wrap.custom_minimum_size = Vector2(548, 324)
	_end_root.add_child(_end_wrap)

	_end_card = PanelContainer.new()
	_end_card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_end_sb = _make_9slice(
		tex_panel, 28.0, 28.0, 28.0, 28.0, 34.0, 34.0, 34.0, 28.0
	)
	_end_card.add_theme_stylebox_override("panel", _end_sb)
	_end_wrap.add_child(_end_card)

	_badge_cause = TextureRect.new()
	_badge_cause.texture = _tex_badge_wall
	_badge_cause.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_badge_cause.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_badge_cause.z_index = 2
	_end_wrap.add_child(_badge_cause)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_end_card.add_child(vbox)

	_lbl_title = _make_label("", 28, Color(1.0, 0.55, 0.45), 5, 2)
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_lbl_title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(cols)

	# 左凹槽：本次距离
	var slot_dist := PanelContainer.new()
	slot_dist.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot_dist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_dist.add_theme_stylebox_override("panel", _make_9slice(
		tex_slot, 12.0, 12.0, 12.0, 12.0, 16.0, 12.0, 16.0, 12.0
	))
	cols.add_child(slot_dist)

	var dist_box := VBoxContainer.new()
	dist_box.add_theme_constant_override("separation", 4)
	dist_box.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_dist.add_child(dist_box)

	var dist_cap := _make_label("本次距离", 14, Color(0.62, 0.82, 0.96), 3, 1)
	dist_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_box.add_child(dist_cap)

	_lbl_end_dist = _make_label("0 m", 30, Color(0.95, 0.98, 1.0), 5, 2)
	_lbl_end_dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_box.add_child(_lbl_end_dist)

	var dist_best_row := HBoxContainer.new()
	dist_best_row.add_theme_constant_override("separation", 6)
	dist_best_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dist_box.add_child(dist_best_row)
	_lbl_end_dist_best = _make_label("最佳 0 m", 13, Color(0.56, 0.72, 0.86), 2, 1)
	dist_best_row.add_child(_lbl_end_dist_best)
	_badge_dist_new = _make_new_badge()
	dist_best_row.add_child(_badge_dist_new)

	# 右凹槽：本次得分
	var slot_score := PanelContainer.new()
	slot_score.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_score.add_theme_stylebox_override("panel", _make_9slice(
		tex_slot, 12.0, 12.0, 12.0, 12.0, 16.0, 12.0, 16.0, 12.0
	))
	cols.add_child(slot_score)

	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 4)
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_score.add_child(score_box)

	var score_cap := _make_label("本次得分", 14, Color(0.94, 0.80, 0.44), 3, 1)
	score_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(score_cap)

	_lbl_end_score = _make_label("0", 30, Color(1.0, 0.85, 0.30), 5, 2)
	_lbl_end_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(_lbl_end_score)

	var score_best_row := HBoxContainer.new()
	score_best_row.add_theme_constant_override("separation", 6)
	score_best_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_box.add_child(score_best_row)
	_lbl_end_score_best = _make_label("最佳 0", 13, Color(0.56, 0.72, 0.86), 2, 1)
	score_best_row.add_child(_lbl_end_score_best)
	_badge_score_new = _make_new_badge()
	score_best_row.add_child(_badge_score_new)

	_lbl_end_note = _make_label("练习模式不计入最佳纪录", 13, Color(0.62, 0.78, 0.90), 2, 1)
	_lbl_end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_end_note.visible = false
	vbox.add_child(_lbl_end_note)

	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 28)
	hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hint_row)

	var r_pair := HBoxContainer.new()
	r_pair.add_theme_constant_override("separation", 8)
	r_pair.add_child(_make_keycap("R", tex_keycap, 15))
	r_pair.add_child(_make_label("重新开始", 16, Color(0.92, 0.96, 1.0), 3, 1))
	hint_row.add_child(r_pair)

	var esc_pair := HBoxContainer.new()
	esc_pair.add_theme_constant_override("separation", 8)
	esc_pair.add_child(_make_keycap("ESC", tex_keycap, 14))
	esc_pair.add_child(_make_label("回主界面", 16, Color(0.92, 0.96, 1.0), 3, 1))
	hint_row.add_child(esc_pair)


func _on_run_started() -> void:
	_panel_delay = 0.0
	_end_root.visible = false
	_fit_end_root()


func _on_ready_started() -> void:
	_panel_delay = 0.0
	_end_root.visible = false
	_warn_box.visible = false
	_hud_box.visible = false
	_lbl_mode.visible = false


func _on_menu_opened() -> void:
	_panel_delay = 0.0
	_end_root.visible = false
	_warn_box.visible = false
	_hud_box.visible = false
	_lbl_mode.visible = false
	_lbl_test.visible = false


func _on_run_ended(reason: String, distance: float, score: int) -> void:
	_warn_box.visible = false
	var title_col := Color(1.0, 0.55, 0.45)
	var badge_tex := _tex_badge_wall
	_lbl_title.text = "被追上了"
	match reason:
		"caught_by_chaser":
			_lbl_title.text = "黑鲸娘咬住了你"
			title_col = Color(1.0, 0.46, 0.50)
			badge_tex = _tex_badge_bite
		"caught_by_wall":
			_lbl_title.text = "深渊水压吞没了你"
			title_col = Color(0.48, 0.88, 1.0)
			badge_tex = _tex_badge_wall
		"fell_into_chasm":
			_lbl_title.text = "坠入了无底深渊"
			title_col = Color(1.0, 0.68, 0.36)
			badge_tex = _tex_badge_chasm
	_lbl_title.add_theme_color_override("font_color", title_col)
	_badge_cause.texture = badge_tex

	var dist_m := int(roundf(distance / 64.0))
	_lbl_end_dist.text = "%d m" % dist_m
	_lbl_end_score.text = "%d" % score

	if GameState.mode == GameState.Mode.NORMAL:
		var rec := Settings.update_records(dist_m, score)
		_lbl_end_dist_best.text = "最佳 %d m" % Settings.best_distance_m
		_lbl_end_score_best.text = "最佳 %d" % Settings.best_score
		_lbl_end_dist_best.visible = true
		_lbl_end_score_best.visible = true
		_badge_dist_new.visible = bool(rec["new_dist"])
		_badge_score_new.visible = bool(rec["new_score"])
		_lbl_end_note.visible = false
	else:
		_lbl_end_dist_best.visible = false
		_lbl_end_score_best.visible = false
		_badge_dist_new.visible = false
		_badge_score_new.visible = false
		_lbl_end_note.text = "练习模式不计入最佳纪录"
		_lbl_end_note.visible = true

	_fit_end_root()
	# 被黑鲸娘咬死时延迟 0.45s 播完扑咬抓痕再弹窗
	_panel_delay = 0.45 if reason == "caught_by_chaser" else 0.0
	if _panel_delay <= 0.0:
		_end_root.visible = true


func _process(delta: float) -> void:
	if _badge_space.visible:
		var sp := 0.5 + 0.5 * sin(_bar_charge._anim_t * 5.0)
		var lbl := _badge_space.get_child(0) as Label
		if lbl != null:
			lbl.add_theme_color_override("font_color", Color(0.65, 0.96, 1.0).lerp(Color.WHITE, sp))

	if _warn_box.visible and _warn_chase:
		_warn_t += delta
		var p := 0.5 + 0.5 * sin(_warn_t * 9.0)
		_lbl_warn.add_theme_color_override(
			"font_color",
			Color(1.0, 0.42, 0.44).lerp(Color(1.0, 0.88, 0.88), p)
		)
	_warn_box.modulate = Color.WHITE

	if _panel_delay <= 0.0:
		return
	if GameState.phase != GameState.Phase.ENDED:
		_panel_delay = 0.0
		_end_root.visible = false
		return
	_panel_delay -= delta
	if _panel_delay <= 0.0:
		_end_root.visible = true


func is_end_panel_visible() -> bool:
	return _end_root != null and _end_root.visible


func update_live(player: Player, director: ChaseDirector) -> void:
	_hud_box.visible = true
	_lbl_mode.visible = true

	if GameState.is_sandbox():
		_lbl_mode.text = "沙盒模式"
		_lbl_mode.add_theme_color_override("font_color", Color(0.55, 0.95, 0.80, 0.92))
	elif GameState.is_practice():
		_lbl_mode.text = "练习模式"
		_lbl_mode.add_theme_color_override("font_color", Color(0.98, 0.86, 0.52, 0.92))
	else:
		_lbl_mode.text = "正常模式"
		_lbl_mode.add_theme_color_override("font_color", Color(0.70, 0.85, 0.96, 0.80))

	_lbl_dist_val.text = "%.0f m" % (GameState.distance / 64.0)
	_lbl_score_val.text = "%d" % GameState.score

	var mx := GameConfig.dash_charge_max
	_bar_charge.max_charge = mx
	_bar_charge.charge = clampi(player.dash_charge, 0, mx)
	_bar_charge.dashing = player.is_dashing()
	_bar_charge.dash_ratio = player.dash_ratio()
	var ready := player.dash_charge >= mx and not player.is_dashing()
	_badge_space.visible = ready
	_lbl_charge_state.visible = player.is_dashing()

	var fps_txt := "—" if player.debug_anim_fps_raw() <= 0.0 \
		else "%.0f→%.0f" % [player.debug_anim_fps_raw(), player.debug_anim_fps()]
	_lbl_perf.visible = GameState.is_sandbox()
	_lbl_perf.text = "%d fps　动画 %s @ %s　%s" % [
		Engine.get_frames_per_second(),
		player.debug_anim_action(), fps_txt,
		"吸附/身高统一" if GameConfig.anim_fps_snap and GameConfig.anim_uniform_height \
			else ("仅吸附" if GameConfig.anim_fps_snap else "原始")]

	var sandbox := GameState.is_sandbox()
	_lbl_test.visible = sandbox
	if sandbox:
		_lbl_test.text = "\n".join([
			"动作 %s　帧 %d/%d" % [player.debug_anim_action(),
				player.debug_anim_index() + 1, player.debug_anim_count()],
			"离地 %.0f px　纵向速度 %.0f" % [-player.global_position.y, player.velocity.y],
			"",
			", / . 调速（0 = 静止慢放）",
			"[ / ] 跑步循环　; / ' 当前动作上下微调",
			"- 帧率吸附　= 帧身高统一　F3 打印档位体检",
			"↑ 跳　↓ 滑　空格 冲刺　R 重开　ESC 回主界面",
		])

	if sandbox or GameState.is_practice() or GameState.phase != GameState.Phase.RUNNING:
		_warn_box.visible = false
		_warn_chase = false
	elif director.in_chase:
		_warn_chase = true
		_warn_icon.texture = _tex_warn_chase
		_lbl_warn.text = "黑鲸娘正在逼近"
		_warn_box.add_theme_stylebox_override("panel", _warn_sb_crimson)
		_warn_box.visible = true
	else:
		_warn_chase = false
		var cd := director.countdown()
		if cd < 1500.0:
			_warn_icon.texture = _tex_warn_amber
			_lbl_warn.text = "前方 %.0f m 进入追逐段" % (cd / 64.0)
			_lbl_warn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.44))
			_warn_box.add_theme_stylebox_override("panel", _warn_sb_amber)
			_warn_box.visible = true
		else:
			_warn_box.visible = false
