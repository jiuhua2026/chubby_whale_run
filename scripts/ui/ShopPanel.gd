extends Control
class_name ShopPanel
## 深海鲸堡小店（1280×720 横屏实景经营）：
##   · 上半屏实景大厅：左外卖窗口 + 中景柜台店长 + 右侧珊瑚卡座（5 种纯海洋动物顾客 + 乔装黑鲸娘彩蛋）
##   · 下半屏料理台：左海洋原料篮与 6 道菜谱 + 中 3 个厨具工位（含★金脆完美区） + 右 3 格木质托盘与赛前试吃 Buff
##   · 支持鼠标点击与键盘快捷键（1~6 点菜下单 / Space 拍金脆 / Q,W,E 一键上菜 / ESC 返回）

signal closed()
signal start_run_requested()

const SHOP_BG_TEX := preload("res://sprites/shop/shop_bg.png")
const SHOP_FG_WINDOW_TEX := preload("res://sprites/shop/shop_fg_window.png")
const SHOP_FG_COUNTER_TEX := preload("res://sprites/shop/shop_fg_counter.png")
const SHOP_FG_BOOTH1_TEX := preload("res://sprites/shop/shop_fg_booth1.png")
const SHOP_FG_BOOTH2_TEX := preload("res://sprites/shop/shop_fg_booth2.png")
const TEX_COIN := preload("res://sprites/shop/coin_shell.png")
const TEX_CRISP := preload("res://sprites/shop/badge_crisp.png")
const TEX_TRAY := preload("res://sprites/shop/tray_wood.png")
const TEX_CREW := {
	"welcome": preload("res://sprites/shop/crew_welcome.png"),
	"cook": preload("res://sprites/shop/crew_cook.png"),
	"serve": preload("res://sprites/shop/crew_serve.png"),
	"cheer": preload("res://sprites/shop/crew_cheer.png"),
}
const PLANT_ICONS := {
	"kelp": preload("res://sprites/plants/kelp.png"),
	"nori": preload("res://sprites/plants/nori.png"),
	"seaweed": preload("res://sprites/plants/seaweed.png"),
	"star_algae": preload("res://sprites/plants/star_algae.png"),
}

const SHIFT_DURATION := 150.0
const MAX_TRAY_SLOTS := 3

## 料理工位槽数据
class CookSlot:
	var station := "fryer"
	var dish_id := ""
	var progress := 0.0
	var duration := 3.0
	var active := false
	var ready_hold := false
	var crisp := false
	var zone_cued := false

## 顾客就座槽数据（0=左外卖窗, 1=右左卡座, 2=右右卡座）
class CustSlot:
	var idx := 0
	var kind := "window"
	var occupied := false
	var cust_id := ""
	var orders: Array[String] = []
	var patience := 0.0
	var max_patience := 20.0
	var eating := false
	var eat_t := 0.0
	var leave_cd := 1.2
	var bubble_text := ""
	var happy := false

## 托盘槽数据
class TraySlot:
	var dish_id := ""
	var crisp := false

var _tex_cache := {}
var _cook_slots: Array[CookSlot] = []
var _cust_slots: Array[CustSlot] = []
var _tray: Array[TraySlot] = []

var _shift_active := false
var _shift_t := 0.0
var _shift_revenue := 0
var _shift_served := 0
var _shift_crisp_hits := 0
var _shift_combo := 0
var _shift_max_combo := 0
var _shift_disguise_hits := 0
var _spawn_cd := 0.8

var _crew_pose := "welcome"
var _crew_pose_t := 0.0
var _anim_t := 0.0
var _use_crew_uniform := true
var _next_booth1_is_jelly := true
var _next_booth2_is_shark := true

# ── UI 节点缓存
var _stage_frame: Control
var _crew_sprite: TextureRect
var _crew_skin_btn: Button
var _crew_speech: Label

var _lbl_decor_badge: Label
var _lbl_coins: Label
var _lbl_shift_status: Label
var _lbl_buff_pill: Label
var _btn_shift: Button
var _btn_upgrade: Button
var _btn_go_run: Button

var _plant_count_lbls := {}
var _dish_btns: Array[Button] = []
var _dish_cost_lbls: Array[Label] = []

var _station_fryer_tex: TextureRect
var _station_fryer_title: Label
var _fryer_bars: Array[Control] = []
var _board_bar: Control
var _soda_bar: Control
var _fryer_hint: Label
var _board_hint: Label
var _soda_hint: Label

var _cust_cards: Array[Control] = []
var _cust_sprites: Array[TextureRect] = []
var _cust_sprite_base_y: Array[float] = [260.0, 294.0, 304.0]
var _cust_bubbles: Array[PanelContainer] = []
var _cust_name_lbls: Array[Label] = []
var _cust_order_boxes: Array[HBoxContainer] = []
var _cust_pat_bars: Array[ProgressBar] = []
var _cust_serve_hints: Array[Label] = []

var _tray_btns: Array[Button] = []
var _tray_dish_icons: Array[TextureRect] = []
var _tray_crisp_icons: Array[TextureRect] = []
var _tray_name_lbls: Array[Label] = []
var _tray_eat_btns: Array[Button] = []

var _toast_lbl: Label
var _toast_t := 0.0
var _fx_layer: Control
var _float_layer: Control

var _upgrade_modal: Control
var _upg_rows: Array[Dictionary] = []
var _summary_modal: Control
var _summary_lbl: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_fit()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

	_init_state()
	_build_ui()
	Progress.shop_changed.connect(_refresh_ui)
	Progress.skin_changed.connect(func(_s): _refresh_ui())
	_refresh_ui()


func _fit() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var sz := vp.get_visible_rect().size
	if sz.x > 0.0 and sz.y > 0.0:
		set_position(Vector2.ZERO)
		set_size(sz)
		if _stage_frame != null:
			var sc := minf(sz.x / 1280.0, sz.y / 720.0)
			_stage_frame.scale = Vector2(sc, sc)
			_stage_frame.position = (sz - Vector2(1280.0, 720.0) * sc) * 0.5


func _init_state() -> void:
	_cook_slots.clear()
	for s_name in ["fryer", "fryer", "board", "soda"]:
		var cs := CookSlot.new()
		cs.station = s_name
		_cook_slots.append(cs)

	_cust_slots.clear()
	for i in 3:
		var cu := CustSlot.new()
		cu.idx = i
		cu.kind = "window" if i == 0 else "booth"
		cu.leave_cd = 0.5 + float(i) * 0.7
		_cust_slots.append(cu)

	_tray.clear()
	for _i in MAX_TRAY_SLOTS:
		_tray.append(TraySlot.new())


func open() -> void:
	if Progress != null:
		Progress.grant_shop_starter_if_needed()
	_upgrade_modal.visible = false
	_summary_modal.visible = false
	_crew_pose = "welcome"
	_crew_pose_t = 0.0
	_crew_speech.text = "欢迎光临鲸堡小店！点左下角下锅，或按 1~6 快速备餐~"
	visible = true
	_fit()
	_refresh_ui()
	AudioManager.play_bgm("shop", 0.55)
	AudioManager.play_sfx("ui_confirm", -2.0)


func close(restore_menu_bgm: bool = true) -> void:
	if not visible:
		return
	_stop_shift_cleanly()
	visible = false
	AudioManager.play_sfx("ui_move", -2.0)
	if restore_menu_bgm:
		AudioManager.play_bgm("menu", 0.55)
	closed.emit()


func _stop_shift_cleanly() -> void:
	_shift_active = false
	for cs in _cook_slots:
		if cs.active and cs.dish_id != "" and not cs.ready_hold:
			var d := ShopCatalog.get_dish(cs.dish_id)
			if not d.is_empty():
				Progress.refund_ingredients(d["cost"])
		cs.active = false
		cs.ready_hold = false
		cs.dish_id = ""
		cs.progress = 0.0
	for cu in _cust_slots:
		cu.occupied = false
		cu.orders.clear()
		cu.eating = false


func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path] as Texture2D


