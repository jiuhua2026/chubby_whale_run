extends Node2D
class_name DashFx
## 冲刺特效：**残影拖尾 + 气泡尾迹 + 起手爆发**，全部由代码生成（零素材）。
##
## 为什么挂在**世界层**、而不是 Player 的子节点
## ----------------------------------------------------------------------
## 玩家是真的在世界里前进的（相机跟随），不是地形在滚。特效若挂在玩家下面，
## 就只会"贴在身上"跟着走 —— 那不叫拖尾。粒子用世界坐标发射、残影留在原地，
## 才会被高速前进的角色甩出一条尾巴。所以本节点与 Player **同级**。
##
## 风格约束
## ----------------------------------------------------------------------
## 所有元素都是**整数像素方块**，绘制时对坐标取整：
##   项目是像素风（texture_filter = nearest），角色线条 2~3px。
##   如果粒子带小数坐标、带抗锯齿，会立刻显出一层"贴纸感"，跟角色不搭。
##   方块还有个好处：气泡/水花本来就是一格一格的，比圆形更贴深海主题。
##
## 三层特效各自负责什么
## ----------------------------------------------------------------------
##   残影   —— 冲刺最经典的表现，负责"速度感"。让玩家在余光里看出"我在窜"
##   尾迹   —— 持续性的存在感，负责"一直在冲"（残影间隔 45ms，中间是空的）
##   起手爆发 —— 一次性，负责"起步那一下"的爆发感，给冲刺一个明确的开始
##
## 层级（绝对 z）：Backdrop -50 < Terrain 0 < **残影 0** < **粒子 1** < Player 2
##   < DeathWall 40 < Chaser 45 < HUD(CanvasLayer)
##   残影压在粒子之下，水花才会"飞在角色影子前面"，有前后层次。

# ---------------------------------------------------------------- 可调参数
## 残影生成间隔（秒）。太密会糊成一坨看不出单帧，太疏读不出连续拖尾。
## 55ms 时同时存活 4 个（0.20 / 0.055），叠起来刚好一条连续拖尾而不"堆"。
const GHOST_INTERVAL := 0.055
## 单个残影的存活时间
const GHOST_LIFE := 0.20
## 残影着色：整体提亮并偏青。
## 与冲刺时角色自身的提亮 `Color(1.25, 1.45, 1.65)` 是同一套色偏，
## 只是残影还要半透明，所以各通道再乘一个衰减。
## ⚠ alpha 是这组参数里最敏感的一个：实测 0.50 时叠 5 层会糊成实心块，
##   读起来像"角色分身"而不是"速度拖影"。0.36 才透气。
const GHOST_TINT := Color(0.46, 1.55, 2.10, 0.36)
## 残影向后（屏幕左）漂移的距离。有位移才像"被甩下来"而不是"幽灵站着"
const GHOST_DRIFT := 22.0
## 残影收尾时缩到原尺寸的多少。配合漂移强化"远去"
const GHOST_SHRINK := 0.88

## 尾迹发射速率（个/秒）
const TRAIL_RATE := 120.0
## 尾迹粒子基础寿命
const TRAIL_LIFE := 0.46
## 尾迹粒子的横向初速（向左 = 负）。世界坐标下角色自己在跑，
## 所以这个值不用很大 —— 主要是给粒子一点形状，别原地不动。
const TRAIL_VX := Vector2(-145.0, -55.0)
## 尾迹粒子的纵向初速范围
const TRAIL_VY := Vector2(-32.0, 32.0)

## 起手爆发粒子数
const BURST_COUNT := 16
## 起手爆发的扇形半角（弧度）。±0.85 ≈ ±49°
const BURST_SPREAD := 0.85
## 起手爆发速度范围（向左）
const BURST_SPEED := Vector2(190.0, 430.0)
const BURST_LIFE := 0.26

