extends StaticBody2D
class_name TerrainChunk
## 一个地形块：建碰撞体 + 占位绘制。
##
## 关键设计：**障碍不是实心的，是 Area2D**。
##   因为玩法定的是「撞到障碍只减速、只有被追上才死」。如果障碍是实体墙，
##   玩家会卡在墙上原地不动，等价于必死，与设计冲突。
##   做成 Area2D 后，撞上 = 触发减速 + 短暂无敌 + 闪白，然后穿过去继续跑，
##   压力交给身后的死亡边界。这是"只死于被追上"能成立的前提。
##
## 碰撞层约定（见 GameConfig 注释）：
##   1 层 = 地面   2 层 = 玩家   3 层 = 障碍
##
## 为什么每块是 StaticBody2D 而不是 TileMapLayer：
##   垂直切片阶段地形是「列层高 + 障碍」的参数化数据，直接按参数生成矩形碰撞体，
##   比先烘焙 TileMap 再对齐图块索引短一条链路。等美术定稿后把 _build 换成
##   TileMapLayer 即可，对外接口（h / b / start_col）不变。

var h := PackedInt32Array()
var b := PackedInt32Array()
var start_col := 0

var _tile := 64

const SURFACE_Y := 0.0
const GROUND_THICK = 900.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2

# 深海像素风礁岩 + 沉船遗迹模块化地形套件（与 `tools/terrain_prep.py` 对齐）
const TEX_FILL := preload("res://sprites/terrain/fill_seamless.png")
const TOP_TEX := [
	preload("res://sprites/terrain/top_01.png"),
	preload("res://sprites/terrain/top_02.png"),
	preload("res://sprites/terrain/top_03.png"),
	preload("res://sprites/terrain/top_04.png"),
]
const TEX_WALL_L := preload("res://sprites/terrain/wall_l.png")
const TEX_WALL_R := preload("res://sprites/terrain/wall_r.png")
const TEX_CO_L := preload("res://sprites/terrain/corner_out_l.png")
const TEX_CO_R := preload("res://sprites/terrain/corner_out_r.png")
const TEX_CI_L := preload("res://sprites/terrain/corner_in_l.png")
const TEX_CI_R := preload("res://sprites/terrain/corner_in_r.png")
const TEX_CHASM_L := preload("res://sprites/terrain/chasm_lip_l.png")
const TEX_CHASM_R := preload("res://sprites/terrain/chasm_lip_r.png")

const SURFACE_OFFSET_Y := 14.0
const FILL_INSET := 6.0
const WALL_R_CLIFF_X := 28.0
const WALL_L_CLIFF_X := 8.0
const CORNER_OUT_R_CLIFF_X := 32.0
const CORNER_OUT_L_CLIFF_X := 8.0
const CORNER_IN_R_ANCHOR := Vector2(8.0, 22.0)
const CORNER_IN_L_ANCHOR := Vector2(28.0, 22.0)
const CHASM_LIP_R_CLIFF_X := 46.0
const CHASM_LIP_L_CLIFF_X := 30.0
const VISUAL_GROUND_BOTTOM := 520.0
const CHASM_GRAD_H := 195.0
const EARTH_SHADE_START := 70.0
const EARTH_SHADE_H := 250.0

static var _chasm_grad: GradientTexture2D
static var _earth_grad: GradientTexture2D


