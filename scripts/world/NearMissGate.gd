extends Area2D
class_name NearMissGate
## 障碍的「擦身而过」判定门。**一边经过一边量净空**，不是"进圈就送一格"。
##
## ## 为什么要重写（2026-10-17，用户报「下滑必给、跳跃不给」）
## 旧实现是给每个障碍套一个 `(tile+2m) × (height+2m)` 的膨胀矩形（m = 26），
## 进圈记一笔、出圈没撞就 +1。它只能测**"你有没有经过这块区域"**，
## 测不了**"你离得多近"**，而且在两种障碍上给出**相反的错误**（都是实测/算出来的）：
##
##   · **悬顶（滑过）**：净空 66、滑铲身高 54.1 ⇒ 真实间隙只有 **11.9px**，
##     而圈往下膨胀 **26px** ⇒ 滑过去时身体**必然**在圈内 **14.1px**
##     ⇒ 进入事件 100% 触发，退化成"只要滑过去了就送一格"。
##   · **矮障碍（跳过）**：圈顶 = 64 + 26 = **90px**，而跳跃顶点 **137.5px**、
##     脚到 90 只要 **0.13s**（约 85px 位移）；可圈宽只有 116px、**左边缘在障碍前 80px**
##     ⇒ 起跳稍早就已经在圈顶之上，连"进入"都不发生 ⇒ 几乎永远不给。
##   · 还有一层：圈是建在 **64px 碰撞盒**上的，而四款贴图实际 **94 / 96 / 128 / 128** 高
##     ⇒ 视觉上"贴着顶部过去"根本不算。
##
## 同一个 26px 同时用在两个轴上 ⇒ 竖直躲（跳）进不去、水平躲（滑）必然在里面。
##
## ## 现在按"两种障碍量不同维度"来处理（这不是偷懒，是它们本身没有同一个风险轴）
##   · **矮障碍**：量**垂直净空** = 障碍**碰撞盒顶(64)** − 玩家脚底。越贴越小。
##     ⚠ **不能用贴图的视觉顶**：四款贴图是 94/96/128/128，而碰撞盒固定 64
##     （"视觉大、碰撞小"是刻意的安全方向）。实测按视觉顶判 ⇒ 净空分布全在 -21~+22，
##     **97% 的跳跃都给分**，机制直接失效。按碰撞盒顶判，净空分布是 9~86，阈值 26
##     正好覆盖"脚在 64~90"这个贴边带 —— 对 94/96 那两款，这恰好就是"视觉上贴着顶部"。”
##   · **悬顶**：净空**恒为 11.9px**（只有"滑过去/撞上"两种），距离维度上不存在"更贴"，
##     所以改量**反应**：**起滑点离障碍越近越算擦身**（晚起滑 = 反应快 = 有风险）。
##
## ## 门的形状
## 水平方向只比障碍的列范围各多半个玩家宽 ⇒ 触发条件正好是
## **"玩家碰撞盒与障碍那一列横向重叠"**；竖直方向故意给足（±500px），
## 不让高度参与"进不进得来" —— 这条是修掉旧 bug 的关键。

const LAYER_PLAYER := 2
const PLAYER_HALF := 22.0        ## 玩家碰撞盒半宽 = Player.STAND_W / 2
const GATE_H := 580.0            ## 门的竖直跨度（故意很大，只做水平触发）

## 调试：`-- --nm-trace` 打开，逐次打印"过了门但为什么给/不给"。
static var debug_trace := false

var kind := 0                    ## TerrainPatterns.LOW / OVERHEAD
var low_judge_top := 0.0         ## 矮障碍**碰撞盒顶**的世界 y（判定基准）
var hazard_left_x := 0.0         ## 障碍左沿的世界 x（悬顶量起滑提前量用）

var _player: Player
var _armed := false
var _min_clear := INF
var _slide_lead := INF
var _hit0 := 0
## 门的**世界**范围。`setup` 时父节点（TerrainChunk）已经在正确位置上了，
## 但那时还没 `add_child` ⇒ 拿不到 `global_position`，所以先存世界值，`_ready` 里换算局部坐标。
var _w_left := 0.0
var _w_right := 0.0
var _w_surface_y := 0.0


func setup(p_kind: int, p_low_judge_top: float, p_left_world: float, p_right_world: float,
		p_surface_y_world: float) -> void:
	kind = p_kind
	low_judge_top = p_low_judge_top
	hazard_left_x = p_left_world
	_w_left = p_left_world
	_w_right = p_right_world
	_w_surface_y = p_surface_y_world
	collision_layer = 8          # 自己的层（近失门）
	collision_mask = LAYER_PLAYER
	monitoring = true
	monitorable = false
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2((p_right_world - p_left_world) + PLAYER_HALF * 2.0, GATE_H)
	cs.shape = sh
	add_child(cs)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	set_process(false)


func _ready() -> void:
	var pw: Vector2 = (get_parent() as Node2D).global_position
	position = Vector2((_w_left + _w_right) * 0.5 - pw.x, _w_surface_y - GATE_H * 0.5 + 90.0 - pw.y)


func _on_enter(body: Node2D) -> void:
	if not (body is Player) or _armed:
		return
	_player = body
	_armed = true
	_min_clear = INF
	_slide_lead = INF
	_hit0 = _player.hit_serial()
	if kind == TerrainPatterns.LOW:
		_track_low()
	else:
		# 悬顶：进门瞬间定"起滑提前量"。已经滑着 → 取当前值；
		# 进门之后才开始滑 → 记 0（最晚 = 最极限）。
		_slide_lead = hazard_left_x - _player.slide_started_x() if _player.is_sliding() else 0.0
	set_process(true)


func _process(_delta: float) -> void:
	if kind == TerrainPatterns.LOW:
		_track_low()


func _track_low() -> void:
	if _player == null:
		return
	# 脚底（玩家的原点就在脚底）在视觉顶之上 → 正数；进到视觉顶以下 → 负数（更贴）
	_min_clear = minf(_min_clear, low_judge_top - _player.global_position.y)


func _on_exit(body: Node2D) -> void:
	if not (body is Player) or not _armed:
		return
	set_process(false)
	_armed = false
	if _player.hit_serial() != _hit0:
		if debug_trace:
			print("[nm] %s 列%.0f → 门里撞过，不给" % [_kind_name(), hazard_left_x / 64.0])
		return
	var ok := false
	var why := ""
	if kind == TerrainPatterns.LOW:
		ok = _min_clear <= GameConfig.near_miss_margin
		why = "最近净空 %.1fpx（阈值 %.0f）" % [_min_clear, GameConfig.near_miss_margin]
	else:
		ok = _slide_lead >= 0.0 and _slide_lead <= GameConfig.near_miss_slide_lead
		why = "起滑提前量 %.1fpx（阈值 %.0f）" % [_slide_lead, GameConfig.near_miss_slide_lead]
	if ok:
		ok = _player.award_near_miss()
		if ok and debug_trace:
			why += " → **给一格**"
		elif debug_trace:
			why += " → 够贴，但势能已满/冲刺中/离上次太近"
	if debug_trace:
		print("[nm] %s 列%.0f %s → %s" % [_kind_name(), hazard_left_x / 64.0, why,
			"给" if ok else "不给"])


func _kind_name() -> String:
	return "矮障碍" if kind == TerrainPatterns.LOW else "悬顶"
