extends CanvasLayer
class_name OpeningIntro
## OpeningIntro —— 方案 B 电影级四幕开场片头（仅首次自动播放 / 设置面板「重温」触发）。
##
## 镜头节奏：
##   Act 1 (0.00 ~ 2.20s) 远景孤逃 —— 辽阔深海远景、蓝鲸娘远景奔跑、极速海草前景
##   Act 2 (2.20 ~ 4.45s) 推近追逼 —— 镜头平滑拉近成中景、黑鲸娘浮现紧追（纯奔跑零违和建筑）
##   Act 3 (4.45 ~ 5.65s) 贴脸萌扑 —— 原彩黑鲸娘超近景飞扑横扫 + 碧蓝像素泡泡浪墙无痕擦屏
##   Act 4 (5.20 ~ 7.75s) 破浪定格 —— 浪潮掀开瞬间重音爆破微震 + 封面微推 + C+D 字幕 + 合入主菜单

signal reveal_ready()
signal finished()

const VW := 1280.0
const VH := 720.0

const TEX_HORIZON := preload("res://sprites/intro/intro_horizon_bg.png")
const TEX_KELP := preload("res://sprites/intro/fg_kelp_strip.png")
const TEX_CHASER_RUSH := preload("res://sprites/intro/chaser_wipe_rush.png")
const TEX_WAVE := preload("res://sprites/intro/chaser_wipe_wave.png")
const TEX_SPLASH_2X := preload("res://sprites/intro/title_splash_2x.png")
const TEX_BUBBLE := preload("res://sprites/fx/bubble.png")

const BLUE_RUN := [
	preload("res://sprites/run/run_00.png"),
	preload("res://sprites/run/run_01.png"),
	preload("res://sprites/run/run_02.png"),
	preload("res://sprites/run/run_03.png"),
	preload("res://sprites/run/run_04.png"),
	preload("res://sprites/run/run_05.png"),
	preload("res://sprites/run/run_06.png"),
	preload("res://sprites/run/run_07.png"),
]
const BLACK_RUN := [
	preload("res://sprites/chaser_run/chaser_run_01.png"),
	preload("res://sprites/chaser_run/chaser_run_02.png"),
	preload("res://sprites/chaser_run/chaser_run_03.png"),
	preload("res://sprites/chaser_run/chaser_run_04.png"),
	preload("res://sprites/chaser_run/chaser_run_05.png"),
	preload("res://sprites/chaser_run/chaser_run_06.png"),
	preload("res://sprites/chaser_run/chaser_run_07.png"),
	preload("res://sprites/chaser_run/chaser_run_08.png"),
]

const INTRO_LINE_MAIN := "深海暗流之下 —— 别回头，拼命游。"
const INTRO_LINES_EASTER := [
	"蓝鲸娘：“等一下……怎么每次片头定格都是我被揪尾巴啊？！”",
	"黑鲸娘：“抓住啦！其实这游戏该叫《大肥鱼捕食日记》才对——嗷呜！”",
	"蓝鲸娘：“导演！这片头我重游第几遍了，尾巴都要抽筋了……”",
	"黑鲸娘：“深渊无退路，肥鱼岂能遁逃？——咬！”",
]

const T_ACT2 := 2.20
const T_WIPE_START := 4.45
const T_WIPE_WHOOSH := 4.40
const T_IMPACT := 5.20
const T_WIPE_END := 5.75
const T_HANDOFF := 6.95
const T_TOTAL := 7.75

var _root: Control
var _chase_stage: Control
var _world: Node2D
var _bg_strip: Node2D
var _blue_sprite: Sprite2D
var _black_sprite: Sprite2D
var _fg_kelp: Node2D
var _bubble_layer: Node2D

var _splash_clip: Control
var _splash_sprite: Sprite2D
var _splash_vignette: TextureRect
var _subtitle_lbl: Label

class _GroundShadow extends Node2D:
	var rx := 32.0
	var ry := 8.0
	var alpha := 0.36
	func _draw() -> void:
		var n := 20
		var pts := PackedVector2Array()
		for i in n:
			var a := TAU * float(i) / float(n)
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, Color(0.01, 0.05, 0.11, alpha))

var _blue_shadow: _GroundShadow
var _black_shadow: _GroundShadow

var _wipe_layer: Control
var _wave_sprite: Sprite2D
var _rush_sprite: Sprite2D

var _flash_rect: ColorRect
var _fade_veil: ColorRect
var _skip_lbl: Label