# ---------------------------------------------------------------- UI 构建
func _mk_lbl(txt: String, sz: int, col: Color, outline: int = 3) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.04, 0.94))
	l.add_theme_constant_override("outline_size", outline)
	return l


func _mk_panel_sb(bg: Color, border: Color, bw: int = 2, r: int = 10, pad_h: int = 10, pad_v: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(r)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


func _mk_pill_btn(txt: String, bg: Color, border: Color, font_sz: int = 14) -> Button:
	var b := Button.new()
	b.text = txt
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", font_sz)
	b.add_theme_color_override("font_color", Color(0.98, 0.96, 0.92))
	var sb_n := _mk_panel_sb(bg, border, 2, 8, 12, 5)
	var sb_h := _mk_panel_sb(bg.lightened(0.14), border.lightened(0.18), 2, 8, 12, 5)
	var sb_p := _mk_panel_sb(bg.darkened(0.16), border, 2, 8, 12, 5)
	var sb_d := _mk_panel_sb(Color(0.14, 0.16, 0.20, 0.72), Color(0.28, 0.32, 0.38, 0.5), 1, 8, 12, 5)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("disabled", sb_d)
	b.add_theme_stylebox_override("focus", sb_h)
	return b


func _build_ui() -> void:
	# 0. 全屏深海暗调衬底 + 1280×720 等比锁定主舞台容器（彻底根除最大化/拉宽窗口导致的人物穿模错位）
	var outer_fill := ColorRect.new()
	outer_fill.color = Color(0.024, 0.035, 0.055, 1.0)
	outer_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_fill.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(outer_fill)

	var outer_bg := TextureRect.new()
	outer_bg.texture = SHOP_BG_TEX
	outer_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outer_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	outer_bg.modulate = Color(0.24, 0.28, 0.34, 0.72)
	outer_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer_bg)

	_stage_frame = Control.new()
	_stage_frame.position = Vector2.ZERO
	_stage_frame.size = Vector2(1280, 720)
	_stage_frame.clip_contents = true
	_stage_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage_frame)

	# 1. 横屏店铺实景底图 (严格锁定 1280×720)
	var bg := TextureRect.new()
	bg.texture = SHOP_BG_TEX
	bg.position = Vector2.ZERO
	bg.size = Vector2(1280, 720)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_frame.add_child(bg)

	# 2. 顶部营业顶栏 (y: 0..54)
	var top_bar := PanelContainer.new()
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(1280, 54)
	top_bar.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.07, 0.05, 0.05, 0.86), Color(0.72, 0.56, 0.32, 0.72), 1, 0, 16, 6
	))
	_stage_frame.add_child(top_bar)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_bar.add_child(top_row)

	var brand := _mk_lbl("深海鲸堡小店", 20, Color(0.62, 0.96, 1.0), 4)
	top_row.add_child(brand)

	_lbl_decor_badge = _mk_lbl("初创木摊", 13, Color(1.0, 0.86, 0.56), 3)
	top_row.add_child(_lbl_decor_badge)

	var coin_chip := PanelContainer.new()
	coin_chip.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.18, 0.13, 0.06, 0.92), Color(0.95, 0.75, 0.30, 0.88), 1, 12, 10, 3
	))
	top_row.add_child(coin_chip)
	var coin_hb := HBoxContainer.new()
	coin_hb.add_theme_constant_override("separation", 6)
	coin_chip.add_child(coin_hb)
	var coin_ic := TextureRect.new()
	coin_ic.texture = TEX_COIN
	coin_ic.custom_minimum_size = Vector2(22, 22)
	coin_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	coin_hb.add_child(coin_ic)
	_lbl_coins = _mk_lbl("0", 16, Color(1.0, 0.90, 0.48), 3)
	coin_hb.add_child(_lbl_coins)

	_lbl_shift_status = _mk_lbl("备餐休整中 · 可自由研发/吃Buff或开店营业", 14, Color(0.92, 0.94, 0.98), 3)
	_lbl_shift_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_shift_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(_lbl_shift_status)

	_lbl_buff_pill = _mk_lbl("出航Buff：无", 13, Color(0.66, 0.95, 0.82), 3)
	top_row.add_child(_lbl_buff_pill)

	_crew_skin_btn = _mk_pill_btn("店长：制服", Color(0.14, 0.18, 0.28, 0.92), Color(0.46, 0.78, 0.94, 0.78), 12)
	_crew_skin_btn.pressed.connect(func():
		_use_crew_uniform = not _use_crew_uniform
		AudioManager.play_sfx("ui_move", -2.0)
		_refresh_crew_visual()
	)
	top_row.add_child(_crew_skin_btn)

	_btn_shift = _mk_pill_btn("开始 2:30 营业", Color(0.14, 0.48, 0.34, 0.95), Color(0.45, 0.92, 0.72, 0.9), 14)
	_btn_shift.pressed.connect(_on_toggle_shift)
	top_row.add_child(_btn_shift)

	_btn_upgrade = _mk_pill_btn("店铺升级", Color(0.36, 0.24, 0.12, 0.95), Color(0.92, 0.72, 0.38, 0.88), 14)
	_btn_upgrade.pressed.connect(func():
		_refresh_upgrades_modal()
		_upgrade_modal.visible = not _upgrade_modal.visible
		AudioManager.play_sfx("ui_move", -2.0)
	)
	top_row.add_child(_btn_upgrade)

	_btn_go_run = _mk_pill_btn("出海奔跑 ▶", Color(0.12, 0.38, 0.62, 0.96), Color(0.48, 0.84, 1.0, 0.92), 14)
	_btn_go_run.pressed.connect(_on_start_run_pressed)
	top_row.add_child(_btn_go_run)

	var btn_close := _mk_pill_btn("返回 ESC", Color(0.24, 0.14, 0.16, 0.92), Color(0.75, 0.45, 0.48, 0.8), 13)
	btn_close.pressed.connect(close)
	top_row.add_child(btn_close)

	# 3. 中上实景营业厅：严格 1280×720 坐标绑定，按「背景 → 角色 → 前景遮罩 → 气泡」分层
	var stage := Control.new()
	stage.position = Vector2.ZERO
	stage.size = Vector2(1280, 720)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_frame.add_child(stage)

	# 先按槽位顺序构造顾客头像与店长立绘，再依次叠加对应 1280×720 家具前景遮罩
	var sprite_rects := [
		Rect2(98, 258, 130, 130),    # 0=左外卖窗口（海马）
		Rect2(742, 290, 144, 144),   # 1=右一珊瑚卡座（海龟 / 水母姐妹）
		Rect2(1012, 290, 156, 156),  # 2=右二珊瑚卡座（锤头鲨 / 黑鲸娘）
	]
	_cust_sprite_base_y = [258.0, 290.0, 290.0]
	var fg_textures := [SHOP_FG_WINDOW_TEX, SHOP_FG_BOOTH1_TEX, SHOP_FG_BOOTH2_TEX]

	_cust_sprites.clear()
	for i in 3:
		var sr: Rect2 = sprite_rects[i]
		var sp := TextureRect.new()
		sp.position = sr.position
		sp.size = sr.size
		sp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sp.visible = false
		stage.add_child(sp)
		_cust_sprites.append(sp)

		var fg := TextureRect.new()
		fg.texture = fg_textures[i]
		fg.position = Vector2.ZERO
		fg.size = Vector2(1280, 720)
		fg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fg.stretch_mode = TextureRect.STRETCH_SCALE
		fg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(fg)

		if i == 0:
			# 店长立在后台明厨暖光下、木吧台正后方
			_crew_sprite = TextureRect.new()
			_crew_sprite.texture = TEX_CREW["welcome"]
			_crew_sprite.position = Vector2(456, 232)
			_crew_sprite.size = Vector2(156, 180)
			_crew_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_crew_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_crew_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			_crew_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage.add_child(_crew_sprite)

			var fg_cnt := TextureRect.new()
			fg_cnt.texture = SHOP_FG_COUNTER_TEX
			fg_cnt.position = Vector2.ZERO
			fg_cnt.size = Vector2(1280, 720)
			fg_cnt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fg_cnt.stretch_mode = TextureRect.STRETCH_SCALE
			fg_cnt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			fg_cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			stage.add_child(fg_cnt)

	# 吧台正面木板上的紧凑招牌字幕条（绝不压挡墙上菜单灯牌）
	var speech_wrap := PanelContainer.new()
	speech_wrap.position = Vector2(392, 404)
	speech_wrap.size = Vector2(290, 36)
	speech_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech_wrap.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.08, 0.04, 0.02, 0.72), Color(0.76, 0.56, 0.30, 0.65), 1, 8, 8, 4
	))
	stage.add_child(speech_wrap)
	_crew_speech = _mk_lbl("", 11, Color(1.0, 0.94, 0.80), 2)
	_crew_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crew_speech.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crew_speech.clip_text = true
	speech_wrap.add_child(_crew_speech)

	# 3 个顾客交互点击区 + 头顶紧凑点餐气泡（悬浮在所有家具前景之上，不遮挡风景与菜单牌）
	var hit_rects := [
		Rect2(88, 120, 176, 276),
		Rect2(728, 206, 178, 238),
		Rect2(1002, 222, 182, 224),
	]
	var bubble_offsets := [
		Vector2(4, 0),
		Vector2(8, 0),
		Vector2(8, 0),
	]
	var key_tags := ["Q", "W", "E"]
	_cust_cards.clear()
	_cust_bubbles.clear()
	_cust_name_lbls.clear()
	_cust_order_boxes.clear()
	_cust_pat_bars.clear()
	_cust_serve_hints.clear()

	for i in 3:
		var r: Rect2 = hit_rects[i]
		var card := Control.new()
		card.position = r.position
		card.size = r.size
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_customer_clicked.bind(i))
		stage.add_child(card)
		_cust_cards.append(card)

		var bub := PanelContainer.new()
		bub.position = bubble_offsets[i]
		bub.custom_minimum_size = Vector2(166, 56)
		bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bub.add_theme_stylebox_override("panel", _mk_panel_sb(
			Color(0.05, 0.08, 0.14, 0.88), Color(0.54, 0.80, 0.94, 0.86), 2, 10, 8, 5
		))
		card.add_child(bub)
		_cust_bubbles.append(bub)

		var bvb := VBoxContainer.new()
		bvb.add_theme_constant_override("separation", 3)
		bvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bub.add_child(bvb)

		var top_r := HBoxContainer.new()
		top_r.add_theme_constant_override("separation", 4)
		bvb.add_child(top_r)
		var c_nm := _mk_lbl("", 12, Color(1.0, 0.90, 0.56), 3)
		c_nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_r.add_child(c_nm)
		_cust_name_lbls.append(c_nm)

		var sh_lbl := _mk_lbl("[%s]上菜" % key_tags[i], 11, Color(0.58, 0.98, 0.82), 2)
		top_r.add_child(sh_lbl)
		_cust_serve_hints.append(sh_lbl)

		var mid_r := HBoxContainer.new()
		mid_r.add_theme_constant_override("separation", 6)
		mid_r.alignment = BoxContainer.ALIGNMENT_CENTER
		bvb.add_child(mid_r)

		var o_box := HBoxContainer.new()
		o_box.add_theme_constant_override("separation", 3)
		mid_r.add_child(o_box)
		_cust_order_boxes.append(o_box)

		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(72, 7)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pb.max_value = 1.0
		pb.value = 1.0
		pb.show_percentage = false
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid_r.add_child(pb)
		_cust_pat_bars.append(pb)

	# 实景庆祝粒子层 + 漂浮币心气泡提示层
	_fx_layer = Control.new()
	_fx_layer.position = Vector2.ZERO
	_fx_layer.size = Vector2(1280, 720)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_frame.add_child(_fx_layer)

	_float_layer = Control.new()
	_float_layer.position = Vector2.ZERO
	_float_layer.size = Vector2(1280, 720)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_frame.add_child(_float_layer)

	# 4. 下半屏浮木操盘台 (锁定 1280×720 内 y: 496..712)
	var deck := PanelContainer.new()
	deck.position = Vector2(10, 496)
	deck.size = Vector2(1260, 216)
	deck.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.08, 0.055, 0.045, 0.88), Color(0.64, 0.48, 0.28, 0.82), 2, 12, 10, 8
	))
	_stage_frame.add_child(deck)

	var deck_hb := HBoxContainer.new()
	deck_hb.add_theme_constant_override("separation", 10)
	deck.add_child(deck_hb)

	# ── 4A 左区：海洋原料篮 + 6 道菜谱下锅按钮 (width ~392)
	var left_box := PanelContainer.new()
	left_box.custom_minimum_size = Vector2(396, 0)
	left_box.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.05, 0.07, 0.11, 0.78), Color(0.32, 0.52, 0.66, 0.65), 1, 8, 8, 6
	))
	deck_hb.add_child(left_box)

	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 6)
	left_box.add_child(left_vb)

	var ing_row := HBoxContainer.new()
	ing_row.add_theme_constant_override("separation", 8)
	left_vb.add_child(ing_row)
	for pk: String in GameState.PLANT_RARITY:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ing_row.add_child(chip)
		var pic := TextureRect.new()
		pic.texture = PLANT_ICONS[pk]
		pic.custom_minimum_size = Vector2(22, 22)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		chip.add_child(pic)
		var pl := _mk_lbl("0", 13, Color(0.76, 0.96, 0.86), 2)
		chip.add_child(pl)
		_plant_count_lbls[pk] = pl

	var dish_grid := GridContainer.new()
	dish_grid.columns = 3
	dish_grid.add_theme_constant_override("h_separation", 6)
	dish_grid.add_theme_constant_override("v_separation", 6)
	dish_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vb.add_child(dish_grid)

	_dish_btns.clear()
	_dish_cost_lbls.clear()
	for i in ShopCatalog.DISHES.size():
		var d: Dictionary = ShopCatalog.DISHES[i]
		var db := _mk_pill_btn("", Color(0.11, 0.16, 0.24, 0.94), Color(0.38, 0.62, 0.78, 0.78), 12)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.size_flags_vertical = Control.SIZE_EXPAND_FILL
		db.custom_minimum_size = Vector2(118, 68)
		db.pressed.connect(_on_craft_dish.bind(String(d["id"])))
		dish_grid.add_child(db)
		_dish_btns.append(db)

		var dvb := VBoxContainer.new()
		dvb.set_anchors_preset(Control.PRESET_FULL_RECT)
		dvb.offset_left = 4
		dvb.offset_right = -4
		dvb.offset_top = 3
		dvb.offset_bottom = -3
		dvb.alignment = BoxContainer.ALIGNMENT_CENTER
		dvb.add_theme_constant_override("separation", 1)
		dvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		db.add_child(dvb)

		var top_d := HBoxContainer.new()
		top_d.alignment = BoxContainer.ALIGNMENT_CENTER
		top_d.add_theme_constant_override("separation", 4)
		top_d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dvb.add_child(top_d)

		var dic := TextureRect.new()
		dic.texture = _tex(String(d["icon"]))
		dic.custom_minimum_size = Vector2(26, 26)
		dic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		dic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		dic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_d.add_child(dic)

		var p_lbl := _mk_lbl("%d币" % int(d["price"]), 12, Color(1.0, 0.86, 0.36), 2)
		p_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_d.add_child(p_lbl)

		var nm_l := _mk_lbl("[%d]%s" % [i + 1, String(d["name"])], 11, Color(0.95, 0.97, 1.0), 2)
		nm_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm_l.clip_text = true
		nm_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dvb.add_child(nm_l)

		var cost_l := _mk_lbl(ShopCatalog.format_cost(d["cost"]), 10, Color(0.72, 0.90, 0.80), 2)
		cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_l.clip_text = true
		cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dvb.add_child(cost_l)
		_dish_cost_lbls.append(cost_l)

	# ── 4B 中区：3 个制作工位（酥炸锅、组装板、气泡饮机）(width ~476)
	var mid_box := HBoxContainer.new()
	mid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_box.add_theme_constant_override("separation", 8)
	deck_hb.add_child(mid_box)

	_fryer_bars.clear()
	var fryer_ui := _build_station_card("fryer", "① 酥炸锅", "汉堡 / 长条 / 脆脆块", 2)
	mid_box.add_child(fryer_ui["card"])
	_station_fryer_tex = fryer_ui["tex"]
	_station_fryer_title = fryer_ui["title"]
	_fryer_bars = fryer_ui["bars"]
	_fryer_hint = fryer_ui["hint"]

	var board_ui := _build_station_card("board", "② 组装板", "海草卷 / 至尊堡", 1)
	mid_box.add_child(board_ui["card"])
	_board_bar = board_ui["bars"][0]
	_board_hint = board_ui["hint"]

	var soda_ui := _build_station_card("soda", "③ 气泡饮机", "星光藻皇特饮", 1)
	mid_box.add_child(soda_ui["card"])
	_soda_bar = soda_ui["bars"][0]
	_soda_hint = soda_ui["hint"]

	# ── 4C 右区：木质出餐托盘 3 槽 & 自己试吃做 Buff (width ~352)
	var right_box := PanelContainer.new()
	right_box.custom_minimum_size = Vector2(352, 0)
	right_box.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.11, 0.08, 0.05, 0.86), Color(0.76, 0.58, 0.34, 0.72), 1, 8, 8, 6
	))
	deck_hb.add_child(right_box)

	var right_vb := VBoxContainer.new()
	right_vb.add_theme_constant_override("separation", 5)
	right_box.add_child(right_vb)

	var rt_hdr := _mk_lbl("出餐托盘（点菜/QWE递给客人 · 或吃下做Buff）", 12, Color(1.0, 0.90, 0.64), 2)
	rt_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vb.add_child(rt_hdr)

	var tray_row := HBoxContainer.new()
	tray_row.add_theme_constant_override("separation", 6)
	tray_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vb.add_child(tray_row)

	_tray_btns.clear()
	_tray_dish_icons.clear()
	_tray_crisp_icons.clear()
	_tray_name_lbls.clear()
	_tray_eat_btns.clear()

	for ti in MAX_TRAY_SLOTS:
		var slot_vb := VBoxContainer.new()
		slot_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_vb.add_theme_constant_override("separation", 4)
		tray_row.add_child(slot_vb)

		var tb := _mk_pill_btn("", Color(0.16, 0.11, 0.07, 0.94), Color(0.68, 0.50, 0.28, 0.75), 11)
		tb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_on_tray_serve_auto.bind(ti))
		slot_vb.add_child(tb)
		_tray_btns.append(tb)

		var inner := Control.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tb.add_child(inner)

		var tray_bg := TextureRect.new()
		tray_bg.texture = TEX_TRAY
		tray_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		tray_bg.offset_left = 6
		tray_bg.offset_right = -6
		tray_bg.offset_top = 18
		tray_bg.offset_bottom = -14
		tray_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tray_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tray_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tray_bg.modulate = Color(1, 1, 1, 0.55)
		tray_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(tray_bg)

		var d_ic := TextureRect.new()
		d_ic.set_anchors_preset(Control.PRESET_CENTER)
		d_ic.offset_left = -28
		d_ic.offset_top = -34
		d_ic.offset_right = 28
		d_ic.offset_bottom = 22
		d_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d_ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		d_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(d_ic)
		_tray_dish_icons.append(d_ic)

		var c_ic := TextureRect.new()
		c_ic.texture = TEX_CRISP
		c_ic.anchor_left = 1.0
		c_ic.anchor_right = 1.0
		c_ic.offset_left = -28
		c_ic.offset_top = 4
		c_ic.offset_right = -4
		c_ic.offset_bottom = 28
		c_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c_ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		c_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c_ic.visible = false
		inner.add_child(c_ic)
		_tray_crisp_icons.append(c_ic)

		var t_nm := _mk_lbl("空托盘", 11, Color(0.86, 0.84, 0.80), 2)
		t_nm.anchor_left = 0.0
		t_nm.anchor_right = 1.0
		t_nm.anchor_top = 1.0
		t_nm.anchor_bottom = 1.0
		t_nm.offset_top = -24
		t_nm.offset_bottom = -4
		t_nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_nm.clip_text = true
		t_nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(t_nm)
		_tray_name_lbls.append(t_nm)

		var eat_b := _mk_pill_btn("吃下做Buff", Color(0.14, 0.34, 0.52, 0.92), Color(0.45, 0.82, 1.0, 0.82), 11)
		eat_b.custom_minimum_size = Vector2(0, 26)
		eat_b.pressed.connect(_on_eat_tray_buff.bind(ti))
		slot_vb.add_child(eat_b)
		_tray_eat_btns.append(eat_b)

	# 提示条（操作反馈）
	_toast_lbl = _mk_lbl("", 14, Color(1.0, 0.92, 0.45), 3)
	_toast_lbl.position = Vector2(380, 62)
	_toast_lbl.size = Vector2(520, 28)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.visible = false
	_stage_frame.add_child(_toast_lbl)

	# 5. 店铺升级弹窗
	_build_upgrade_modal()
	# 6. 2 分半营业结算弹窗
	_build_summary_modal()


