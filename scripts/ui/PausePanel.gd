extends Control
class_name PausePanel
## 暂停界面：遮罩 + 居中面板，两个选项（继续游戏 / 返回主菜单）。
##
## 为什么暂停用 `get_tree().paused`，而不是给 `GameState` 加一个 PAUSED 相位：
##   · 本作里"该停的东西"散落在好几处 —— `Player` 的动画 tick、`DashFx` 的残影发射、
##     黑鲸娘的双正弦浮动，**都不归 `is_running()` 管**。加相位得逐个补门控，
##     漏一个就是"世界半冻结"（人在原地跑、粒子还在飘）；
##   · `paused` 一行停掉整棵树（含 Tween / 粒子），语义只有一处。
## 代价：**暂停后 `Main` 也不再收 `_unhandled_input`** ⇒ "继续 / 返回"必须由本面板自己接，
##   所以 `_ready()` 里必须 `process_mode = ALWAYS`（不能靠父节点继承，父 `CanvasLayer` 是 pausable）。
##
## 交互与 `SettingsPanel` 保持一致：↑↓ 选、回车确认、ESC = 继续，鼠标悬停即选中。
## 样式也复用同一套：遮罩 0.62 + 居中 `PanelContainer`。**不照抄主菜单那套"右上角零背板"**
## —— 那套靠封面右上角亮度 97 撑对比，而跑动画面是暗海底（亮度 13~29），同样的字会读不清。

signal resumed()
signal menu_requested()

const OPTIONS := ["继续游戏", "设置", "返回主菜单"]

var _rows: Array[Label] = []
var _marks: Array[Label] = []
## 遮罩 + 居中面板的容器。打开设置时整块藏起来（见 `_ready()` 第 0 步）。
var _body: Control
var _lbl_info: Label
## 设置面板：挂在本面板下面（**不挂到 `MainMenu` 那边**）。
## `SettingsPanel` 没有本地数值状态 —— 三行都从 `Settings` autoload 现读现写，
## 所以多一个实例不会出现"两份值不同步"；父节点是 ALWAYS，它继承后暂停中也能操作。
var _settings: SettingsPanel
## 设置面板刚被关掉的那一帧。见 `_unhandled_input()` 里的说明。
var _settings_closed_frame := -10
var _sel := 0
## 打开面板的那一帧不接输入。`Main` 和本面板的 `_unhandled_input` **谁先被叫到是不确定的**
## （Godot 按场景树逆序派发，而暂停是在 `Main` 的处理里才生效的）。
## 不挡这一帧，就可能出现"按一下 ESC，面板闪一下就自己继续了"。
var _open_frame := -1


func _ready() -> void:
	# ⚠ **必须自己声明，不能靠继承**：父 `CanvasLayer` 是 pausable，
	#   树一暂停本节点就收不到 `_unhandled_input` —— ESC 按下去毫无反应，等于卡死。
	process_mode = Node.PROCESS_MODE_ALWAYS

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# ⚠ **必做**：这个 Control 直接挂在 `CanvasLayer` 下，进树那一刻 `size` 还是 (0,0)，
	#   遮罩铺不开、面板按"父矩形中心"算出来落在左上角（这个坑踩过两次）。
	_fit()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

	# 0. 面板本体（遮罩 + 居中面板）全挂在 `_body` 下。
	#    打开设置时整块收起来 —— 否则 0.94 的面板会把它后面的三行选项透出来
	#    （6% 的亮度也看得见，实测就是一排灰字鬼影 + 一圈露出来的圆角边框）。
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	# 1. 遮罩：吃掉背后的所有点击，同时把画面压暗（和设置面板同一个值，保持一种视觉语言）
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.08, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点面板外 = 继续。方向要是"安全"的那个：误点最多回到游戏，不会把本局扔掉。
	dim.gui_input.connect(_on_dim_input)
	_body.add_child(dim)

	# 2. 居中面板（尺寸/边框/圆角/内边距全部对齐 `SettingsPanel`）
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(420, 0)
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
	# ⚠ **必须显式 STOP**：默认值不可靠，穿透到遮罩就变成"点一下选项面板自己关了"。
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := _mk("已暂停", 26, Color(0.80, 0.92, 1.0), 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	# 本局进度。暂停正是玩家最想知道"我现在值多少"的时刻（项目里没有最高分存档，
	# 一按 ESC 弃局就什么都不剩 —— 这也是这个面板存在的主要理由）。
	_lbl_info = _mk("", 14, Color(0.62, 0.78, 0.92), 2)
	_lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_lbl_info)
	vb.add_child(_spacer(14))

	# 3. 两个选项。热区按"整行"算（容器 STOP + Label IGNORE）：
	#    只给 Label 设热区太窄，22px 的字点起来很难受。
	# 布局 = 固定宽 148 的块（`SHRINK_CENTER` 水平居中）+ 标记列(24) + 左对齐文字。
	# 为什么不用"整行文字居中"：两行字数不同（4 字 / 5 字），居中的话换选中项时
	# 整行会左右跳一格；固定块宽 + 左对齐，两行的文字左缘永远在同一条竖线上。
	for i in OPTIONS.size():
		var group := HBoxContainer.new()
		group.mouse_filter = Control.MOUSE_FILTER_STOP
		group.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		group.custom_minimum_size = Vector2(148, 34)
		group.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		group.add_theme_constant_override("separation", 0)
		vb.add_child(group)

		var mark := _mk("", 22, Color(1.0, 0.86, 0.50), 3)
		mark.custom_minimum_size = Vector2(24, 0)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(mark)
		_marks.append(mark)

		var row := _mk("", 22, Color(0.72, 0.82, 0.92), 3)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE     # 事件交给 group
		group.add_child(row)
		_rows.append(row)

		group.mouse_entered.connect(_on_hover.bind(i))
		group.gui_input.connect(_on_row_input.bind(i))

	vb.add_child(_spacer(12))
	var hint := _mk("↑↓ 选择　回车确认　ESC 继续", 13, Color(0.56, 0.70, 0.84), 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)

	# 4. 设置面板。**必须最后 add**：它要盖在暂停面板的选项之上，且
	#    `_unhandled_input` 是"子节点先收到"，挂最后才能先吃按键。
	#    暂停中能操作是靠 process_mode 继承本面板的 ALWAYS（不要在这里再设一次）。
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.closed.connect(_on_settings_closed)

	_refresh()