var _playing := false
var _is_replay := false
var _t := 0.0
var _skipping := false
var _bg_scroll := 0.0
var _kelp_scroll := 0.0
var _whoosh_played := false
var _impact_played := false
var _handoff_started := false
var _shake_amp := 0.0
var _bubbles: Array[Dictionary] = []


func _ready() -> void:
	layer = 250
	visible = false
	_build_tree()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_resized)
	_fit_layout()


func _vp_size() -> Vector2:
	var vp := get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.x > 0.0 and sz.y > 0.0:
			return sz
	return Vector2(VW, VH)


func _on_viewport_resized() -> void:
	_fit_layout()
	if visible:
		_update_visuals(0.0)


func _fit_layout() -> void:
	if _root == null:
		return
	var vp := _vp_size()
	if _splash_clip != null:
		_splash_clip.size.y = vp.y
	if _splash_sprite != null:
		_splash_sprite.position = vp * 0.5
	if _splash_vignette != null:
		_splash_vignette.position = Vector2(0.0, vp.y - 190.0)
		_splash_vignette.size = Vector2(vp.x, 190.0)
	if _subtitle_lbl != null:
		_subtitle_lbl.position = Vector2(80.0, vp.y - 72.0)
		_subtitle_lbl.size = Vector2(maxf(200.0, vp.x - 160.0), 44.0)
	if _skip_lbl != null:
		_skip_lbl.position = Vector2(vp.x - 236.0, vp.y - 42.0)