func _build_station_card(st_id: String, title_txt: String, sub_txt: String, slot_count: int) -> Dictionary:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.06, 0.08, 0.13, 0.84), Color(0.42, 0.68, 0.86, 0.72), 1, 10, 8, 6
	))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_trigger_crisp_hit(st_id)
	)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	var ttl := _mk_lbl(title_txt, 13, Color(0.68, 0.95, 1.0), 2)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ttl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ttl)

	var tex := TextureRect.new()
	tex.texture = _tex(String(ShopCatalog.STATIONS[st_id]["tex_0"]))
	tex.custom_minimum_size = Vector2(0, 74)
	tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tex)

	var bars: Array[Control] = []
	for si in slot_count:
		var bar := StationProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 16)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if st_id == "fryer" and si == 1:
			bar.visible = false
		vb.add_child(bar)
		bars.append(bar)

	var hint := _mk_lbl(sub_txt, 11, Color(0.88, 0.92, 0.96), 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.clip_text = true
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

	return {"card": card, "tex": tex, "title": ttl, "bars": bars, "hint": hint}


class StationProgressBar extends Control:
	var active := false
	var progress := 0.0
	var zone_lo := 0.60
	var zone_hi := 0.84
	var dish_name := ""

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 4 or h <= 4:
			return
		draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.11, 0.16, 0.92))
		var zx0 := zone_lo * w
		var zx1 := zone_hi * w
		draw_rect(Rect2(zx0, 1, maxf(4.0, zx1 - zx0), h - 2), Color(0.98, 0.78, 0.22, 0.42))
		draw_rect(Rect2(zx0, 1, maxf(4.0, zx1 - zx0), h - 2), Color(1.0, 0.90, 0.42, 0.85), false, 1.0)
		if active:
			var fw := clampf(progress, 0.0, 1.0) * w
			var in_zone := progress >= zone_lo and progress <= zone_hi
			var fc := Color(1.0, 0.88, 0.30, 0.94) if in_zone else Color(0.32, 0.86, 0.96, 0.88)
			draw_rect(Rect2(1, 2, maxf(2.0, fw - 2.0), h - 4), fc)
			draw_rect(Rect2(clampf(fw - 1.5, 0.0, w - 3.0), 0, 3.0, h), Color.WHITE)
		draw_rect(Rect2(0, 0, w, h), Color(0.45, 0.72, 0.88, 0.75), false, 1.0)


