extends CanvasLayer
class_name MainMenu
## 主界面 —— 选模式。
##
## 两个选项：
##   正常模式 —— 完整玩法：障碍 + 死亡边界 + 高潮追击
##   测试模式 —— 平坦地面、无障碍、无追逐、永不死亡，只用来观察角色动作
##
## 交互：↑↓ 选择、回车/空格确认，也可以直接按 1 / 2。
## 界面上直接写明两种模式的差别，避免以后还要回来翻代码。

signal mode_chosen(mode: int)
signal replay_intro_requested()

## 封面图。**必须是 1280x720**（视口尺寸）—— 项目开了最近邻过滤，
## 非整数倍放大会让像素宽度在 1px/2px 之间跳。改图用 `tools/make_title_cover.py` 重新生成。
const TITLE_BG := preload("res://sprites/title/title_screen_pixel_art.png")

## ⚠ `desc` 必须**短**（≤12 字）：菜单是 236px 宽的右对齐窄列，13px 下 12 字约 156px。
## 原来是「完整玩法：障碍、死亡边界、高潮追击战」这种 20 字长句，现在塞不进去了。
const OPTIONS := [
	{
		"title": "出海奔跑",
		"desc": "常规 / 困难 · 出航",
		"mode": 0,           # 展开出海模式选择（常规模式 / 困难模式）
	},
	{
		"title": "鲸堡小店",
		"desc": "做餐 · 赚贝壳 · Buff",
		"mode": -3,          # -3 = 打开深海鲸堡小店
	},
	{
		"title": "换装",
		"desc": "深海衣橱 · 皮肤",
		"mode": -2,          # -2 = 打开深海换装衣橱
	},
	{
		"title": "设置",
		"desc": "音量 · 成就 · 重温",
		"mode": -1,          # -1 = 打开设置面板
	},
]

var _root: Control
var _ui_col: VBoxContainer
var _rows: Array[Label] = []
## 每个选项的「名字 + 说明」整体。**鼠标热区按这个算** ——
## 只给 Label 设热区太窄（文字高度 26px），点起来很难受。
var _groups: Array[Control] = []
## 鲸堡小店、换装衣橱、成就图鉴与设置面板：同在 CanvasLayer 200 里，盖在菜单之上
var _shop: ShopPanel
var _wardrobe: WardrobePanel
var _achievements: AchievementsPanel
var _settings: SettingsPanel
var _mode_picker: Control
var _mode_sel := 0
var _mode_rows: Array[PanelContainer] = []
var _mode_buff_lbl: Label
var _reopen_settings_after_ach := false
var _selected := 0
var _intro_blocking := false
var _fade_tw: Tween