func _build_tree() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.clip_contents = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# 1. Stage 1~2 远景与中景奔跑舞台（底层深海色块兜底，杜绝非 16:9 屏下边缘穿帮）
	_chase_stage = Control.new()
	_chase_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chase_stage.clip_contents = true
	_chase_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chase_stage)

	var abyss_bg := ColorRect.new()
	abyss_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	abyss_bg.color = Color(0.015, 0.055, 0.115, 1.0)
	abyss_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chase_stage.add_child(abyss_bg)

	_world = Node2D.new()
	_chase_stage.add_child(_world)

	_bg_strip = _TiledStrip.new()
	_bg_strip.tex = TEX_HORIZON
	_bg_strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_world.add_child(_bg_strip)

	# 追逐气泡粒子层（介于角色与远景之间）
	_bubble_layer = _BubbleCanvas.new()
	_bubble_layer.bubbles = _bubbles
	_bubble_layer.tex = TEX_BUBBLE
	_world.add_child(_bubble_layer)

	# 地面接触柔影（让奔跑双姝脚踏海底沙地而不是悬空）
	_black_shadow = _GroundShadow.new()
	_black_shadow.rx = 34.0
	_black_shadow.ry = 7.5
	_black_shadow.alpha = 0.28
	_world.add_child(_black_shadow)

	_blue_shadow = _GroundShadow.new()
	_blue_shadow.rx = 26.0
	_blue_shadow.ry = 6.5
	_blue_shadow.alpha = 0.34
	_world.add_child(_blue_shadow)

	# 黑鲸娘追兵（像素锐利渲染，居蓝鲸娘左后方）
	_black_sprite = Sprite2D.new()
	_black_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_black_sprite.texture = BLACK_RUN[0]
	_black_sprite.centered = false
	_world.add_child(_black_sprite)

	# 蓝鲸娘主角（像素锐利渲染，踩在平坦海底跑道）
	_blue_sprite = Sprite2D.new()
	_blue_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_blue_sprite.texture = BLUE_RUN[0]
	_blue_sprite.centered = false
	_world.add_child(_blue_sprite)

	# 前景超近景高速飞掠海藻条（紧贴镜头底部，高于世界缩放速率制造视差冲力）
	_fg_kelp = _TiledStrip.new()
	_fg_kelp.tex = TEX_KELP
	_fg_kelp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fg_kelp.scale = Vector2(1.0, 0.92)
	_chase_stage.add_child(_fg_kelp)

	# 2. Stage 4 定格封面（包在 clip_contents 容器内，左侧宽度随海浪遮罩实心中心实时揭开！）
	_splash_clip = Control.new()
	_splash_clip.position = Vector2.ZERO
	_splash_clip.size = Vector2(0.0, VH)
	_splash_clip.clip_contents = true
	_splash_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_splash_clip)

	# 使用 Sprite2D 居中按 1280/2560 = 0.5x 渲染，彻底避免 Control 最小尺寸撑大裁切问题
	_splash_sprite = Sprite2D.new()
	_splash_sprite.texture = TEX_SPLASH_2X
	_splash_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_splash_sprite.centered = true
	_splash_sprite.position = Vector2(VW * 0.5, VH * 0.5)
	_splash_sprite.scale = Vector2(0.5 * 1.055, 0.5 * 1.055)
	_splash_clip.add_child(_splash_sprite)

	# 下缘柔暗渐变条（托住 C+D 字幕可读性，绝不挡上方主角）
	_splash_vignette = TextureRect.new()
	_splash_vignette.position = Vector2(0.0, VH - 190.0)
	_splash_vignette.size = Vector2(VW, 190.0)
	_splash_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.03, 0.07, 0.0))
	grad.set_color(1, Color(0.01, 0.03, 0.07, 0.62))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	_splash_vignette.texture = gtex
	_splash_clip.add_child(_splash_vignette)

	# C+D 台词 / 氛围字幕（对齐大屏底部居中 + 清晰描边）
	_subtitle_lbl = Label.new()
	_subtitle_lbl.position = Vector2(80.0, VH - 72.0)
	_subtitle_lbl.size = Vector2(VW - 160.0, 44.0)
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_lbl.add_theme_font_size_override("font_size", 22)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	_subtitle_lbl.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.08, 0.96))
	_subtitle_lbl.add_theme_constant_override("outline_size", 5)
	_subtitle_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_clip.add_child(_subtitle_lbl)

	# 3. Stage 3 擦屏遮罩层：碧蓝像素海浪墙 + 原彩黑鲸娘超大贴脸飞扑
	_wipe_layer = Control.new()
	_wipe_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wipe_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe_layer.visible = false
	_root.add_child(_wipe_layer)

	_wave_sprite = Sprite2D.new()
	_wave_sprite.texture = TEX_WAVE
	_wave_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wave_sprite.centered = false
	_wipe_layer.add_child(_wave_sprite)

	_rush_sprite = Sprite2D.new()
	_rush_sprite.texture = TEX_CHASER_RUSH
	_rush_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rush_sprite.centered = false
	_rush_sprite.scale = Vector2(0.95, 0.95)
	_wipe_layer.add_child(_rush_sprite)

	# 4. 破浪重音瞬态白青光闪 + 开闭场黑幕
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(0.82, 0.97, 1.0, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash_rect)

	_fade_veil = ColorRect.new()
	_fade_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_veil.color = Color(0.01, 0.03, 0.07, 1.0)
	_fade_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade_veil)

	# 5. 右下角轻量跳过提示
	_skip_lbl = Label.new()
	_skip_lbl.text = "空格 / 点击 跳过"
	_skip_lbl.position = Vector2(VW - 236.0, VH - 42.0)
	_skip_lbl.size = Vector2(214.0, 28.0)
	_skip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_lbl.add_theme_font_size_override("font_size", 15)
	_skip_lbl.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 0.90))
	_skip_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.06, 0.96))
	_skip_lbl.add_theme_constant_override("outline_size", 4)
	_skip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_skip_lbl)


func is_playing() -> bool:
	return _playing


## 开始播放开场大片。
##   p_is_replay = false（冷启动首播）→ 显示主线氛围短句（风格 C）
##   p_is_replay = true （设置重温）  → 顺序轮播吐槽彩蛋（风格 D）
func play(p_is_replay: bool = false) -> void:
	_is_replay = p_is_replay
	_t = 0.0
	_skipping = false
	_bg_scroll = 0.0
	_kelp_scroll = 0.0
	_whoosh_played = false
	_impact_played = false
	_handoff_started = false
	_shake_amp = 0.0
	_bubbles.clear()

	if _is_replay:
		var idx := posmod(Settings.intro_replay_count - 1, INTRO_LINES_EASTER.size())
		_subtitle_lbl.text = INTRO_LINES_EASTER[idx]
	else:
		_subtitle_lbl.text = INTRO_LINE_MAIN

	var vp := _vp_size()
	_chase_stage.visible = true
	_wipe_layer.visible = false
	_splash_clip.size = Vector2(0.0, vp.y)
	_splash_clip.modulate.a = 1.0
	var init_s := maxf(vp.x / maxf(float(TEX_SPLASH_2X.get_width()), 1.0), vp.y / maxf(float(TEX_SPLASH_2X.get_height()), 1.0))
	_splash_sprite.scale = Vector2.ONE * (init_s * 1.055)
	_fit_layout()
	_splash_vignette.modulate.a = 0.0
	_subtitle_lbl.modulate.a = 0.0
	_flash_rect.color.a = 0.0
	_fade_veil.color.a = 1.0
	_skip_lbl.visible = true
	_root.position = Vector2.ZERO
	visible = true
	_playing = true

	_update_visuals(0.0)
	AudioManager.stop_all()
	AudioManager.play_sfx("intro_buildup", -1.5)