func _build_upgrade_modal() -> void:
	_upgrade_modal = Control.new()
	_upgrade_modal.position = Vector2.ZERO
	_upgrade_modal.size = Vector2(1280, 720)
	_upgrade_modal.visible = false
	_upgrade_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_frame.add_child(_upgrade_modal)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.07, 0.68)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_upgrade_modal.visible = false
	)
	_upgrade_modal.add_child(dim)

	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(680, 0)
	pc.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.05, 0.09, 0.15, 0.96), Color(0.90, 0.72, 0.36, 0.88), 2, 12, 22, 18
	))
	_upgrade_modal.add_child(pc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)

	var t := _mk_lbl("深海鲸堡 · 设施与保鲜兜升级", 22, Color(1.0, 0.90, 0.56), 4)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)

	_upg_rows.clear()
	for upg: Dictionary in ShopCatalog.UPGRADES:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _mk_panel_sb(
			Color(0.08, 0.13, 0.21, 0.92), Color(0.36, 0.62, 0.80, 0.68), 1, 8, 12, 10
		))
		vb.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info_vb)
		var nm_l := _mk_lbl(String(upg["name"]), 16, Color(0.86, 0.96, 1.0), 3)
		info_vb.add_child(nm_l)
		var desc_l := _mk_lbl("", 13, Color(0.72, 0.86, 0.94), 2)
		info_vb.add_child(desc_l)

		var btn := _mk_pill_btn("升级", Color(0.18, 0.48, 0.32, 0.95), Color(0.55, 0.94, 0.72, 0.9), 14)
		btn.custom_minimum_size = Vector2(138, 40)
		var tid := String(upg["id"])
		btn.pressed.connect(func():
			if Progress.upgrade_shop_track(tid):
				AudioManager.play_sfx("shop_crisp", 0.0)
				_spawn_shop_fx("shop/confetti", Vector2(640, 380), Vector2(1.35, 1.35), 1.25)
				_show_toast("升级成功！小店实力大增~")
				_refresh_upgrades_modal()
				_refresh_ui()
		)
		hb.add_child(btn)
		_upg_rows.append({"id": tid, "name": nm_l, "desc": desc_l, "btn": btn})

	var close_b := _mk_pill_btn("返回柜台", Color(0.24, 0.26, 0.34, 0.94), Color(0.62, 0.74, 0.88, 0.8), 14)
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_b.pressed.connect(func(): _upgrade_modal.visible = false)
	vb.add_child(close_b)