static func _ensure_grads() -> void:
	if _chasm_grad != null:
		return
	var cg := Gradient.new()
	cg.offsets = PackedFloat32Array([0.0, 0.25, 0.50, 0.75, 1.0])
	cg.colors = PackedColorArray([
		Color(0.008, 0.020, 0.043, 0.0),
		Color(0.008, 0.020, 0.043, 0.15),
		Color(0.008, 0.020, 0.043, 0.47),
		Color(0.008, 0.020, 0.043, 0.80),
		Color(0.008, 0.020, 0.043, 0.94),
	])
	_chasm_grad = GradientTexture2D.new()
	_chasm_grad.gradient = cg
	_chasm_grad.fill_from = Vector2(0.0, 0.0)
	_chasm_grad.fill_to = Vector2(0.0, 1.0)
	_chasm_grad.width = 4
	_chasm_grad.height = 128

	var eg := Gradient.new()
	eg.offsets = PackedFloat32Array([0.0, 0.50, 1.0])
	eg.colors = PackedColorArray([
		Color(0.008, 0.020, 0.043, 0.0),
		Color(0.008, 0.020, 0.043, 0.10),
		Color(0.008, 0.020, 0.043, 0.38),
	])
	_earth_grad = GradientTexture2D.new()
	_earth_grad.gradient = eg
	_earth_grad.fill_from = Vector2(0.0, 0.0)
	_earth_grad.fill_to = Vector2(0.0, 1.0)
	_earth_grad.width = 4
	_earth_grad.height = 128

## 贴地矮障碍的贴图（沉船残骸四款：断船肋 / 锚 / 木桶 / 木箱）。
## 由 tools/obstacle_prep.py 从 AI 分镜图切出并抠成透明 PNG。
##
## ⚠ **四张的尺寸不再统一**（2026-09-27 晚，用户要求断船肋/锚"宽度高度都加一倍"）：
##     木桶 `106×64`、木箱 `139×64`  —— 仍是 1 格高；
##   **断船肋 `179×128`、锚 `131×128`** —— 重切成 2 格高（`obstacle_prep --height 128`）。
##   所以绘制高度必须取 `tex.get_height()`，**不能写死 LOW_HAZARD_H**。
##
## ⚠ **但这四款的碰撞盒一律 64×64（1 格），不跟贴图走**：
##   视觉大、碰撞小是安全方向 —— 玩家不会觉得"明明躲过去了却撞到"。
##   反过来（视觉小、碰撞大）才是要避免的。详见 docs/交接说明.md 11.0。
##
##   **为什么加高那两款的碰撞盒不能一起变成 128 高**（算过，不是保守）：
##   玩家碰撞盒 44px 宽，脚要抬到障碍顶以上才算躲开 ⇒ 需水平跨过 64 + 44 = 108px；
##   而一次跳跃在「128px 以上」的水平覆盖 = 速度 × 0.1905s（由 jump_velocity/gravity 定），
##   最低速 470 时只有 **89px < 108px ⇒ 开局必然撞**（要 567px/s 才够）。
##   想改就得同步抬高跳跃（v 760→793，apex 137.5→149.6，+9%），那是动全局手感。
##   现状的代价：起跳时机偏早/偏晚时，玩家会从贴图上半截"前面"穿过去
##   （玩家 z_index 更高、画在障碍之上，读作前后层次而非穿模）。
##   时机正常时脚在最高点 137px > 贴图顶 128px，**完全不重叠**。
const LOW_TEX := [
	preload("res://sprites/hazard/hazard_low_shiprib.png"),
	preload("res://sprites/hazard/hazard_low_anchor.png"),
	preload("res://sprites/hazard/hazard_low_barrels.png"),
	preload("res://sprites/hazard/hazard_low_crate.png"),
]

## 悬顶障碍的贴图（四款：断裂桅杆 / 船体横撑 / 悬挂锚链 / 吊货滑车）。
## 每张都是 240px 高、**底边就是悬顶下沿**；宽度 144~179px —— 和 LOW 一样，
## 横跨 2 列（128px）时会视觉超出。这是有意的（视觉大、碰撞小是安全方向）。
const OVER_TEX := [
	preload("res://sprites/hazard/hazard_over_mast.png"),
	preload("res://sprites/hazard/hazard_over_ribs.png"),
	preload("res://sprites/hazard/hazard_over_chain.png"),
	preload("res://sprites/hazard/hazard_over_hoist.png"),
]

