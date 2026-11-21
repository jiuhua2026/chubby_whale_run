extends Control
class_name ChaseVignette
## 追击压迫感的**暗角**：四周由外向内渐变压暗，强度 = 她离你多近。
##
## ## 为什么不用 shader
## `--headless` 下 shader 编译不可依赖（自检、抓帧、地形验证全靠它跑），
## 而这里只需要"四边往中间变暗"——18 条渐变矩形（72 个 draw_rect）就够了，成本可忽略。
##
## ## 为什么强度用"缺口"驱动，不用"追击是否开始"
## 追击刚开始她还在画面外（136px），那时候压暗没有意义；
## 她一贴上来，画面才该收窄。所以强度接 `Chaser.pressure()`（0 = 520px 远，1 = 贴到 130px）。
## 平滑交给 `Main`（它按帧 move_toward），这里只负责画。

const BANDS := 18
## 渐变带占屏幕的比例（左/右、上/下）。太窄会像一条硬边，太宽会糊到画面中间。
const SIDE := 0.26
const TOP := 0.24
## 最外圈的暗度上限（乘 strength）。
const EDGE_ALPHA := 0.5

var strength := 0.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if is_equal_approx(v, strength):
			return
		strength = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if strength <= 0.002:
		return
	var s := size
	var w := s.x * SIDE
	var h := s.y * TOP
	var max_a := strength * EDGE_ALPHA
	var col := Color(0.01, 0.03, 0.06)
	for i in BANDS:
		var t0 := float(i) / float(BANDS)
		var t1 := float(i + 1) / float(BANDS)
		# 1.7 次幂：靠近画面中心几乎不变暗，越靠边越快变黑 —— 直着来会像半透明黑框
		var a := max_a * pow(t0, 1.7)
		var r := Color(col, a)
		var bw := w * (t1 - t0) + 1.0
		var bh := h * (t1 - t0) + 1.0
		draw_rect(Rect2(w * t0, 0, bw, s.y), r)              # 左
		draw_rect(Rect2(s.x - w * t1, 0, bw, s.y), r)        # 右
		draw_rect(Rect2(0, h * t0, s.x, bh), r)              # 上
		draw_rect(Rect2(0, s.y - h * t1, s.x, bh), r)        # 下