func _build_summary_modal() -> void:
	_summary_modal = Control.new()
	_summary_modal.position = Vector2.ZERO
	_summary_modal.size = Vector2(1280, 720)
	_summary_modal.visible = false
	_summary_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_frame.add_child(_summary_modal)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.07, 0.68)
	_summary_modal.add_child(dim)

	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(520, 0)
	pc.add_theme_stylebox_override("panel", _mk_panel_sb(
		Color(0.05, 0.09, 0.15, 0.96), Color(0.96, 0.78, 0.36, 0.9), 2, 12, 24, 20
	))
	_summary_modal.add_child(pc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)

	var ttl := _mk_lbl("本轮打烊结算", 24, Color(1.0, 0.90, 0.52), 4)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ttl)

	_summary_lbl = _mk_lbl("", 16, Color(0.88, 0.95, 1.0), 3)
	_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_summary_lbl)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)

	var b_again := _mk_pill_btn("再来 2:30 营业", Color(0.14, 0.48, 0.34, 0.95), Color(0.45, 0.92, 0.72, 0.9), 14)
	b_again.pressed.connect(func():
		_summary_modal.visible = false
		_start_shift()
	)
	hb.add_child(b_again)

	var b_upg := _mk_pill_btn("去升级设施", Color(0.36, 0.24, 0.12, 0.95), Color(0.92, 0.72, 0.38, 0.88), 14)
	b_upg.pressed.connect(func():
		_summary_modal.visible = false
		_refresh_upgrades_modal()
		_upgrade_modal.visible = true
	)
	hb.add_child(b_upg)

	var b_run := _mk_pill_btn("出海奔跑 ▶", Color(0.12, 0.38, 0.62, 0.96), Color(0.48, 0.84, 1.0, 0.92), 14)
	b_run.pressed.connect(func():
		_summary_modal.visible = false
		_on_start_run_pressed()
	)
	hb.add_child(b_run)

	var b_close := _mk_pill_btn("先留店里", Color(0.22, 0.24, 0.32, 0.92), Color(0.58, 0.68, 0.80, 0.8), 14)
	b_close.pressed.connect(func(): _summary_modal.visible = false)
	hb.add_child(b_close)


# ---------------------------------------------------------------- 经营逻辑循环
func _process(delta: float) -> void:
	if not visible:
		return
	_anim_t += delta

	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast_lbl.visible = false

	if _crew_pose_t > 0.0:
		_crew_pose_t -= delta
		if _crew_pose_t <= 0.0:
			_crew_pose = "welcome"
			_refresh_crew_visual()

	# 店长站在吧台内轻盈呼吸感
	if _crew_sprite != null:
		_crew_sprite.position.y = 232.0 + sin(_anim_t * 3.1) * 2.2

	# 推进烹饪槽（进入金脆区时发出轻脆提示音提醒手感拍合）
	var cook_changed := false
	var zone := _gold_zone()
	for cs in _cook_slots:
		if not cs.active:
			continue
		if cs.ready_hold:
			if _try_place_on_tray(cs.dish_id, cs.crisp):
				cs.active = false
				cs.ready_hold = false
				cs.dish_id = ""
				cs.progress = 0.0
				cs.zone_cued = false
				cook_changed = true
			continue
		cs.progress += delta / maxf(cs.duration, 0.1)
		if not cs.zone_cued and cs.progress >= zone.x and cs.progress <= zone.y:
			cs.zone_cued = true
			AudioManager.play_sfx("shop_zone_cue", -3.0)
		if cs.progress >= 1.0:
			cs.progress = 1.0
			cs.crisp = false
			cs.zone_cued = false
			if _try_place_on_tray(cs.dish_id, false):
				cs.active = false
				cs.dish_id = ""
				cs.progress = 0.0
				AudioManager.play_sfx("ui_move", -1.0, 1.1)
			else:
				cs.ready_hold = true
				_show_toast("托盘已满（3/3），先上菜或吃掉一份吧！")
			cook_changed = true

	_update_station_bars()
	if cook_changed:
		_refresh_ui()

	if not _shift_active:
		return

	# 2 分 30 秒 (150s) 舒缓营业倒计时与波次
	_shift_t -= delta
	var rem_s := maxi(0, ceili(_shift_t))
	@warning_ignore("integer_division")
	var rem_min := rem_s / 60
	var rem_sec := rem_s % 60
	_lbl_shift_status.text = "营业中 %02d:%02d  ·  本轮 +%d 贝壳币  ·  金脆连击 ×%d" % [
		rem_min, rem_sec, _shift_revenue, _shift_combo
	]

	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_try_spawn_customer()
		var base_gap := randf_range(4.2, 5.6) if Progress.shop_decor_lv == 0 else randf_range(3.5, 4.8)
		_spawn_cd = base_gap

	var pat_mult := 0.80 if Progress.shop_decor_lv >= 2 else (0.90 if Progress.shop_decor_lv == 1 else 1.0)
	var cust_dirty := false
	for i in _cust_slots.size():
		var cu := _cust_slots[i]
		if not cu.occupied:
			cu.leave_cd = maxf(0.0, cu.leave_cd - delta)
			continue
		var base_cy := _cust_sprite_base_y[i]
		if cu.eating:
			cu.eat_t -= delta
			_cust_sprites[i].position.y = base_cy - absf(sin(_anim_t * 10.0)) * 7.0
			if cu.eat_t <= 0.0:
				cu.occupied = false
				cu.eating = false
				cu.orders.clear()
				cu.leave_cd = randf_range(3.6, 5.2)
				cust_dirty = true
			continue
		_cust_sprites[i].position.y = base_cy + sin(_anim_t * 2.5 + float(i) * 1.4) * 2.0
		cu.patience -= delta * pat_mult
		_cust_pat_bars[i].value = clampf(cu.patience / maxf(cu.max_patience, 1.0), 0.0, 1.0)
		if cu.patience <= 0.0:
			cu.occupied = false
			cu.orders.clear()
			cu.leave_cd = randf_range(3.8, 5.2)
			_shift_combo = 0
			_show_toast("%s 等太久游走啦…" % String(ShopCatalog.get_customer(cu.cust_id)["name"]))
			cust_dirty = true

	if cust_dirty:
		_refresh_customers_ui()

	if _shift_t <= 0.0:
		_finish_shift()