func _ready() -> void:
	layer = 200

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 1. 封面大图背景：全屏等比覆盖（无黑边自动铺满）
	var bg := TextureRect.new()
	bg.texture = TITLE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# 2. 菜单文字：**右上角、右对齐、小字号**（2026-10-30 重构，用户："文字喧宾夺主"）
	#    · 字号 46/30/17/18 → **24/20/13/13**，整块占屏从 ≈18% 降到 **3.7%**
	#    · 从居中改为贴右上角 ⇒ 画面中心（两个人的脸）完全让出来
	#    · 右边距 24 / 上边距 16；列宽固定 236（实测文字 196，留 40 给字体差异）
	#    · **不加任何压暗或背板**：右上那块底子亮度 97，白字对比 **5.5:1**，13px 够读。
	#      左上那块是 137（只有 3.1:1），必须加背板才读得清 —— 这就是选右上的原因。
	_ui_col = VBoxContainer.new()
	var vb := _ui_col
	vb.anchor_left = 1.0
	vb.anchor_right = 1.0
	vb.anchor_top = 0.0
	vb.anchor_bottom = 0.0
	vb.offset_left = -260.0
	vb.offset_right = -24.0
	vb.offset_top = 16.0
	vb.offset_bottom = 16.0
	vb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	vb.grow_vertical = Control.GROW_DIRECTION_END
	vb.add_theme_constant_override("separation", 4)
	_root.add_child(vb)

	# 标题 28px：**必须缩短字数**，否则放不下 —— 列宽 236、实际可用只有 196（左边是她帽檐 x≤1015）。
	# 实测：`深海鲸鱼娘 · 跑酷`(8字) 24px 正好 196px 到顶；`鲸鱼娘 · 跑酷`(6字) 28px 只要 170px ✓
	var title := _mk_label("鲸鱼娘 · 跑酷", 28, Color(0.80, 0.92, 1.0), 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(title)

	# 「垂直切片」是开发期标签，2026-10-30 删掉：少一行，整块密度立刻降下来
	vb.add_child(_spacer(20))

	for i in OPTIONS.size():
		# 一个选项 = 「名字 + 说明」一个整体，鼠标热区按整块算。
		# `mouse_default_cursor_shape` 让系统指针自动变成手型，不用手动 set_cursor_shape。
		var group := VBoxContainer.new()
		group.mouse_filter = Control.MOUSE_FILTER_STOP
		group.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		group.add_theme_constant_override("separation", 2)
		vb.add_child(group)
		_groups.append(group)

		var row := _mk_label("", 26, Color(0.70, 0.80, 0.90), 4)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE     # 事件交给 group
		group.add_child(row)
		_rows.append(row)

		var d := _mk_label(OPTIONS[i]["desc"], 14, Color(0.74, 0.85, 0.96), 2)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(d)

		group.mouse_entered.connect(_on_row_hover.bind(i))
		group.gui_input.connect(_on_row_input.bind(i))

		if i < OPTIONS.size() - 1:
			vb.add_child(_spacer(14))

	# 3. 操作提示：**已删除**（2026-10-30）
	#    那行字压在锚上（背景亮度起伏 σ=48.1，全画面最碎的区域），是全屏唯一"贴在主体上"的文字。
	#    信息也冗余：行首已有 1/2/3、▶ 已表达选中、鼠标能悬停能点。
	#    唯一别处没有的「ESC 回主界面」已挪到结算面板（玩家真正需要它的时刻）。
	#    ⚠ 设置面板里仍保留一行操作提示 —— 那是深色面板，不碍事。

	# 4. 鲸堡小店、换装衣橱、成就面板与设置面板（默认隐藏）
	_shop = ShopPanel.new()
	_shop.start_run_requested.connect(func():
		_open_mode_picker()
	)
	add_child(_shop)

	_wardrobe = WardrobePanel.new()
	add_child(_wardrobe)

	_achievements = AchievementsPanel.new()
	_achievements.closed.connect(func():
		if _reopen_settings_after_ach:
			_reopen_settings_after_ach = false
			_settings.open("achievements")
	)
	add_child(_achievements)

	_settings = SettingsPanel.new()
	_settings.allow_achievements = true
	_settings.allow_intro_replay = true
	_settings.achievements_requested.connect(func():
		_reopen_settings_after_ach = true
		_achievements.open()
	)
	_settings.replay_intro_requested.connect(func(): replay_intro_requested.emit())
	add_child(_settings)

	_build_mode_picker()

	# `-- --shop` / `-- --wardrobe` / `-- --settings` / `-- --achievements`：启动直接展开对应面板
	if OS.get_cmdline_user_args().has("--shop"):
		_shop.open.call_deferred()
	elif OS.get_cmdline_user_args().has("--wardrobe"):
		var init_skin := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--skin="):
				init_skin = a.substr("--skin=".length())
		_wardrobe.open.call_deferred(init_skin)
	elif OS.get_cmdline_user_args().has("--achievements"):
		var init_art := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--art="):
				init_art = a.substr("--art=".length())
		_achievements.open.call_deferred(init_art)
	elif OS.get_cmdline_user_args().has("--settings"):
		_settings.open.call_deferred()

	GameState.menu_opened.connect(_refresh)
	GameState.ready_started.connect(_on_ready_started)
	GameState.run_started.connect(_on_run_started)
	_refresh()


## `outline` 要跟着字号走：46px 时用 6 好看，24px 用 6 会糊成一坨。
func _mk_label(text: String, size: int, col: Color, outline: int = 3) -> Label:
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
	return c


## 鼠标移到某个选项上 ⇒ **直接把它变成选中项**（和键盘选择走同一套渲染）。
## 这样"悬停高亮"和"键盘选中"永远长得一样，不会出现两套视觉语言。
func set_intro_blocking(on: bool) -> void:
	_intro_blocking = on
	if on and _ui_col != null:
		_ui_col.modulate.a = 0.0


func reveal_ui(duration: float = 0.45, snap_alpha: float = -1.0) -> void:
	_intro_blocking = false
	_root.modulate.a = 1.0
	visible = GameState.is_menu()
	if _ui_col == null:
		return
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	if snap_alpha >= 0.0:
		_ui_col.modulate.a = clampf(snap_alpha, 0.0, 1.0)
		return
	if duration <= 0.0:
		_ui_col.modulate.a = 1.0
		return
	_ui_col.modulate.a = 0.0
	_fade_tw = create_tween()
	_fade_tw.tween_property(_ui_col, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_row_hover(i: int) -> void:
	if not GameState.is_menu() or _intro_blocking or _selected == i:
		return
	_selected = i
	_refresh()
	AudioManager.play_sfx("ui_move", -4.0)


## 左键点击选项 = 确认。和键盘回车走同一个 `_choose()`。
func _on_row_input(event: InputEvent, i: int) -> void:
	if not GameState.is_menu() or _intro_blocking:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_choose(i)
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	visible = GameState.is_menu()
	if _root != null:
		_root.modulate.a = 1.0
	if _ui_col != null and not _intro_blocking:
		_ui_col.modulate.a = 1.0
	_selected = clampi(_selected, 0, OPTIONS.size() - 1)
	for i in _rows.size():
		var on := i == _selected
		# 右对齐窄列：选中标记放在行首，整行会往左多伸一个字宽 ⇒ 天然形成一个"缩进差"。
		# 未选中用全角空格占位，两行右缘才对得齐。
		_rows[i].text = ("▶  " if on else "　  ") + "%d  %s" % [i + 1, OPTIONS[i]["title"]]
		_rows[i].add_theme_color_override("font_color",
			Color(1.0, 0.86, 0.50) if on else Color(0.68, 0.80, 0.90))


func _on_ready_started() -> void:
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	if not visible:
		if _root != null:
			_root.modulate.a = 1.0
		return
	# 进起跑过场时平滑淡出封面（0.18s），露出现场海底与奔跑小人
	_fade_tw = create_tween()
	_fade_tw.tween_property(_root, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	_fade_tw.tween_callback(func():
		if not GameState.is_menu():
			visible = false
			_root.modulate.a = 1.0
	)


func _on_run_started() -> void:
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	visible = false
	if _root != null:
		_root.modulate.a = 1.0


func open_shop() -> void:
	if _mode_picker != null:
		_mode_picker.visible = false
	if _shop != null:
		_shop.open()


func _build_mode_picker() -> void:
	_mode_picker = Control.new()
	_mode_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mode_picker.visible = false
	_mode_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_mode_picker)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.08, 0.58)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_mode_picker.visible = false
	)
	_mode_picker.add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(480, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.082, 0.145, 0.96)
	sb.border_color = Color(0.36, 0.68, 0.88, 0.88)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_mode_picker.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	var ttl := _mk_label("选择出航模式", 22, Color(0.84, 0.95, 1.0), 4)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ttl)

	_mode_buff_lbl = _mk_label("", 13, Color(1.0, 0.88, 0.44), 2)
	_mode_buff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_mode_buff_lbl)

	var mode_items := [
		{"title": "1  常规模式", "desc": "海洋采植 · 黑鲸娘常态追击", "mode": GameState.Mode.NORMAL},
		{"title": "2  困难模式", "desc": "黑鲸娘狂暴模式 · 掉落稀有星光藻", "mode": GameState.Mode.HARD},
	]
	_mode_rows.clear()
	for mi in mode_items.size():
		var item: Dictionary = mode_items[mi]
		var row_pc := PanelContainer.new()
		row_pc.mouse_filter = Control.MOUSE_FILTER_STOP
		row_pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row_pc.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_launch_mode(mi)
		)
		row_pc.mouse_entered.connect(func():
			_mode_sel = mi
			_refresh_mode_picker()
			AudioManager.play_sfx("ui_move", -4.0)
		)
		vb.add_child(row_pc)
		_mode_rows.append(row_pc)

		var rvb := VBoxContainer.new()
		rvb.add_theme_constant_override("separation", 2)
		rvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_pc.add_child(rvb)
		var rttl := _mk_label(String(item["title"]), 19, Color(0.95, 0.98, 1.0), 3)
		rttl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_child(rttl)
		var rdsc := _mk_label(String(item["desc"]), 13, Color(0.72, 0.86, 0.95), 2)
		rdsc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_child(rdsc)

	var esc_tip := _mk_label("↑↓ 选择 · Enter / 1 / 2 确认 · ESC 返回", 12, Color(0.60, 0.76, 0.88), 2)
	esc_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(esc_tip)


