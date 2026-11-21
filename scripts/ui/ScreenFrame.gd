extends Control
class_name ScreenFrame
## 屏幕的**恒定画框**：上边缘渐隐到黑（下边缘几乎不做）。
##
## ## 为什么需要
## 背景换成岩壁纹理后，**纹理的上边界会露出来** —— 实测截图顶部有一条约 36px 的
## 均匀亮带（亮度 16~17），下面才是带纹理的 10~18 ✗ 读作"背景到此为止"。
## 顶部渐隐之后纹理自然溶进黑暗，HUD 文字也更清楚。
##
## ## 和 `ChaseVignette` 的分工
## 那个只在**追击**时按贴近度加深（动态）；这个是**不变的画框**（静态）。两者会叠加。
## ⚠ 只做**顶部**：底部是地形板的顶边高光，压暗会直接削弱"哪里能站"的可读性。

const TOP_H := 220.0       ## 渐隐高度（150 时上半部还像「一片贴图」，200 才像「没入黑暗」）
const TOP_A := 0.80        ## 最上缘的压暗强度

var _grad_tex: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.50, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(0.008, 0.020, 0.040, TOP_A),
		Color(0.008, 0.020, 0.040, TOP_A * pow(0.75, 1.8)),
		Color(0.008, 0.020, 0.040, TOP_A * pow(0.50, 1.8)),
		Color(0.008, 0.020, 0.040, TOP_A * pow(0.25, 1.8)),
		Color(0.008, 0.020, 0.040, 0.0),
	])
	_grad_tex = GradientTexture2D.new()
	_grad_tex.gradient = grad
	_grad_tex.fill_from = Vector2(0.0, 0.0)
	_grad_tex.fill_to = Vector2(0.0, 1.0)
	_grad_tex.width = 4
	_grad_tex.height = 128

	# ⚠ **必须显式设 size 再主动重绘**。这个 Control 挂在 CanvasLayer 下：
	#   进树那一刻 size 还是 (0,0)，`_draw()` 只会在进树时被调一次 ⇒ 画了个空内容，
	#   之后**没有任何东西触发重绘** ⇒ 整块永远不显示（实测把 TOP_A 拉到 1.0 也一点不变）。
	#   `ChaseVignette` 之所以正常，是因为它在强度变化时会 `queue_redraw()`。
	size = get_viewport_rect().size
	queue_redraw()
	# ⚠ 进树那一刻视口尺寸可能还没定 ⇒ **延后一帧再定一次**。
	#   Control 会按自身矩形裁剪，size=(0,0) 时 `draw_rect` 什么都出不来。
	await get_tree().process_frame
	size = get_viewport_rect().size
	queue_redraw()


func _draw() -> void:
	if _grad_tex != null:
		draw_texture_rect(_grad_tex, Rect2(0.0, 0.0, size.x, TOP_H), false)