## 气泡上浮加速度（px/s²，向上为负）。深海主题：喷出去的水花该往上飘
const BUBBLE_RISE := 95.0
## 每秒速度衰减比例。让粒子很快就慢下来，尾迹不至于拖太长
const DRAG_PER_SEC := 3.4

## 粒子颜色：主体青白，偶尔纯白点一下高光
const COL_TRAIL := Color(0.68, 0.94, 1.00)
const COL_TRAIL_HI := Color(0.95, 1.00, 1.00)
const COL_BURST := Color(0.85, 0.98, 1.00)

## 绘制用的像素尺寸池。全是整数，避免半像素糊边。
## 2px 在 720p 下太小，几乎看不见 —— 实际起步就是 3px。
const SIZES_TRAIL := [3, 3, 4, 4, 5]
const SIZES_BURST := [3, 3, 4, 5]

# ---------------------------------------------------------------- 状态
## 一个像素质点。用内部类而不是 Dictionary —— 冲刺期间每帧都在读写这些字段，
## 字典的字符串查表在这里是纯粹的浪费。
class P:
	var pos := Vector2.ZERO      ## 世界坐标（局部坐标 == 世界坐标，本节点在原点）
	var vel := Vector2.ZERO
	var life := 0.0
	var life_max := 1.0
	var size := 2.0
	var col := Color.WHITE

var _player: Player = null
var _sprite: Sprite2D = null
var _dashing := false
var _emit_acc := 0.0
var _ghost_t := 0.0
var _parts: Array[P] = []


func _ready() -> void:
	# 粒子画在 z=1（地形 0 之上、玩家 2 之下）；残影用相对 z=-1 落到 0。
	z_index = 1
	# 平时不跑 _process，冲刺开始才打开。省得整局空转（--solvable 要跑 20000 帧）
	set_process(false)


func setup(p_player: Player) -> void:
	_player = p_player
	# 残影要复制角色当前的纹理 / 偏移 / 缩放，所以得拿到它的 Sprite2D
	_sprite = _player.get_node_or_null("Sprite2D") as Sprite2D


# ---------------------------------------------------------------- 对外接口
## 冲刺开始：起手水花爆散 + 原地爆发粒子 + 打开尾迹与残影
func start_dash() -> void:
	_dashing = true
	_ghost_t = 0.0
	_emit_acc = 0.0
	_burst()
	_spawn_dash_poof()
	set_process(true)


## 冲刺结束：停掉发射。
## 刻意**不清空已有的粒子** —— 让它们在冲刺结束后自然飘完，
## 否则一松手尾巴就"啪"地断掉，很假。
func stop_dash() -> void:
	_dashing = false


## 落地冲击水雾 / 碎石（在玩家脚底世界坐标触发）
func spawn_landing(world_pos: Vector2, intensity := 1.0) -> void:
	var fx := PixelFxPlayer.new()
	fx.z_index = 0
	fx.scale = Vector2(1.45, 1.45)
	fx.modulate = Color(0.86, 0.96, 1.0, clampf(0.80 * intensity, 0.50, 0.85))
	fx.position = world_pos
	add_child(fx)
	if not fx.play("action/heavy_landing", true, 1.55, 0.0, true):
		fx.queue_free()


## 撞击障碍受击锐利星爆（压在角色与障碍前）
func spawn_hit(world_pos: Vector2) -> void:
	var fx := PixelFxPlayer.new()
	fx.z_index = 2
	fx.scale = Vector2(1.5, 1.5)
	fx.modulate = Color(1.0, 0.98, 0.95, 0.96)
	fx.position = world_pos
	add_child(fx)
	if not fx.play("action/crit_hit", true, 1.25, 0.0, true):
		fx.queue_free()
		return
	fx.set_flipped_h(true)