## 跳转至指定时间点（专供 `-- --intro-shot=...` 自动化抓帧验收使用）。
func seek_for_capture(target_sec: float, p_is_replay: bool = false) -> void:
	_is_replay = p_is_replay
	_playing = true
	_skipping = false
	visible = true
	_t = clampf(target_sec, 0.0, T_TOTAL)
	_bg_scroll = _t * 145.0
	_kelp_scroll = _t * 680.0
	_whoosh_played = _t >= T_WIPE_WHOOSH
	_impact_played = _t >= T_IMPACT
	_handoff_started = _t >= T_HANDOFF
	_splash_clip.modulate.a = 1.0
	if _is_replay:
		var idx := posmod(maxi(0, Settings.intro_replay_count - 1), INTRO_LINES_EASTER.size())
		_subtitle_lbl.text = INTRO_LINES_EASTER[idx]
	else:
		_subtitle_lbl.text = INTRO_LINE_MAIN
	_update_visuals(0.0)
	_playing = false


func _input(event: InputEvent) -> void:
	if not _playing or _skipping:
		return
	# 防手抖防透传：开启片头后的前 0.18s 内忽略按键与鼠标（防止点"重温"那一击顺便跳过片头）
	if _t < 0.18:
		return
	var skip_hit := false
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			skip_hit = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			skip_hit = true

	if skip_hit:
		get_viewport().set_input_as_handled()
		_trigger_skip()


func _trigger_skip() -> void:
	if _skipping:
		return
	_skipping = true
	_playing = false
	_skip_lbl.visible = false
	AudioManager.stop_sfx()
	AudioManager.play_sfx("ui_confirm", -4.0)
	_mark_seen()
	reveal_ready.emit()

	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		visible = false
		_root.modulate.a = 1.0
		finished.emit()
	)


func _mark_seen() -> void:
	if not Settings.intro_seen:
		Settings.intro_seen = true
		Settings.save_cfg()


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	_update_visuals(delta)
	if _t >= T_TOTAL:
		_finish_naturally()


func _finish_naturally() -> void:
	_playing = false
	visible = false
	_root.position = Vector2.ZERO
	_mark_seen()
	finished.emit()