func _gold_zone() -> Vector2:
	if Progress.shop_fryer_lv >= 2:
		return Vector2(0.42, 0.92)
	if Progress.shop_fryer_lv == 1:
		return Vector2(0.48, 0.88)
	return Vector2(0.56, 0.84)


func _update_station_bars() -> void:
	var zone := _gold_zone()
	var f_slots := _cook_slots.filter(func(c: CookSlot): return c.station == "fryer")
	var max_f := 2 if Progress.shop_fryer_lv >= 1 else 1
	for i in _fryer_bars.size():
		var bar := _fryer_bars[i] as StationProgressBar
		bar.visible = i < max_f
		if i < f_slots.size():
			var cs: CookSlot = f_slots[i]
			bar.active = cs.active
			bar.progress = cs.progress
			bar.zone_lo = zone.x
			bar.zone_hi = zone.y
			bar.queue_redraw()
	var b_bar := _board_bar as StationProgressBar
	b_bar.active = _cook_slots[2].active
	b_bar.progress = _cook_slots[2].progress
	b_bar.zone_lo = zone.x
	b_bar.zone_hi = zone.y
	b_bar.queue_redraw()

	var s_bar := _soda_bar as StationProgressBar
	s_bar.active = _cook_slots[3].active
	s_bar.progress = _cook_slots[3].progress
	s_bar.zone_lo = zone.x
	s_bar.zone_hi = zone.y
	s_bar.queue_redraw()


func _on_toggle_shift() -> void:
	if _shift_active:
		_finish_shift()
	else:
		_start_shift()


func _start_shift() -> void:
	_stop_shift_cleanly()
	_shift_active = true
	_shift_t = SHIFT_DURATION
	_shift_revenue = 0
	_shift_served = 0
	_shift_crisp_hits = 0
	_shift_combo = 0
	_shift_max_combo = 0
	_shift_disguise_hits = 0
	_next_booth1_is_jelly = true
	_next_booth2_is_shark = true
	for i in _cust_slots.size():
		_cust_slots[i].leave_cd = 0.0 if i <= 1 else 2.2
	_spawn_cd = 3.8
	# 开业先迎 1 位常客（水母姐妹或小海马），其余缓慢入座
	_try_spawn_customer(1)
	_crew_pose = "cheer"
	_crew_pose_t = 1.2
	_crew_speech.text = "2分半营业开始！慢火看准金区拍 Space 出★金脆！"
	AudioManager.play_sfx("shop_serve", 0.0)
	_refresh_ui()


func _finish_shift() -> void:
	_shift_active = false
	for cu in _cust_slots:
		cu.occupied = false
		cu.eating = false
		cu.orders.clear()
	Progress.record_shift_result(0, _shift_revenue, 0, 0)
	_crew_pose = "cheer" if _shift_served > 0 else "welcome"
	_crew_pose_t = 1.8
	_summary_lbl.text = "服务海洋顾客：%d 位   ·   ★ 金脆特级：%d 份（最高连击 ×%d）\n本轮总收入：+%d 贝壳币%s\n当前钱包总计：%d 贝壳币" % [
		_shift_served,
		_shift_crisp_hits,
		_shift_max_combo,
		_shift_revenue,
		("\n神秘彩蛋：乔装黑鲸娘来偷吃啦 ×%d！" % _shift_disguise_hits) if _shift_disguise_hits > 0 else "",
		Progress.shell_coins,
	]
	_summary_modal.visible = true
	if _shift_served > 0:
		_spawn_shop_fx("shop/confetti", Vector2(640, 320), Vector2(1.5, 1.5), 1.1)
	AudioManager.play_sfx("shop_crisp", 0.0)
	_refresh_ui()


func _try_spawn_customer(preferred_slot: int = -1) -> void:
	# 前 30 秒舒缓期同时最多 2 位在场，之后可出现 3 位同堂热闹营业
	var occ_count := 0
	var free_idxs: Array[int] = []
	for i in _cust_slots.size():
		var cu := _cust_slots[i]
		if cu.occupied:
			occ_count += 1
		elif cu.leave_cd <= 0.0:
			free_idxs.append(i)
	var max_concurrent := 2 if _shift_t > (SHIFT_DURATION - 30.0) else 3
	if occ_count >= max_concurrent or free_idxs.is_empty():
		return

	var slot_i := -1
	if preferred_slot >= 0 and free_idxs.has(preferred_slot):
		slot_i = preferred_slot
	else:
		slot_i = int(free_idxs[randi_range(0, free_idxs.size() - 1)])
	var cu := _cust_slots[slot_i]

	# 每种顾客固定对应专属座位与轮转：
	#   · Slot 0（左外卖窗）：打工小海马
	#   · Slot 1（右一卡座）：水母姐妹 ↔ 海龟爷爷（保证水母姐妹开场即稳定高频登场）
	#   · Slot 2（右二卡座）：锤头鲨大叔 ↔ 乔装黑鲸娘彩蛋
	var cid := "seahorse"
	if slot_i == 1:
		cid = "jelly" if _next_booth1_is_jelly else "turtle"
		_next_booth1_is_jelly = not _next_booth1_is_jelly
	elif slot_i == 2:
		var bw_chance := 0.45 if Progress.total_boss_enrages > 0 else (0.35 if Progress.shop_decor_lv >= 1 else 0.25)
		if not _next_booth2_is_shark and randf() < bw_chance + 0.35:
			cid = "blackwhale"
		elif _next_booth2_is_shark:
			cid = "shark"
		else:
			cid = "blackwhale" if randf() < bw_chance else "shark"
		_next_booth2_is_shark = not _next_booth2_is_shark

	var has_star := int(Progress.ingredients.get("star_algae", 0)) > 0
	var spec := ShopCatalog.get_customer(cid)
	cu.occupied = true
	cu.cust_id = cid
	cu.eating = false
	cu.happy = false
	cu.max_patience = float(spec["patience"])
	cu.patience = cu.max_patience
	cu.orders.clear()

	# 选择贴合库存优先级的菜品（绝少刷出玩家完全做不出的星光藻菜品）
	var pool: Array[String] = []
	for pid in spec["preferred"]:
		var d := ShopCatalog.get_dish(String(pid))
		var needs_star := int(d["cost"].get("star_algae", 0)) > 0
		if needs_star and not has_star and not _tray_has_dish(String(pid)):
			continue
		pool.append(String(pid))
	if pool.is_empty():
		pool = ["fries", "nuggets", "burger"]
	var pick1 := String(pool[randi_range(0, pool.size() - 1)])
	cu.orders.append(pick1)
	if cid == "shark" and randf() < 0.35:
		cu.orders.append(String(pool[randi_range(0, pool.size() - 1)]))

	var lines: Array = spec.get("lines_wait", [])
	if cid == "blackwhale" and _use_crew_uniform and spec.has("lines_wait_crew"):
		lines = spec["lines_wait_crew"]
	cu.bubble_text = String(lines[randi_range(0, lines.size() - 1)]) if not lines.is_empty() else "点餐！"
	_spawn_float_text(_cust_cards[slot_i].position + Vector2(-8.0, -24.0), cu.bubble_text, Color(0.84, 0.95, 1.0))
	_refresh_customers_ui()


func _tray_has_dish(dish_id: String) -> bool:
	for ts in _tray:
		if ts.dish_id == dish_id:
			return true
	return false