func _open_mode_picker() -> void:
	_mode_sel = 0
	if Progress != null and Progress.active_meal_buff != "":
		var bd := ShopCatalog.get_dish(Progress.active_meal_buff)
		_mode_buff_lbl.text = "已享用出航Buff：%s（%s）" % [String(bd.get("name", "")), String(bd.get("buff_name", ""))]
		_mode_buff_lbl.visible = true
	else:
		_mode_buff_lbl.text = "提示：可在「鲸堡小店」吃下海味快餐获得出海 Buff"
		_mode_buff_lbl.visible = true
	_mode_picker.visible = true
	_refresh_mode_picker()
	AudioManager.play_sfx("ui_move", -2.0)


func _refresh_mode_picker() -> void:
	for i in _mode_rows.size():
		var on := i == _mode_sel
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.25, 0.40, 0.96) if on else Color(0.06, 0.12, 0.20, 0.88)
		sb.border_color = Color(0.55, 0.88, 1.0, 0.95) if on else Color(0.28, 0.48, 0.64, 0.65)
		sb.set_border_width_all(2 if on else 1)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		_mode_rows[i].add_theme_stylebox_override("panel", sb)


func _launch_mode(mi: int) -> void:
	_mode_picker.visible = false
	var target_mode := GameState.Mode.NORMAL if mi == 0 else GameState.Mode.HARD
	AudioManager.play_sfx("ui_confirm", 0.0)
	mode_chosen.emit(target_mode)


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_menu() or _intro_blocking:
		return
	# 小店、换装、成就或设置面板展开时，↑↓/回车/ESC 全部交给对应面板，菜单不再响应
	if (_shop != null and _shop.visible) \
			or (_wardrobe != null and _wardrobe.visible) \
			or (_achievements != null and _achievements.visible) \
			or (_settings != null and _settings.visible):
		return
	if _mode_picker != null and _mode_picker.visible:
		if event.is_action_pressed("back_to_menu"):
			_mode_picker.visible = false
			AudioManager.play_sfx("ui_move", -2.0)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
			_mode_sel = 1 - _mode_sel
			_refresh_mode_picker()
			AudioManager.play_sfx("ui_move", -2.0)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_confirm"):
			_launch_mode(_mode_sel)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			var mk := (event as InputEventKey).keycode
			if mk == KEY_1 or mk == KEY_KP_1:
				_launch_mode(0)
				get_viewport().set_input_as_handled()
			elif mk == KEY_2 or mk == KEY_KP_2:
				_launch_mode(1)
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_up"):
		_selected = wrapi(_selected - 1, 0, OPTIONS.size())
		_refresh()
		AudioManager.play_sfx("ui_move", -2.0, randf_range(0.98, 1.02))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_selected = wrapi(_selected + 1, 0, OPTIONS.size())
		_refresh()
		AudioManager.play_sfx("ui_move", -2.0, randf_range(0.98, 1.02))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		_choose(_selected)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_1 or k == KEY_KP_1:
			_choose(0)
			get_viewport().set_input_as_handled()
		elif k == KEY_2 or k == KEY_KP_2:
			_choose(1)
			get_viewport().set_input_as_handled()
		elif k == KEY_3 or k == KEY_KP_3:
			_choose(2)
			get_viewport().set_input_as_handled()
		elif k == KEY_4 or k == KEY_KP_4:
			_choose(3)
			get_viewport().set_input_as_handled()


func _choose(i: int) -> void:
	var m: int = OPTIONS[i]["mode"]
	if m == -3:
		open_shop()
		return
	if m == -2:
		_wardrobe.open()
		return
	if m == -1:
		# "设置"这一项：不开跑，展开设置面板
		_settings.open()
		return
	_open_mode_picker()
