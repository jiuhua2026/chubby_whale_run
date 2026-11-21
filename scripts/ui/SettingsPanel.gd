extends Control
class_name SettingsPanel
## 设置界面：半透明遮罩 + 居中面板，键盘和鼠标都能操作。
##
## 三个开关都是**真的接在系统上**的（见 `Settings` 的注释）：
##   主音量 → Master 总线；屏幕震动 → `Main` 的震幅倍率；显示模式 → DisplayServer。
##
## 交互：
##   ↑↓ 选行　←→ 调整　回车/空格 切换　ESC 返回
##   鼠标：移到某行即选中，点 ◀ ▶ 调整

signal closed
signal replay_intro_requested

const BASE_ROWS := [
	{"id": "bgm_volume", "name": "音乐音量"},
	{"id": "sfx_volume", "name": "音效音量"},
	{"id": "shake", "name": "屏幕震动"},
	{"id": "fullscreen", "name": "显示模式"},
]
const REPLAY_ROW := {"id": "intro_replay", "name": "开场动画"}
const SHAKE_TEXTS := ["关", "50%", "100%"]
const SHAKE_VALUES := [0.0, 0.5, 1.0]

## 只有主菜单打开的设置才显示「重温开场」；局内暂停里的设置隐藏该项，防跑酷中途误触。
@export var allow_intro_replay := false

var _rows: Array[Dictionary] = []
var _sel := 0
var _names: Array[Label] = []
var _values: Array[Label] = []