## 悬顶障碍下方留出的净空（px）。
## 必须满足「滑铲高度 < 净空 < 站立高度」，否则要么滑过去也不用滑、要么滑不过。
## 站立 ≈ 104px，滑铲 ≈ 54px → 取 66px。
const OVERHEAD_CLEARANCE := 66.0
const OVERHEAD_THICK := 240.0
## 贴地矮障碍的**碰撞盒**高度。
## ⚠ 这不是贴图高度 —— 断船肋/锚那两张是 2 格高（128）。理由见 LOW_TEX 的注释。
const LOW_HAZARD_H := 64.0

## 调 `GameConfig.near_miss_margin` 时打开：把「擦身而过」的判定外圈画出来。
## 这个参数是纯手感值（多大才算擦过），没有公式可推，只能肉眼校准 —— 所以留了这个开关。
const DEBUG_DRAW_NEAR_MISS := false

## 调试用：强制所有悬顶只用第 N 款造型（−1 = 按世界列号正常轮换）。
##
## 存在的理由：造型按 `世界列号 mod 4` 轮换，**一段悬顶只呈现一款**，
## 所以「改完 4 张贴图后逐款核对实机效果」在正常情况下要靠运气撞见某一款
## （实际连跑三局都没撞到第 4 款）。用 `-- --over-variant=3` 可以钉死某一款。
## 默认 −1，不传参数时对渲染毫无影响。
static var debug_over_variant := -1

## 调试用：强制所有贴地矮障碍只用第 N 款造型（−1 = 按世界列号正常轮换）。
## 与 debug_over_variant 同理 —— 四款也按世界列号轮换，想逐款核对实机效果要靠运气。
## 换尺寸/换素材后逐款验收用 `-- --low-variant=0`（0 断船肋 / 1 锚 / 2 木桶 / 3 木箱）。
static var debug_low_variant := -1


## 本块是否属于**断桥段**。它同时决定画法与碰撞，两者必须一起变（见 `_build` / `_draw`）：
##
##   · **断桥段**（`broken = true`）：坑画成**无底深沟**，坑列**没有**碰撞体 ⇒ 掉下去 = 坠崖。
##   · **实体段**（`broken = false`）：坑照旧**逐列按层高画**，凹陷露出自己的台阶和坑底，
##     坑列**保留**碰撞体 ⇒ 掉进去能爬出来、不致命。
##
## ⚠ **为什么画法和碰撞必须绑在一起**：只改画法会立刻重演"看着有地板却掉下去"
##   （用户报过）—— 实体段的凹陷画出了坑底，玩家就会以为那里站得住。
##   绑在一起之后，「看得见的地面 = 站得住的表面」这条不破，而且**视觉自己教规则**：
##   有坑底的小凹陷可以踩，看不到底的大沟会死。
##
## ⚠ 语义上也正好：断桥段本来就该是"断掉的桥"，实体段的坑本来就是"点缀起伏"。
var broken := false


func setup(p_h: PackedInt32Array, p_b: PackedInt32Array, p_start_col: int,
		p_broken := false) -> void:
	h = p_h
	b = p_b
	start_col = p_start_col
	broken = p_broken
	_tile = GameConfig.TILE
	collision_layer = LAYER_WORLD
	collision_mask = 0
	position = Vector2(float(start_col * _tile), 0.0)
	_build()
	queue_redraw()


func world_right() -> float:
	return position.x + float(h.size() * _tile)


func surface_y_of(c: int) -> float:
	return SURFACE_Y + float(h[c]) * float(_tile)


## 按**全局列号**确定性地从 n 款造型里挑一个。
##
## ⚠ 绝对不能用 randi()：_draw 每帧都会重画，随机的话障碍会每帧换一个样子（疯狂闪烁）。
## 用全局列号（start_col + c）而不是块内局部列号，是为了让造型在块与块的接缝处
## 也保持一致 —— 同一个世界位置永远长同一个障碍。
func _variant_of(global_col: int, n: int) -> int:
	return posmod(global_col * 2654435761, n)