func _fit() -> void:
	size = get_viewport_rect().size


## 打开面板并显示本局进度。由 `Main._pause_game()` 调用 —— 它在返回后立刻把树暂停。
func open(distance: float, score: int) -> void:
	if visible:
		return
	_lbl_info.text = "已跑 %d m　得分 %d" % [roundi(distance / 64.0), score]
	_sel = 0          # 默认停在"继续游戏"：误按回车也不会丢掉本局
	_body.visible = true      # 上一轮如果是"从设置里退回来"，这里必须复位
	visible = true
	_open_frame = Engine.get_process_frames()     # 见 `_open_frame` 的注释
	_refresh()
	AudioManager.play_sfx("ui_move", -2.0)


func close() -> void:
	if not visible:
		return
	# 兜底：正常情况下设置开着时外层收不到"继续/返回"，走不到这里
	if _settings != null and _settings.visible:
		_settings.close()
	_body.visible = true
	visible = false


# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _open_frame:
		return
	# 设置面板叠在上面时，按键全部归它（子节点先收到，这里只是兜底）
	if _settings.visible:
		return
	# 关掉设置的那一帧：同一次 ESC 会继续往下派发到这里 ⇒
	# 不挡的话"关掉设置"会顺手把游戏也继续了（用户按一下连退两层）。
	if Engine.get_process_frames() == _settings_closed_frame:
		return
	if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
		_sel = wrapi(_sel + (1 if event.is_action_pressed("menu_down") else -1),
			0, OPTIONS.size())
		_refresh()
		AudioManager.play_sfx("ui_move", -4.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		_choose(_sel)
	elif event.is_action_pressed("back_to_menu"):
		# 暂停中 ESC 只承担"退出暂停"，**不是**回主菜单 —— 回主菜单要在面板里选。
		_choose(0)


func _choose(i: int) -> void:
	# 1 = 设置：**不关暂停面板**，只是把设置叠上来；关掉设置仍回到暂停。
	if i == 1:
		_open_settings()
		get_viewport().set_input_as_handled()
		return
	# 先收面板再发信号：`Main` 收到后会立刻 `paused = false`，
	# 那时如果面板还画着，会有一帧"已经能动了但遮罩还在"的闪。
	close()
	AudioManager.play_sfx("ui_confirm", 0.0 if i == 0 else -2.0)
	if i == 0:
		resumed.emit()
	else:
		menu_requested.emit()
	get_viewport().set_input_as_handled()


func _on_settings_closed() -> void:
	_body.visible = true
	_settings_closed_frame = Engine.get_process_frames()


## 打开设置：**先把面板本体整块收起来**（0.94 的背景会把后面的三行透出来），
## 关闭时 `_on_settings_closed()` 再放回来。`open()` 自己会响一声，调用方不要再叠。
func _open_settings() -> void:
	_body.visible = false
	_settings.open()


## 调试用（`--pause-demo`）：设置面板是否正叠在上面
func settings_visible() -> bool:
	return _settings != null and _settings.visible


## 只给抓帧用（`-- --pause-shot-settings`）：直接把设置叠上来，
## 用来验"暂停面板 + 设置面板 + 两层遮罩"摞在一起时的观感。
func debug_open_settings() -> void:
	_open_settings()


## 悬停即选中——和主菜单、设置面板同一套：视觉只有一种"选中"语言。
func _on_hover(i: int) -> void:
	if _sel == i:
		return
	_sel = i
	_refresh()
	AudioManager.play_sfx("ui_move", -4.0)


func _on_row_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_sel = i
			_choose(i)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(0)


# ---------------------------------------------------------------- 渲染
func _refresh() -> void:
	for i in _rows.size():
		var on := i == _sel
		# 标记单独占一列（见 `_ready()` 里的布局说明），文字本身不带缩进 ——
		# 两行的文字因此**严格对齐**，选中只多出一个 ▶，不会整行往右跳。
		_marks[i].text = "▶" if on else ""
		_rows[i].text = OPTIONS[i]
		_rows[i].add_theme_color_override("font_color",
			Color(1.0, 0.86, 0.50) if on else Color(0.72, 0.82, 0.92))


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