func _ready() -> void:
	_rows.clear()
	for r: Dictionary in BASE_ROWS:
		_rows.append(r)
	if allow_intro_replay:
		_rows.append(REPLAY_ROW)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# ⚠ **必做**：这个 Control 直接挂在 `CanvasLayer` 下，进树那一刻 `size` 还是 (0,0)，
	#   于是遮罩铺不开、面板按"父矩形中心"算出来落在左上角（实测就是这样）。
	#   显式定尺寸 + 延后一帧再定一次，并跟随窗口尺寸变化。
	_fit()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

	# 1. 遮罩：吃掉背后的所有点击，同时把画面压暗
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.08, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点面板**外**任意位置 = 关闭（比记着按 ESC 顺手）
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	# 2. 居中面板
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.030, 0.070, 0.120, 0.94)
	sb.border_color = Color(0.32, 0.58, 0.74, 0.80)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	# ⚠ **必须显式 STOP**：否则点面板内部（比如调音量的 ◀ ▶）会穿透到遮罩，
	#   变成"一调音量面板就自己关了"。默认值不可靠，写死。
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := _mk("设置", 26, Color(0.80, 0.92, 1.0), 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(_spacer(8))

	# 3. 设置行：名字 + ◀ 值 ▶（重温开场为动作行，点整行/回车/右箭头即可触发）
	for i in _rows.size():
		var row_id := String(_rows[i]["id"])
		var is_action := row_id == "intro_replay"
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		vb.add_child(box)

		var nm := _mk(_rows[i]["name"], 20, Color(0.72, 0.82, 0.92), 3)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.custom_minimum_size = Vector2(160, 0)
		box.add_child(nm)
		_names.append(nm)

		var fill := Control.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(fill)

		var left := _mk("" if is_action else "◀", 20, Color(0.62, 0.80, 0.92), 2)
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE if is_action else Control.MOUSE_FILTER_STOP
		if not is_action:
			left.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			left.gui_input.connect(_on_arrow.bind(i, -1))
		box.add_child(left)

		var val := _mk("", 20, Color(0.90, 0.95, 1.0), 3)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.custom_minimum_size = Vector2(96, 0)
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(val)
		_values.append(val)

		var right := _mk("▶", 20, Color(0.62, 0.80, 0.92), 2)
		right.mouse_filter = Control.MOUSE_FILTER_STOP
		right.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		right.gui_input.connect(_on_arrow.bind(i, 1))
		box.add_child(right)

		if is_action:
			box.gui_input.connect(_on_action_row_input.bind(i))
		box.mouse_entered.connect(_on_hover.bind(i))

	vb.add_child(_spacer(10))
	var hint := _mk("↑↓ 选择　←→ 调整　回车切换　ESC 返回", 13,
		Color(0.56, 0.70, 0.84), 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

	_refresh()


func _fit() -> void:
	size = get_viewport_rect().size


func open() -> void:
	visible = true
	_sel = 0
	_refresh()
	AudioManager.play_sfx("ui_confirm", 0.0)


func close() -> void:
	if not visible:
		return
	visible = false
	Settings.save_cfg()
	AudioManager.play_sfx("ui_confirm", -2.0)
	closed.emit()


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
		_sel = wrapi(_sel + (1 if event.is_action_pressed("menu_down") else -1), 0, _rows.size())
		_refresh()
		AudioManager.play_sfx("ui_move", -4.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		_adjust(_sel, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_adjust(_sel, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		# 回车 = 把这一项"往后拨一格"（范围和右箭头一致）
		_adjust(_sel, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back_to_menu"):
		close()
		get_viewport().set_input_as_handled()


## 点到遮罩（= 面板以外）就关闭。左右中键都算。
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			close()
			get_viewport().set_input_as_handled()


func _on_hover(i: int) -> void:
	if _sel == i:
		return
	_sel = i
	_refresh()


func _on_arrow(event: InputEvent, i: int, dir: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_sel = i
			_adjust(i, dir)
			get_viewport().set_input_as_handled()


func _on_action_row_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_sel = i
			_adjust(i, 1)
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 值
func _adjust(i: int, dir: int) -> void:
	match _rows[i]["id"]:
		"bgm_volume":
			Settings.bgm_volume = clampf(snappedf(Settings.bgm_volume + 0.1 * float(dir), 0.01), 0.0, 1.0)
			Settings.apply_volume()
		"sfx_volume":
			Settings.sfx_volume = clampf(snappedf(Settings.sfx_volume + 0.1 * float(dir), 0.01), 0.0, 1.0)
			Settings.apply_volume()
		"shake":
			var idx := _shake_index()
			idx = wrapi(idx + dir, 0, SHAKE_VALUES.size())
			Settings.shake_scale = float(SHAKE_VALUES[idx])
		"fullscreen":
			Settings.fullscreen = not Settings.fullscreen
			Settings.apply_display()
		"intro_replay":
			Settings.save_cfg()
			visible = false
			AudioManager.play_sfx("ui_confirm", -2.0)
			closed.emit()
			replay_intro_requested.emit()
			return
	Settings.save_cfg()
	_refresh()
	AudioManager.play_sfx("ui_move", -4.0)


func _shake_index() -> int:
	var best := 0
	for i in SHAKE_VALUES.size():
		if absf(float(SHAKE_VALUES[i]) - Settings.shake_scale) < 0.01:
			return i
	return best


func _refresh() -> void:
	for i in _rows.size():
		var on := i == _sel
		_names[i].add_theme_color_override("font_color",
			Color(1.0, 0.86, 0.50) if on else Color(0.72, 0.82, 0.92))
		_values[i].add_theme_color_override("font_color",
			Color(1.0, 0.94, 0.78) if on else Color(0.84, 0.92, 1.0))
		_values[i].text = _value_text(_rows[i]["id"])


func _value_text(id: String) -> String:
	match id:
		"bgm_volume":
			return "%d%%" % roundi(Settings.bgm_volume * 100.0)
		"sfx_volume":
			return "%d%%" % roundi(Settings.sfx_volume * 100.0)
		"shake":
			return SHAKE_TEXTS[_shake_index()]
		"fullscreen":
			return "全屏" if Settings.fullscreen else "窗口"
		"intro_replay":
			return "重温"
	return ""


# ---------------------------------------------------------------- 小工具
func _mk(text: String, size: int, col: Color, outline: int = 3) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.03, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", outline)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