## 按世界坐标对齐平铺无缝岩体填充贴图，彻底消除 256px 与地形块接缝。
func _draw_world_fill(rx: float, ry: float, rw: float, rh: float) -> void:
	if rw <= 0.0 or rh <= 0.0:
		return
	var fw := float(TEX_FILL.get_width())
	var fh := float(TEX_FILL.get_height())
	var cur_y := 0.0
	while cur_y < rh:
		var ty := fposmod(position.y + ry + cur_y, fh)
		if ty >= fh - 0.01:
			ty = 0.0
		var step_h := minf(rh - cur_y, fh - ty)
		if step_h <= 0.01:
			break
		var cur_x := 0.0
		while cur_x < rw:
			var tx := fposmod(position.x + rx + cur_x, fw)
			if tx >= fw - 0.01:
				tx = 0.0
			var step_w := minf(rw - cur_x, fw - tx)
			if step_w <= 0.01:
				break
			draw_texture_rect_region(
				TEX_FILL,
				Rect2(rx + cur_x, ry + cur_y, step_w, step_h),
				Rect2(tx, ty, step_w, step_h)
			)
			cur_x += step_w
		cur_y += step_h


## 纵向平铺岩壁并在到达下层地面前精确裁切，防止台阶岩壁往下渗出下层地板。
func _draw_wall_clipped(tex: Texture2D, wx: float, y_start: float, y_end: float) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var step_y := th - 4.0
	var wy := y_start
	while wy < y_end:
		var rem := y_end - wy
		if rem <= 0.0:
			break
		if rem < th:
			draw_texture_rect_region(tex, Rect2(wx, wy, tw, rem), Rect2(0.0, 0.0, tw, rem))
			break
		draw_texture(tex, Vector2(wx, wy))
		wy += step_y