func _update_visuals(delta: float) -> void:
	# 1. 开场前 0.28s 柔和渐亮黑幕
	if _t < 0.28:
		_fade_veil.color.a = clampf(1.0 - _t / 0.28, 0.0, 1.0)
	else:
		_fade_veil.color.a = 0.0

	# 跳过提示呼吸 + 在交接给主菜单前提前淡出
	if _t < T_HANDOFF - 0.3:
		_skip_lbl.visible = true
		_skip_lbl.modulate.a = 0.55 + 0.25 * sin(_t * 4.0)
	else:
		_skip_lbl.visible = false

	# 2. 音效节点精准卡点
	if not _whoosh_played and _t >= T_WIPE_WHOOSH:
		_whoosh_played = true
		AudioManager.play_sfx("intro_whoosh", 0.5)

	if not _impact_played and _t >= T_IMPACT:
		_impact_played = true
		AudioManager.play_sfx("intro_impact", 1.0)
		_flash_rect.color.a = 0.36
		_shake_amp = 13.0 * Settings.shake_scale

	# 3. 推送破浪瞬间的闪白 + 屏震衰减
	if _flash_rect.color.a > 0.0:
		_flash_rect.color.a = maxf(0.0, _flash_rect.color.a - 1.65 * delta)
	if _shake_amp > 0.1:
		_shake_amp = move_toward(_shake_amp, 0.0, 46.0 * delta)
		_root.position = Vector2(randf_range(-_shake_amp, _shake_amp), randf_range(-_shake_amp, _shake_amp))
	elif _root.position != Vector2.ZERO:
		_root.position = Vector2.ZERO

	var vp := _vp_size()
	var cover := maxf(vp.x / VW, vp.y / VH)
	var stage_ox := (vp.x - VW * cover) * 0.5
	var stage_oy := (vp.y - VH * cover) * 0.5
	_fit_layout()

	# 4. Stage 1~2 运镜推进（远景 → 中景追逐，随视口 cover 等比铺满任意宽高比）
	var p_chase := clampf(_t / T_WIPE_START, 0.0, 1.0)
	var zoom := lerpf(1.00, 1.35, pow(p_chase, 0.92)) * cover
	var focus := Vector2(VW * 0.5, VH * 0.5).lerp(Vector2(530.0, 428.0), p_chase)
	_world.scale = Vector2(zoom, zoom)
	_world.position = vp * 0.5 - focus * zoom

	var bg_spd := lerpf(115.0, 210.0, p_chase)
	var kelp_spd := lerpf(560.0, 980.0, p_chase)
	_bg_scroll = fmod(_bg_scroll + bg_spd * delta, float(TEX_HORIZON.get_width()))
	_kelp_scroll = fmod(_kelp_scroll + kelp_spd * delta, float(TEX_KELP.get_width()))
	_bg_strip.offset_x = -_bg_scroll

	var kelp_scale := lerpf(0.92, 1.08, p_chase) * cover
	_fg_kelp.scale = Vector2(kelp_scale, kelp_scale)
	_fg_kelp.position.y = vp.y - float(TEX_KELP.get_height()) * kelp_scale + 10.0 * cover
	_fg_kelp.offset_x = -_kelp_scroll

	# 蓝鲸娘奔跑：从左中远方跑到靠中右位置（脚踩平坦海底沙地 y=566）
	var blue_x := lerpf(270.0, 625.0, pow(p_chase, 0.85))
	var blue_s := 0.62
	var b_tex: Texture2D = BLUE_RUN[posmod(int(_t * lerpf(13.0, 18.0, p_chase)), BLUE_RUN.size())]
	_blue_sprite.texture = b_tex
	_blue_sprite.scale = Vector2(blue_s, blue_s)
	_blue_sprite.position = Vector2(
		blue_x - float(b_tex.get_width()) * blue_s * 0.5,
		566.0 - float(b_tex.get_height()) * blue_s
	)
	_blue_shadow.position = Vector2(blue_x, 565.0)
	_blue_shadow.visible = true

	# 黑鲸娘自 1.95s 起从左方潜行追出（近沙地掠行）
	var chaser_p := clampf((_t - 1.95) / (T_WIPE_START - 1.95), 0.0, 1.0)
	var chaser_a := clampf((_t - 1.95) / 0.45, 0.0, 1.0)
	var blk_tex: Texture2D = BLACK_RUN[posmod(int(_t * 10.0), BLACK_RUN.size())]
	var blk_s := 0.57
	var blk_x := lerpf(-40.0, 345.0, chaser_p)
	var blk_y := 556.0 + sin(_t * 6.5) * 4.5
	_black_sprite.texture = blk_tex
	_black_sprite.scale = Vector2(blk_s, blk_s)
	_black_sprite.modulate.a = chaser_a
	_black_sprite.position = Vector2(
		blk_x - float(blk_tex.get_width()) * blk_s * 0.5,
		blk_y - float(blk_tex.get_height()) * blk_s
	)
	_black_shadow.position = Vector2(blk_x - 4.0, 564.0)
	_black_shadow.modulate.a = chaser_a

	# 冒泡微粒
	_step_bubbles(delta, blue_x)

	# 5. Stage 3 碧蓝海浪 + 原彩黑鲸娘飞扑擦屏 (T_WIPE_START .. T_WIPE_END)
	if _t < T_WIPE_START:
		_wipe_layer.visible = false
		_splash_clip.size.x = 0.0
		_chase_stage.visible = true
	elif _t <= T_WIPE_END:
		var wp := clampf((_t - T_WIPE_START) / (T_WIPE_END - T_WIPE_START), 0.0, 1.0)
		var ease_wp := wp * wp * (3.0 - 2.0 * wp)
		# wave_x 从 -1620 → +1420：按 cover 与舞台居中偏移映射，保证任意宽高比完全擦满屏幕
		var wave_x := lerpf(-1620.0, 1420.0, ease_wp)
		_wipe_layer.visible = true
		_wave_sprite.scale = Vector2(cover, cover)
		_wave_sprite.position = Vector2(stage_ox + wave_x * cover, stage_oy)
		# 原彩黑鲸娘贴脸扑跃在浪头右侧（带微仰俯冲弧线，呆萌充满活力！）
		var arc_y := -55.0 - sin(wp * PI) * 26.0
		_rush_sprite.scale = Vector2(0.95 * cover, 0.95 * cover)
		_rush_sprite.position = Vector2(stage_ox + (wave_x + 830.0) * cover, stage_oy + arc_y * cover)

		var reveal_x := clampf(stage_ox + (wave_x + 680.0) * cover, 0.0, vp.x)
		_splash_clip.size = Vector2(reveal_x, vp.y)
		# 当浪墙揭开到 >98% 以后即可收掉 Stage 1~2 省去多余绘制
		_chase_stage.visible = reveal_x < vp.x - 8.0
	else:
		_wipe_layer.visible = false
		_chase_stage.visible = false
		_splash_clip.size = vp

	# 6. Stage 4 定格封面微推 + C+D 字幕 + 合入主菜单（与 MainMenu 的 COVERED 完全一致）
	var sp := clampf((_t - T_IMPACT) / (T_HANDOFF - T_IMPACT), 0.0, 1.0) if _t >= T_IMPACT else 0.0
	var ease_out := 1.0 - pow(1.0 - sp, 3.0)
	var sc := lerpf(1.055, 1.000, ease_out)
	var base_s := maxf(vp.x / maxf(float(TEX_SPLASH_2X.get_width()), 1.0), vp.y / maxf(float(TEX_SPLASH_2X.get_height()), 1.0))
	_splash_sprite.position = vp * 0.5
	_splash_sprite.scale = Vector2.ONE * (base_s * sc)

	if _t >= T_IMPACT:
		var sub_a := 0.0
		if _t < T_IMPACT + 0.30:
			sub_a = (_t - T_IMPACT) / 0.30
		elif _t < T_HANDOFF - 0.45:
			sub_a = 1.0
		elif _t < T_HANDOFF - 0.05:
			sub_a = clampf(1.0 - (_t - (T_HANDOFF - 0.45)) / 0.40, 0.0, 1.0)
		_splash_vignette.modulate.a = sub_a
		_subtitle_lbl.modulate.a = sub_a
	else:
		_splash_vignette.modulate.a = 0.0
		_subtitle_lbl.modulate.a = 0.0

	if not _handoff_started and _t >= T_HANDOFF:
		_handoff_started = true
		reveal_ready.emit()

	if _t >= T_HANDOFF:
		var hp := clampf((_t - T_HANDOFF) / (T_TOTAL - T_HANDOFF), 0.0, 1.0)
		_splash_clip.modulate.a = 1.0 - hp
	else:
		_splash_clip.modulate.a = 1.0