func _on_craft_dish(dish_id: String) -> void:
	var d := ShopCatalog.get_dish(dish_id)
	if d.is_empty():
		return
	var st := String(d["station"])
	var max_f := 2 if Progress.shop_fryer_lv >= 1 else 1
	var target_slot: CookSlot = null
	for i in _cook_slots.size():
		var cs := _cook_slots[i]
		if cs.station != st:
			continue
		if st == "fryer" and i >= max_f:
			continue
		if not cs.active:
			target_slot = cs
			break
	if target_slot == null:
		_show_toast("%s 正在忙碌中，稍等或拍一下推进~" % String(ShopCatalog.STATIONS[st]["name"]))
		AudioManager.play_sfx("ui_move", -3.0, 0.85)
		return
	if not Progress.spend_ingredients(d["cost"]):
		_show_toast("原料不足（需 %s），先出海采些植物吧！" % ShopCatalog.format_cost(d["cost"]))
		AudioManager.play_sfx("ui_move", -3.0, 0.78)
		return

	# 不再用加快读条惩罚手速：升级专注扩双锅、宽金区与加价
	target_slot.dish_id = dish_id
	target_slot.duration = float(d["cook_sec"])
	target_slot.progress = 0.0
	target_slot.crisp = false
	target_slot.ready_hold = false
	target_slot.zone_cued = false
	target_slot.active = true

	_crew_pose = "cook"
	_crew_pose_t = 0.9
	AudioManager.play_sfx("shop_cook", -1.0, randf_range(0.95, 1.06))
	_refresh_ui()


func _trigger_crisp_hit(st_filter: String = "") -> bool:
	var zone := _gold_zone()
	var best_cs: CookSlot = null
	for i in _cook_slots.size():
		var cs := _cook_slots[i]
		if not cs.active or cs.ready_hold:
			continue
		if st_filter != "" and cs.station != st_filter:
			continue
		if cs.progress >= zone.x and cs.progress <= zone.y:
			best_cs = cs
			break
	if best_cs == null:
		return false
	best_cs.crisp = true
	best_cs.progress = 1.0
	if _try_place_on_tray(best_cs.dish_id, true):
		best_cs.active = false
		best_cs.dish_id = ""
		best_cs.progress = 0.0
	else:
		best_cs.ready_hold = true
	AudioManager.play_sfx("shop_crisp", 0.0)
	Progress.record_shop_instant(0, 0, 1)
	var st_x := 492.0 if best_cs.station == "fryer" else (656.0 if best_cs.station == "board" else 818.0)
	_spawn_shop_fx("shop/confetti", Vector2(st_x, 520.0), Vector2(1.1, 1.1), 1.35)
	_crew_pose = "cheer"
	_crew_pose_t = 0.9
	_show_toast("★ 金脆特级出锅！交付顾客售价 +30%！")
	_refresh_ui()
	return true


func _try_place_on_tray(dish_id: String, crisp: bool) -> bool:
	for ts in _tray:
		if ts.dish_id == "":
			ts.dish_id = dish_id
			ts.crisp = crisp
			return true
	return false


func _on_customer_clicked(ev: InputEvent, slot_idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_serve_customer_slot(slot_idx)


func _serve_customer_slot(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= _cust_slots.size():
		return false
	var cu := _cust_slots[slot_idx]
	if not cu.occupied or cu.eating or cu.orders.is_empty():
		return false
	# 优先拿 ★ 金脆匹配的成品
	var picked_tray := -1
	var matched_order := -1
	for is_crisp_pass in [true, false]:
		for ti in _tray.size():
			var ts := _tray[ti]
			if ts.dish_id == "" or ts.crisp != is_crisp_pass:
				continue
			var oi := cu.orders.find(ts.dish_id)
			if oi >= 0:
				picked_tray = ti
				matched_order = oi
				break
		if picked_tray >= 0:
			break
	if picked_tray < 0:
		_show_toast("托盘里还没有 %s 点的菜哦~" % String(ShopCatalog.get_customer(cu.cust_id)["name"]))
		AudioManager.play_sfx("ui_move", -3.0, 0.85)
		return false

	var ts := _tray[picked_tray]
	var dish := ShopCatalog.get_dish(ts.dish_id)
	var is_crisp := ts.crisp
	ts.dish_id = ""
	ts.crisp = false
	cu.orders.remove_at(matched_order)

	# 计算收益：基础价 × 金脆 × 装潢小费 × 顾客小费（黑鲸娘 2×）× 连击微增
	var mult := 1.0
	if is_crisp:
		mult *= 1.30
		_shift_crisp_hits += 1
		_shift_combo += 1
		_shift_max_combo = maxi(_shift_max_combo, _shift_combo)
	else:
		_shift_combo = 0
	if Progress.shop_fryer_lv >= 2 and is_crisp:
		mult *= 1.15
	if Progress.shop_decor_lv == 1:
		mult *= 1.15
	elif Progress.shop_decor_lv >= 2:
		mult *= 1.30
	var c_spec := ShopCatalog.get_customer(cu.cust_id)
	mult *= float(c_spec.get("tip_mult", 1.0))
	var earned := maxi(1, roundi(float(dish["price"]) * mult))

	Progress.add_shell_coins(earned)
	_shift_revenue += earned
	_crew_pose = "serve"
	_crew_pose_t = 0.85
	AudioManager.play_sfx("shop_serve", -1.0)
	AudioManager.play_sfx("shop_coin", -2.0, randf_range(0.96, 1.08))

	var card := _cust_cards[slot_idx]
	var pop_pos := card.position + Vector2(card.size.x * 0.5 - 60.0, 86.0)
	_spawn_shop_fx("shop/coin_burst", card.position + Vector2(card.size.x * 0.5, 132.0), Vector2(1.35, 1.35), 1.35)
	_spawn_float_text(pop_pos, "+%d 贝壳币%s" % [earned, " ★金脆!" if is_crisp else ""],
		Color(1.0, 0.90, 0.36) if is_crisp else Color(0.65, 0.98, 0.82))

	if cu.orders.is_empty():
		cu.eating = true
		cu.eat_t = 1.35
		cu.happy = is_crisp
		_shift_served += 1
		var is_bw := cu.cust_id == "blackwhale"
		if is_bw:
			_shift_disguise_hits += 1
			_crew_speech.text = "咦？那条黑鲸尾好眼熟…双倍小费真香！"
		if is_crisp or is_bw or cu.cust_id == "jelly":
			_spawn_shop_fx("shop/customer_happy", card.position + Vector2(card.size.x * 0.5, 108.0), Vector2(1.45, 1.45), 1.1)
		Progress.record_shop_instant(1, 1 if is_bw else 0, 0)
		var eat_lines: Array = c_spec.get("lines_eat", [])
		if not eat_lines.is_empty():
			var eline := String(eat_lines[randi_range(0, eat_lines.size() - 1)])
			_spawn_float_text(card.position + Vector2(-8.0, -24.0), eline, Color(1.0, 0.95, 0.82))

	_refresh_ui()
	return true


func _on_tray_serve_auto(tray_idx: int) -> void:
	if tray_idx < 0 or tray_idx >= _tray.size():
		return
	var ts := _tray[tray_idx]
	if ts.dish_id == "":
		return
	for i in _cust_slots.size():
		var cu := _cust_slots[i]
		if cu.occupied and not cu.eating and cu.orders.has(ts.dish_id):
			_serve_customer_slot(i)
			return
	_show_toast("当前没有客人点 %s，可留给下一位或[吃下做Buff]" % String(ShopCatalog.get_dish(ts.dish_id)["name"]))


func _on_eat_tray_buff(tray_idx: int) -> void:
	if tray_idx < 0 or tray_idx >= _tray.size():
		return
	var ts := _tray[tray_idx]
	if ts.dish_id == "":
		return
	var d := ShopCatalog.get_dish(ts.dish_id)
	var dish_id := ts.dish_id
	ts.dish_id = ""
	ts.crisp = false
	Progress.set_active_meal_buff(dish_id)
	_crew_pose = "cheer"
	_crew_pose_t = 1.2
	_crew_speech.text = "已享用【%s】：%s！" % [String(d["name"]), String(d["buff_desc"])]
	_show_toast("赛前 Buff 已就绪：%s（下局正常出海自动生效）" % String(d["buff_name"]))
	AudioManager.play_sfx("shop_crisp", -1.0, 1.08)
	_refresh_ui()


func _on_start_run_pressed() -> void:
	close(false)
	start_run_requested.emit()


func _spawn_shop_fx(fx_key: String, pos: Vector2, p_scale: Vector2 = Vector2.ONE, spd: float = 1.2) -> void:
	if _fx_layer == null:
		return
	var fx := PixelFxPlayer.new()
	fx.position = pos
	fx.scale = p_scale
	_fx_layer.add_child(fx)
	if not fx.play(fx_key, true, spd, 0.0, true):
		fx.queue_free()


func _spawn_float_text(pos: Vector2, txt: String, col: Color) -> void:
	if _float_layer == null:
		return
	var l := _mk_lbl(txt, 16, col, 4)
	l.position = pos
	_float_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 42.0, 1.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.05).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)