## 模块化像素礁岩与沉船遗迹地面渲染（4 Pass：地底无缝填岩 → 顶面岩檐 → 崖壁/内外转角 → 底部深渊柔暗）。
func _draw_plates(tile: float, skip_pits: bool) -> void:
	# 收集所有连续同层高段（供 Pass 1 / 3 / 4 复用）
	var runs: Array[Dictionary] = []
	var c := 0
	while c < h.size():
		if skip_pits and h[c] > 0:
			c += 1
			continue
		var c0 := c
		while c + 1 < h.size() and h[c + 1] == h[c]:
			c += 1
		var c1 := c
		c += 1
		var rx := float(c0) * tile
		var rw := float(c1 - c0 + 1) * tile
		if start_col == 0 and c0 == 0:
			var pad := tile * 4.0
			rx -= pad
			rw += pad
		var top := surface_y_of(c0)
		var fill_x := rx
		var fill_w := rw
		if c0 > 0 and h[c0 - 1] > h[c0]:
			fill_x += FILL_INSET
			fill_w -= FILL_INSET
		if c1 + 1 < h.size() and h[c1 + 1] > h[c1]:
			fill_w -= FILL_INSET
		runs.append({
			"c0": c0,
			"c1": c1,
			"rx": rx,
			"rw": rw,
			"fill_x": fill_x,
			"fill_w": fill_w,
			"top": top,
		})

	# Pass 1：地底无缝礁岩体填充
	# 临空上段向内收 FILL_INSET=6px 藏进崖壁外缘之下；非断桥段在相邻下层地面以下贴合实岩层，不留 6px 竖缝。
	for r in runs:
		var c0 := int(r["c0"])
		var c1 := int(r["c1"])
		var top_lv := float(r["top"])
		var rx := float(r["rx"])
		var rw := float(r["rw"])
		var ry := top_lv + FILL_INSET
		var left_exp := c0 > 0 and h[c0 - 1] > h[c0]
		var right_exp := c1 + 1 < h.size() and h[c1 + 1] > h[c1]
		var left_chasm := broken and c0 > 0 and h[c0 - 1] > 0
		var right_chasm := broken and c1 + 1 < h.size() and h[c1 + 1] > 0
		if (left_chasm or right_chasm) or (not left_exp and not right_exp):
			_draw_world_fill(float(r["fill_x"]), ry, float(r["fill_w"]), VISUAL_GROUND_BOTTOM - ry)
			continue
		var y_l := VISUAL_GROUND_BOTTOM if left_chasm else (surface_y_of(c0 - 1) + FILL_INSET if left_exp else ry)
		var y_r := VISUAL_GROUND_BOTTOM if right_chasm else (surface_y_of(c1 + 1) + FILL_INSET if right_exp else ry)
		y_l = clampf(y_l, ry, VISUAL_GROUND_BOTTOM)
		y_r = clampf(y_r, ry, VISUAL_GROUND_BOTTOM)
		var cuts: Array[float] = [ry, VISUAL_GROUND_BOTTOM]
		if y_l > ry and y_l < VISUAL_GROUND_BOTTOM:
			cuts.append(y_l)
		if y_r > ry and y_r < VISUAL_GROUND_BOTTOM and not is_equal_approx(y_r, y_l):
			cuts.append(y_r)
		cuts.sort()
		for ci in cuts.size() - 1:
			var sy0 := cuts[ci]
			var sy1 := cuts[ci + 1]
			if sy1 <= sy0 + 0.01:
				continue
			var sx := rx
			var sw := rw
			if left_exp and sy1 <= y_l + 0.5:
				sx += FILL_INSET
				sw -= FILL_INSET
			if right_exp and sy1 <= y_r + 0.5:
				sw -= FILL_INSET
			_draw_world_fill(sx, sy0, sw, sy1 - sy0)

	# Pass 2：行进顶面岩檐（4 款按全局列号确定性混拼，左侧起点带 4 列延伸垫底）
	if start_col == 0 and h.size() > 0 and (not skip_pits or h[0] == 0):
		var ty0 := surface_y_of(0) - SURFACE_OFFSET_Y
		for pc in range(-4, 0):
			var tex_pad: Texture2D = TOP_TEX[_variant_of(start_col + pc, TOP_TEX.size())]
			draw_texture(tex_pad, Vector2(float(pc) * tile, ty0))
	for idx in h.size():
		if skip_pits and h[idx] > 0:
			continue
		var tex_top: Texture2D = TOP_TEX[_variant_of(start_col + idx, TOP_TEX.size())]
		draw_texture(tex_top, Vector2(float(idx) * tile, surface_y_of(idx) - SURFACE_OFFSET_Y))

	# Pass 3：垂直崖壁 + 外凸崖角 / 断桥悬崖口 + 凹坑内拐角（彻底消灭黑方盒与双层 7px 立面）
	for r in runs:
		var c0 := int(r["c0"])
		var c1 := int(r["c1"])
		var top_lv := float(r["top"])
		if c1 + 1 < h.size() and h[c1 + 1] > h[c1]:
			var edge_x := float(c1 + 1) * tile
			var is_chasm_r := broken and h[c1 + 1] > 0
			var bot_lv := VISUAL_GROUND_BOTTOM if is_chasm_r else surface_y_of(c1 + 1)
			if is_chasm_r:
				_draw_wall_clipped(TEX_WALL_R, edge_x - WALL_R_CLIFF_X, top_lv + 72.0, VISUAL_GROUND_BOTTOM)
				draw_texture(TEX_CHASM_R, Vector2(edge_x - CHASM_LIP_R_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
			else:
				_draw_wall_clipped(TEX_WALL_R, edge_x - WALL_R_CLIFF_X, top_lv + 14.0, bot_lv + 4.0)
				draw_texture(TEX_CO_R, Vector2(edge_x - CORNER_OUT_R_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
				draw_texture(TEX_CI_R, Vector2(edge_x - CORNER_IN_R_ANCHOR.x, bot_lv - CORNER_IN_R_ANCHOR.y))
		if c0 > 0 and h[c0 - 1] > h[c0]:
			var edge_x2 := float(c0) * tile
			var is_chasm_l := broken and h[c0 - 1] > 0
			var bot_lv2 := VISUAL_GROUND_BOTTOM if is_chasm_l else surface_y_of(c0 - 1)
			if is_chasm_l:
				_draw_wall_clipped(TEX_WALL_L, edge_x2 - WALL_L_CLIFF_X, top_lv + 72.0, VISUAL_GROUND_BOTTOM)
				draw_texture(TEX_CHASM_L, Vector2(edge_x2 - CHASM_LIP_L_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
			else:
				_draw_wall_clipped(TEX_WALL_L, edge_x2 - WALL_L_CLIFF_X, top_lv + 14.0, bot_lv2 + 4.0)
				draw_texture(TEX_CO_L, Vector2(edge_x2 - CORNER_OUT_L_CLIFF_X, top_lv - SURFACE_OFFSET_Y))
				draw_texture(TEX_CI_L, Vector2(edge_x2 - CORNER_IN_L_ANCHOR.x, bot_lv2 - CORNER_IN_L_ANCHOR.y))

	# Pass 4：底部深海柔和压暗渐变，将大地深处沉进屏底
	if _earth_grad != null:
		for r in runs:
			var rx := float(r["rx"])
			var rw := float(r["rw"])
			var sy0 := float(r["top"]) + EARTH_SHADE_START
			if sy0 >= VISUAL_GROUND_BOTTOM:
				continue
			var sh := minf(EARTH_SHADE_H, VISUAL_GROUND_BOTTOM - sy0)
			draw_texture_rect(_earth_grad, Rect2(rx, sy0, rw, sh), false)
			var sy1 := sy0 + sh
			if VISUAL_GROUND_BOTTOM > sy1:
				draw_rect(Rect2(rx, sy1, rw, VISUAL_GROUND_BOTTOM - sy1),
					Color(0.008, 0.020, 0.043, 0.38))


func _draw_chasms(tile: float) -> void:
	var c := 0
	var n := h.size()
	while c < n:
		if h[c] <= 0:
			c += 1
			continue
		var c0 := c
		while c + 1 < n and h[c + 1] > 0:
			c += 1
		var c1 := c
		c += 1

		var lv := 0
		var has_l := c0 > 0 and h[c0 - 1] <= 0
		var has_r := c1 + 1 < n and h[c1 + 1] <= 0
		if has_l and has_r:
			lv = mini(h[c0 - 1], h[c1 + 1])
		elif has_l:
			lv = h[c0 - 1]
		elif has_r:
			lv = h[c1 + 1]
		var top := SURFACE_Y + float(lv) * tile
		var x0 := float(c0) * tile
		var w := float(c1 - c0 + 1) * tile

		# 口沿从 alpha = 0.0 平滑入雾下沉至 0.94，彻底消灭沟口横黑线与离散色带
		if _chasm_grad != null:
			draw_texture_rect(_chasm_grad, Rect2(x0, top, w, CHASM_GRAD_H), false)
		var bot_y := top + CHASM_GRAD_H
		if VISUAL_GROUND_BOTTOM > bot_y:
			draw_rect(Rect2(x0, bot_y, w, VISUAL_GROUND_BOTTOM - bot_y),
				Color(0.008, 0.020, 0.043, 0.94))


func _draw_overheads(tile: float) -> void:
	var i := 0
	while i < b.size():
		if b[i] != TerrainPatterns.OVERHEAD:
			i += 1
			continue
		var c0 := i
		while i + 1 < b.size() and b[i + 1] == TerrainPatterns.OVERHEAD:
			i += 1
		_draw_one_overhead(c0, i, tile)
		i += 1


## 画一段悬顶。段内各列地面高度必然相同（地形生成器保证「障碍落在连续平地上」）。
func _draw_one_overhead(c0: int, c1: int, tile: float) -> void:
	var vi := _variant_of(start_col + c0, OVER_TEX.size())
	if debug_over_variant >= 0:
		vi = debug_over_variant % OVER_TEX.size()
	var tex: Texture2D = OVER_TEX[vi]
	var tw := float(tex.get_width())
	var seg_x := float(c0) * tile
	var seg_w := float(c1 - c0 + 1) * tile
	var bot := surface_y_of(c0) - OVERHEAD_CLEARANCE
	# 贴图**自带向上延伸段**（在预处理阶段合成，见 tools/obstacle_prep.py 的
	# build_upfill），总高 = 240（碰撞区）+ 400（延伸）。
	# ⚠ 不要在运行时补高：试过「取贴图最上面 2 行纵向拉伸」，但贴图顶边就是
	#   造型最高点、也就是绳子的顶端末端（渐细 + 大量半透明像素），
	#   拉出来细如蛛丝、和下方粗绳完全接不上 —— 就是「空中连接点很奇怪」的成因。
	var th := float(tex.get_height())
	# 保持原比例、水平居中于整段。横向会超出 2 列 = 128px 的段宽，
	# 和矮障碍一样是「视觉大、碰撞小」的安全方向。
	var px := seg_x + (seg_w - tw) * 0.5
	draw_texture_rect(tex, Rect2(px, bot - th, tw, th), false)


# ---------------------------------------------------------------- 碰撞
func _build() -> void:
	# 1) 层高相同的连续列合并成一个矩形，减少碰撞体数量。
	#
	# ⚠ **坑列给不给碰撞体，跟着 `broken` 走**（2026-09-28 晚第二版）。
	#
	#   历史：一开始坑列一律有碰撞体（1~2 格深的实心地板）；后来断崖渲染把坑画成
	#   无底深沟，两者矛盾 ⇒ 玩家掉进沟里只下沉 64px 就"站"在虚空里继续跑
	#   （用户实机截图：脚底比地面线低 62px，左右两边全是虚空色）。
	#   于是先改成"坑列一律不给碰撞体"，但那样**实体段的凹陷也没了底** ——
	#   于是一个 128px 宽的小裂缝都能摔死人，而且画面上它看着像能踩。
	#
	#   现在按段落分流，画法与碰撞成对：
	#     · 断桥段：画无底深沟 + 坑列没有碰撞体 ⇒ 掉下去 = 坠崖（`Main.FALL_KILL_DEPTH`）
	#     · 实体段：凹陷画出台阶和坑底 + 坑列保留碰撞体 ⇒ 踩下去能爬出来，不致命
	#   这样「看得见的地面 = 站得住的表面」这条不破，而且视觉自己教规则。
	#
	# ⚠ 连带后果：R2 那句"需掉入再爬出"的次优解**只在实体段还存在**。
	#   断桥段的坑必须跳得过去（`max_safe_gap` + `BROKEN_GAP_CAP` 一起保证），
	#   所以"沟宽留余量"这件事对断桥段比之前更要紧。
	var i := 0
	while i < h.size():
		var j := i
		while j + 1 < h.size() and h[j + 1] == h[i]:
			j += 1
		if h[i] <= 0 or not broken:
			_add_ground_rect(i, j, h[i])
		i = j + 1

	# 2) 障碍：**伤害**逐列（Area2D，非实心）；**擦身**逐组（一整个障碍一个判定门）
	#    ⚠ 逐列造成伤害是必须的（悬顶横跨 2~3 列，少一列就会从缝里穿过去）；
	#      但擦身不能逐列 —— 一组长障碍会连着给好几次分。
	var i2 := 0
	while i2 < b.size():
		var kind := b[i2]
		if kind != TerrainPatterns.LOW and kind != TerrainPatterns.OVERHEAD:
			i2 += 1
			continue
		var c0 := i2
		while i2 + 1 < b.size() and b[i2 + 1] == kind:
			i2 += 1
		var c1 := i2
		i2 += 1
		for c in range(c0, c1 + 1):
			match kind:
				TerrainPatterns.LOW:
					_add_hazard_area(c, surface_y_of(c) - LOW_HAZARD_H, LOW_HAZARD_H, "low")
				TerrainPatterns.OVERHEAD:
					var bot := surface_y_of(c) - OVERHEAD_CLEARANCE
					_add_hazard_area(c, bot - OVERHEAD_THICK, OVERHEAD_THICK, "over")
		_add_near_gate(c0, c1, kind)


func _add_ground_rect(c0: int, c1: int, level: int) -> void:
	var w := float(c1 - c0 + 1) * float(_tile)
	var top := SURFACE_Y + float(level) * float(_tile)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(w, GROUND_THICK)
	cs.shape = sh
	cs.position = Vector2(float(c0) * float(_tile) + w * 0.5, top + GROUND_THICK * 0.5)
	add_child(cs)


func _add_hazard_area(col: int, top_y: float, height: float, kind: String) -> void:
	var cx := (float(col) + 0.5) * float(_tile)
	var cy := top_y + height * 0.5

	# ① 本体：撞上去只减速（见文件头注释），不致命
	var area := Area2D.new()
	area.name = "Hazard_%s_%d" % [kind, col]
	area.collision_layer = 4          # 3 层：障碍
	area.collision_mask = LAYER_PLAYER
	area.monitoring = true
	area.monitorable = false
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(float(_tile), height)
	cs.shape = sh
	cs.position = Vector2(cx, cy)
	area.add_child(cs)
	area.body_entered.connect(_on_hazard_body_entered.bind(kind))
	add_child(area)

func _add_near_gate(c0: int, c1: int, kind: int) -> void:
	# 擦身判定门：见 `NearMissGate` 的文件头（旧做法为什么在两种障碍上给出相反的错误）。
	#
	# ⚠ 净空量在**碰撞盒顶(64)**上，不用贴图的视觉顶 ——
	#   四款贴图是 94/96/128/128，按视觉量会让 97% 的跳跃都给分（实测，见 NearMissGate 文件头）。
	var tile := float(_tile)
	var left_w := global_position.x + float(c0) * tile
	var right_w := global_position.x + float(c1 + 1) * tile
	var surf_w := global_position.y + surface_y_of(c0)
	var judge_top_w := surf_w - LOW_HAZARD_H
	var gate := NearMissGate.new()
	gate.setup(kind, judge_top_w, left_w, right_w, surf_w)
	add_child(gate)


func _on_hazard_body_entered(body: Node2D, kind: String) -> void:
	if body is Player:
		(body as Player).take_hit(kind)


# ---------------------------------------------------------------- 地面与断崖
func _draw() -> void:
	_ensure_grads()
	var tile := float(_tile)
	# 1) 地面。**画法按 `broken` 分流** —— 这是"断崖观感"和"凹面起伏"共存的关键：
	if broken:
		# 先铺深渊渐变再铺崖壁与悬崖口，让断桥崖角和垂挂海藻落在渐变前面
		_draw_chasms(tile)
		_draw_plates(tile, true)
	else:
		_draw_plates(tile, false)

	for c in h.size():
		if b[c] == TerrainPatterns.LOW:
			var vi := _variant_of(start_col + c, LOW_TEX.size())
			if debug_low_variant >= 0:
				vi = debug_low_variant % LOW_TEX.size()
			var tex: Texture2D = LOW_TEX[vi]
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			var x := float(c) * tile
			draw_texture_rect(tex, Rect2(x + (tile - tw) * 0.5, surface_y_of(c) - th, tw, th), false)

	# 悬顶：按连续段画整图（见 _draw_overheads 的说明）
	_draw_overheads(tile)

	# 近失判定外圈（只在调参时打开，见 DEBUG_DRAW_NEAR_MISS）
	if DEBUG_DRAW_NEAR_MISS:
		var m := GameConfig.near_miss_margin
		var col_nm := Color(0.35, 1.0, 0.90, 0.35)
		for c in h.size():
			var x := float(c) * tile
			match b[c]:
				TerrainPatterns.LOW:
					var top := surface_y_of(c) - LOW_HAZARD_H
					draw_rect(Rect2(x - m, top - m, tile + m * 2.0, LOW_HAZARD_H + m * 2.0),
						col_nm, false, 1.5)
				TerrainPatterns.OVERHEAD:
					var bot := surface_y_of(c) - OVERHEAD_CLEARANCE
					draw_rect(Rect2(x - m, bot - OVERHEAD_THICK - m,
						tile + m * 2.0, OVERHEAD_THICK + m * 2.0), col_nm, false, 1.5)