func _step_bubbles(delta: float, emitter_x: float) -> void:
	if delta > 0.0 and _t < T_WIPE_END and _bubbles.size() < 26 and randf() < delta * 14.0:
		_bubbles.append({
			"x": emitter_x - randf_range(8.0, 26.0),
			"y": 532.0 - randf_range(4.0, 42.0),
			"vx": -randf_range(60.0, 160.0),
			"vy": -randf_range(35.0, 95.0),
			"r": randf_range(5.0, 14.0),
			"t": 0.0,
			"life": randf_range(0.6, 1.2),
		})
	var next: Array[Dictionary] = []
	for b in _bubbles:
		b["t"] = float(b["t"]) + delta
		if float(b["t"]) < float(b["life"]):
			b["x"] = float(b["x"]) + float(b["vx"]) * delta
			b["y"] = float(b["y"]) + float(b["vy"]) * delta
			next.append(b)
	_bubbles = next
	(_bubble_layer as _BubbleCanvas).bubbles = _bubbles
	_bubble_layer.queue_redraw()


class _TiledStrip extends Node2D:
	var tex: Texture2D
	var offset_x := 0.0:
		set(v):
			offset_x = v
			queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var x0 := fposmod(offset_x, tw) - tw
		while x0 < 2560.0:
			draw_texture_rect(tex, Rect2(x0, 0.0, tw, th), false)
			x0 += tw


class _BubbleCanvas extends Node2D:
	var tex: Texture2D
	var bubbles: Array[Dictionary] = []

	func _draw() -> void:
		if tex == null:
			return
		for b in bubbles:
			var k := 1.0 - float(b["t"]) / maxf(float(b["life"]), 0.01)
			var r := float(b["r"])
			var p := Vector2(float(b["x"]), float(b["y"]))
			draw_texture_rect(tex, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, Color(1.0, 1.0, 1.0, 0.72 * k))
