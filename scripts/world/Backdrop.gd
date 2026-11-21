extends Node2D
class_name Backdrop
## Backdrop —— 视差背景（深海岩壁）。
##
## ## 演进（两次都是被用户点破的）
## ① 2026-10-18 上午：原来整块画在**画面下方**（远景 y 150~1500、海藻 1220~1500，
##    而可见范围只有 y −570~150 ⇒ 背景是空的）。改成相对 `SURFACE_Y` 锚定。
## ② 2026-10-18 下午：用户给了一张深海岩壁照片问"能不能换背景"，并说手写多边形"不好看"。
##    ⇒ **程序化几何的天花板就在这里**：`draw_colored_polygon` 是纯色填充，没有纹理、
##    没有渐变；山脊 7 个点直线相连 ⇒ 读成"折纸"；光柱画成宽竖条 ⇒ 读成"条纹" ✗
##    ⇒ 换成**真纹理**（`tools/make_backdrop.py` 处理：横向无缝 + 压暗 + 竖向渐变）。
##
## ## 现在只有两层
##   · **岩壁纹理**（视差 0.12）：1024×451 → 缩放 1.45×，横向平铺。
##     处理后的平均亮度 **14.5**，而地形板是 22~29 ⇒ **背景比地形暗** ✓
##   · **地面线附近的暗雾**：12 条渐变横带，把纹理"沉"到地面下面去，
##     保证"地形板和玩家"永远是画面里最亮的东西。
##
## ⚠ **亮度阶梯是硬约束**：纹理 14.5 < 地形板 22~29 < 地形顶边高光 ~100。
##   背景一变亮，地形就读不出来 —— 改贴图参数时先量这三个数。

var camera_x := 0.0
var camera_y := 0.0

const SURFACE_Y := 0.0

const TEX_ROCK := preload("res://sprites/bg/deep_rock.png")
const TEX_SIL := preload("res://sprites/bg/far_silhouettes.png")
const ROCK_PARALLAX := 0.12
const SIL_PARALLAX := 0.24
## 缩放：贴图高 451、可见高度 570 ⇒ 1.45 才能盖满（上缘要越过画面上缘）
const ROCK_SCALE := 1.45
## 只做色偏（偏冷），不再大幅压暗 —— 压暗在 `make_backdrop.py` 里已经做过了
const ROCK_TINT := Color(0.92, 1.0, 1.12)

const HAZE_TOP_OFFSET := 200.0
const HAZE_BOT_OFFSET := 120.0

const VIEW_PAD := 1600.0

var _haze_tex: GradientTexture2D


func _ready() -> void:
	z_index = -50
	set_process(false)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3125, 0.625, 1.0])
	grad.colors = PackedColorArray([
		Color(0.012, 0.031, 0.063, 0.0),
		Color(0.012, 0.031, 0.063, 0.085),
		Color(0.012, 0.031, 0.063, 0.34),
		Color(0.012, 0.031, 0.063, 0.64),
	])
	_haze_tex = GradientTexture2D.new()
	_haze_tex.gradient = grad
	_haze_tex.fill_from = Vector2(0.0, 0.0)
	_haze_tex.fill_to = Vector2(0.0, 1.0)
	_haze_tex.width = 4
	_haze_tex.height = 256


## 由 `Main` 每帧把相机位置写进来并重画（相机不动就不重画）。
func follow(p_camera_x: float, p_camera_y: float) -> void:
	if is_equal_approx(p_camera_x, camera_x) and is_equal_approx(p_camera_y, camera_y):
		return
	camera_x = p_camera_x
	camera_y = p_camera_y
	queue_redraw()


func _draw() -> void:
	var left := camera_x - VIEW_PAD
	var right := camera_x + VIEW_PAD

	# ---- 1. 远景岩壁纹理：X+Y 双向无缝平铺（覆盖高跳顶缘与深坑底缘，零水平接缝）----
	var tw := float(TEX_ROCK.get_width()) * ROCK_SCALE
	var th := float(TEX_ROCK.get_height()) * ROCK_SCALE
	var off := camera_x * (1.0 - ROCK_PARALLAX)
	var x0 := floorf((left - off) / tw) * tw + off
	var y_top := SURFACE_Y - th * 1.5
	var y_bot := SURFACE_Y + 520.0
	while x0 < right:
		var wy := y_top
		while wy < y_bot:
			draw_texture_rect(TEX_ROCK, Rect2(x0, wy, tw, th), false, ROCK_TINT)
			wy += th
		x0 += tw

	# ---- 2. 远景海底礁峰与沉船剪影视差层（像素画风低对比轮廓）----
	var sw := float(TEX_SIL.get_width())
	var sh := float(TEX_SIL.get_height())
	var sil_off := camera_x * (1.0 - SIL_PARALLAX)
	var sx := floorf((left - sil_off) / sw) * sw + sil_off
	var sil_y := SURFACE_Y - sh + 100.0
	while sx < right:
		draw_texture_rect(TEX_SIL, Rect2(sx, sil_y, sw, sh), false)
		sx += sw

	# ---- 3. 平滑景深雾（替代 12 条离散矩形，消灭百叶窗色带）----
	if _haze_tex != null:
		draw_texture_rect(_haze_tex,
			Rect2(left, SURFACE_Y - HAZE_TOP_OFFSET, right - left, HAZE_TOP_OFFSET + HAZE_BOT_OFFSET),
			false)