## 水泡护盾抵挡 1 次碰障减速时碎裂特效
func spawn_shield_break(world_pos: Vector2) -> void:
	var fx := PixelFxPlayer.new()
	fx.z_index = 3
	fx.scale = Vector2(1.5, 1.5)
	fx.modulate = Color(0.92, 0.98, 1.0, 0.95)
	fx.position = world_pos
	add_child(fx)
	if not fx.play("action/bubble_shield_break", true, 1.35, 0.0, true):
		fx.queue_free()


## 冲刺对黑鲸娘造成水压冲击波命中特效
func spawn_dash_shockwave(world_pos: Vector2) -> void:
	var fx := PixelFxPlayer.new()
	fx.z_index = 46
	fx.scale = Vector2(1.65, 1.65)
	fx.modulate = Color(0.88, 0.98, 1.0, 0.98)
	fx.position = world_pos
	add_child(fx)
	if not fx.play("action/dash_shockwave", true, 1.4, 0.0, true):
		fx.queue_free()


## 撞障碍物滑落采集物时：从鲸尾兜向后下方抛落 1 株植物剪影
func spawn_plant_drop(world_pos: Vector2, tex: Texture2D) -> void:
	if tex == null:
		return
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.position = world_pos
	sp.scale = Vector2(0.86, 0.86)
	sp.z_index = 4
	sp.modulate = Color(1.0, 0.88, 0.78, 0.96)
	add_child(sp)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "position:x", world_pos.x - 140.0, 0.56).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "position:y", world_pos.y - 36.0, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(sp, "position:y", world_pos.y + 64.0, 0.38).set_delay(0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(sp, "rotation", -1.4, 0.56)
	tw.tween_property(sp, "modulate:a", 0.0, 0.30).set_delay(0.26)
	tw.chain().tween_callback(sp.queue_free)


## 重开一局时清干净（残影是 Tween 驱动的，必须显式回收）
func clear_all() -> void:
	_dashing = false
	_parts.clear()
	_emit_acc = 0.0
	_ghost_t = 0.0
	for c in get_children():
		c.queue_free()
	queue_redraw()
	set_process(false)


# ---------------------------------------------------------------- 自检探针
## 当前存活粒子数。给无头自检用 —— 冲刺结束后它必须落回 0，
## 否则就是粒子池没回收（长度 20000 帧的可解性验证会一路堆到爆）。
func particle_count() -> int:
	return _parts.size()


## 当前存活残影节点数。残影靠 Tween 的 finished 回调 queue_free，
## 落回 0 才说明回收链路是通的。
func ghost_count() -> int:
	var n := 0
	for c in get_children():
		if c is Sprite2D and not (c is PixelFxPlayer):
			n += 1
	return n


# ---------------------------------------------------------------- 每帧
func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		set_process(false)
		return

	if _dashing:
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t += GHOST_INTERVAL
			_spawn_ghost()

		_emit_acc += TRAIL_RATE * delta
		while _emit_acc >= 1.0:
			_emit_acc -= 1.0
			_emit_trail()

	_update_parts(delta)

	# 没粒子了就把 _process 关掉 —— 下一帧不再白跑
	if not _dashing and _parts.is_empty():
		set_process(false)


## 起手原地水花爆散：留在世界坐标原地散开，人向前窜出去
func _spawn_dash_poof() -> void:
	if _player == null:
		return
	var fx := PixelFxPlayer.new()
	fx.z_index = 0
	fx.scale = Vector2(1.6, 1.6)
	fx.modulate = Color(0.90, 0.98, 1.0, 0.88)
	fx.position = _player.global_position + Vector2(-10.0, -34.0)
	add_child(fx)
	if not fx.play("action/dash_poof", true, 2.2, 0.0, true):
		fx.queue_free()


func _update_parts(delta: float) -> void:
	var alive: Array[P] = []
	var damp := maxf(0.0, 1.0 - DRAG_PER_SEC * delta)
	for p in _parts:
		p.life -= delta
		if p.life > 0.0:
			p.vel.y -= BUBBLE_RISE * delta   # 上浮
			p.vel *= damp
			p.pos += p.vel * delta
			alive.append(p)
	_parts = alive
	queue_redraw()


# ---------------------------------------------------------------- 发射
## 发射原点：角色**身后偏中**。
## 脚底在 player.global_position，角色显示高约 130px，所以身体中段约 -58。
func _emit_origin() -> Vector2:
	return _player.global_position + Vector2(-14.0, -58.0)


func _emit_trail() -> void:
	var p := P.new()
	p.pos = _emit_origin() + Vector2(randf_range(-6.0, 6.0), randf_range(-18.0, 18.0))
	p.vel = Vector2(randf_range(TRAIL_VX.x, TRAIL_VX.y), randf_range(TRAIL_VY.x, TRAIL_VY.y))
	p.life = TRAIL_LIFE * randf_range(0.7, 1.15)
	p.life_max = p.life
	p.size = float(SIZES_TRAIL.pick_random())
	# 约 1/5 的概率点一颗高光白，让尾巴有层次而不是一片同色的青
	p.col = COL_TRAIL_HI if randf() < 0.2 else COL_TRAIL
	_parts.append(p)


## 起手爆发：向左的扇形喷射。
## 速度比尾迹大得多、寿命更短 —— 读起来是"蹬出去"的那一下，而不是尾巴。
func _burst() -> void:
	var o := _emit_origin()
	for _i in BURST_COUNT:
		var p := P.new()
		var ang := randf_range(-BURST_SPREAD, BURST_SPREAD)
		# ang = 0 时方向为 (-1, 0)：正后方
		var dir := Vector2(-cos(ang), sin(ang))
		p.pos = o + Vector2(randf_range(-8.0, 8.0), randf_range(-14.0, 14.0))
		p.vel = dir * randf_range(BURST_SPEED.x, BURST_SPEED.y)
		p.life = BURST_LIFE * randf_range(0.75, 1.2)
		p.life_max = p.life
		p.size = float(SIZES_BURST.pick_random())
		p.col = COL_BURST
		_parts.append(p)
	queue_redraw()


## 残影：把角色**当前这一帧**原样复制一份，染色后留在原地淡出。
## 关键在于复制 offset / scale —— 锚点信息全在里面，
## 少了它们残影会和角色错位（角色的锚点对齐是靠这两个值实现的）。
func _spawn_ghost() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var g := Sprite2D.new()
	g.texture = _sprite.texture
	g.centered = _sprite.centered
	g.offset = _sprite.offset
	g.scale = _sprite.scale
	g.flip_h = _sprite.flip_h
	g.modulate = GHOST_TINT
	# 相对本节点（z=1）为 -1 → 绝对 0，压在粒子之下
	g.z_index = -1
	# 角色的锚点恰好落在 player 原点上，所以残影直接对齐原点即可，不用再算偏移
	g.position = _player.global_position
	add_child(g)

	var base_scale := _sprite.scale
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(g, "modulate:a", 0.0, GHOST_LIFE)
	tw.tween_property(g, "position:x", g.position.x - GHOST_DRIFT, GHOST_LIFE)
	tw.tween_property(g, "scale", base_scale * GHOST_SHRINK, GHOST_LIFE)
	tw.chain().tween_callback(g.queue_free)


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	for p in _parts:
		var t := clampf(p.life / maxf(p.life_max, 0.0001), 0.0, 1.0)
		var c := p.col
		# 平方衰减：尾段掉得更快，读起来像气泡"啪"地散掉，而不是慢慢褪色
		c.a = t * t
		var s := p.size
		# 坐标取整 + 整数尺寸 = 干净的像素方块，不会被插值糊掉边缘
		var tl := Vector2(roundf(p.pos.x - s * 0.5), roundf(p.pos.y - s * 0.5))
		draw_rect(Rect2(tl, Vector2(s, s)), c)