func _show_toast(msg: String) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = msg
	_toast_lbl.visible = true
	_toast_t = 2.6


# ---------------------------------------------------------------- 刷新与输入
func _refresh_ui() -> void:
	if not is_node_ready():
		return
	var d_names := ["初创木摊", "珊瑚雅座 ★", "金牌名店 ★★"]
	_lbl_decor_badge.text = d_names[clampi(Progress.shop_decor_lv, 0, 2)]
	_lbl_coins.text = "%d" % Progress.shell_coins

	if not _shift_active:
		_lbl_shift_status.text = "备餐休整中 · 点菜下锅或吃套餐Buff后直接出海！"
		_btn_shift.text = "开始 2:30 营业"
	else:
		_btn_shift.text = "提前打烊"

	if Progress.active_meal_buff != "":
		var bd := ShopCatalog.get_dish(Progress.active_meal_buff)
		_lbl_buff_pill.text = "出航Buff：%s（%s）" % [String(bd.get("name", "")), String(bd.get("buff_name", ""))]
		_lbl_buff_pill.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
	else:
		_lbl_buff_pill.text = "出航Buff：无"
		_lbl_buff_pill.add_theme_color_override("font_color", Color(0.68, 0.84, 0.90))

	# 原料角标
	for pk: String in _plant_count_lbls.keys():
		(_plant_count_lbls[pk] as Label).text = "×%d" % int(Progress.ingredients.get(pk, 0))

	# 6 道菜谱按钮可用态
	for i in _dish_btns.size():
		var d: Dictionary = ShopCatalog.DISHES[i]
		var can := Progress.has_ingredients(d["cost"])
		_dish_btns[i].disabled = not can
		_dish_cost_lbls[i].add_theme_color_override("font_color",
			Color(0.72, 0.94, 0.80) if can else Color(0.92, 0.48, 0.46))

	# 工位外观
	var f_tex_key := "tex_1" if Progress.shop_fryer_lv >= 1 else "tex_0"
	var f_tex := _tex(String(ShopCatalog.STATIONS["fryer"][f_tex_key]))
	_station_fryer_tex.texture = f_tex
	_station_fryer_title.text = "① 双联酥炸锅" if Progress.shop_fryer_lv >= 1 else "① 酥炸锅"
	_fryer_hint.text = "双锅×2 · 金脆+30%" if Progress.shop_fryer_lv >= 1 else "点锅/Space 金脆+30%"

	# 托盘 3 槽
	for ti in MAX_TRAY_SLOTS:
		var ts := _tray[ti]
		if ts.dish_id == "":
			_tray_dish_icons[ti].texture = null
			_tray_crisp_icons[ti].visible = false
			_tray_name_lbls[ti].text = "空托盘"
			_tray_btns[ti].disabled = true
			_tray_eat_btns[ti].disabled = true
		else:
			var d := ShopCatalog.get_dish(ts.dish_id)
			_tray_dish_icons[ti].texture = _tex(String(d["icon"]))
			_tray_crisp_icons[ti].visible = ts.crisp
			_tray_name_lbls[ti].text = ("★" if ts.crisp else "") + String(d["name"])
			_tray_btns[ti].disabled = false
			_tray_eat_btns[ti].disabled = false

	# 可升级小红点提示
	var any_upg := false
	for u: Dictionary in ShopCatalog.UPGRADES:
		var cur := _upgrade_cur_lv(String(u["id"]))
		var costs: Array = u["costs"]
		if cur < int(u["max_lv"]) and Progress.shell_coins >= int(costs[cur]):
			any_upg = true
			break
	_btn_upgrade.text = "★ 店铺升级" if any_upg else "店铺升级"

	_refresh_crew_visual()
	_refresh_customers_ui()


func _refresh_crew_visual() -> void:
	if _crew_sprite == null:
		return
	if _use_crew_uniform:
		_crew_sprite.texture = TEX_CREW.get(_crew_pose, TEX_CREW["welcome"])
		_crew_skin_btn.text = "店长：制服"
	else:
		var art := SkinCatalog.get_artwork(Progress.equipped_skin)
		_crew_sprite.texture = _tex(String(art.get("preview", art.get("avatar", ""))))
		_crew_skin_btn.text = "店长：" + String(art.get("name", "女仆"))


func _refresh_customers_ui() -> void:
	for i in _cust_slots.size():
		var cu := _cust_slots[i]
		var card := _cust_cards[i]
		var sp := _cust_sprites[i]
		card.visible = cu.occupied
		sp.visible = cu.occupied
		if not cu.occupied:
			continue
		var spec := ShopCatalog.get_customer(cu.cust_id)
		var spos: Vector2 = spec.get("seat_pos", sp.position)
		var ssz: Vector2 = spec.get("seat_size", sp.size)
		sp.position = spos
		sp.size = ssz
		_cust_sprite_base_y[i] = spos.y
		sp.texture = _tex(String(spec["eat_tex" if cu.eating else "wait_tex"]))
		_cust_name_lbls[i].text = String(spec["name"])
		_cust_pat_bars[i].visible = not cu.eating
		_cust_pat_bars[i].value = clampf(cu.patience / maxf(cu.max_patience, 1.0), 0.0, 1.0)

		var ob := _cust_order_boxes[i]
		for ch in ob.get_children():
			ch.queue_free()
		var can_serve_now := false
		for oid in cu.orders:
			var d := ShopCatalog.get_dish(oid)
			var ic := TextureRect.new()
			ic.texture = _tex(String(d["icon"]))
			ic.custom_minimum_size = Vector2(30, 30)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			ob.add_child(ic)
			if _tray_has_dish(oid):
				can_serve_now = true
		_cust_serve_hints[i].visible = (not cu.eating) and can_serve_now


func _upgrade_cur_lv(track_id: String) -> int:
	match track_id:
		"fryer":
			return Progress.shop_fryer_lv
		"decor":
			return Progress.shop_decor_lv
		"cooler":
			return Progress.cooler_upgrade_lv
	return 0


func _refresh_upgrades_modal() -> void:
	for r in _upg_rows:
		var tid := String(r["id"])
		var spec := {}
		for u: Dictionary in ShopCatalog.UPGRADES:
			if String(u["id"]) == tid:
				spec = u
				break
		var cur := _upgrade_cur_lv(tid)
		var mx := int(spec["max_lv"])
		var costs: Array = spec["costs"]
		var descs: Array = spec["descs"]
		(r["name"] as Label).text = "%s（Lv %d / %d）" % [String(spec["name"]), cur, mx]
		var btn := r["btn"] as Button
		if cur >= mx:
			(r["desc"] as Label).text = "已升至满级！"
			btn.text = "已满级"
			btn.disabled = true
		else:
			var price := int(costs[cur])
			(r["desc"] as Label).text = String(descs[cur])
			btn.text = "%d 贝壳币升级" % price
			btn.disabled = Progress.shell_coins < price


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("back_to_menu"):
		if _upgrade_modal.visible:
			_upgrade_modal.visible = false
		elif _summary_modal.visible:
			_summary_modal.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if _upgrade_modal.visible or _summary_modal.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE:
			if _trigger_crisp_hit(""):
				get_viewport().set_input_as_handled()
		elif k == KEY_Q:
			_serve_customer_slot(0)
			get_viewport().set_input_as_handled()
		elif k == KEY_W:
			_serve_customer_slot(1)
			get_viewport().set_input_as_handled()
		elif k == KEY_E:
			_serve_customer_slot(2)
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k <= KEY_6:
			_on_craft_dish(String(ShopCatalog.DISHES[k - KEY_1]["id"]))
			get_viewport().set_input_as_handled()
