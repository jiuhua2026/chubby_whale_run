extends CharacterBody2D
class_name Player
## 玩家控制器：极简「跳 + 滑」，手感三件套（可变跳跃高度 / 土狼时间 / 输入缓冲）。
##
## 只有两个按键，所以手感完全靠这几件事撑住：
##   · 可变跳跃高度 —— 早松手 = 矮跳，这是唯一的空中微调手段
##   · 土狼时间     —— 离开平台后仍有 ~0.1s 可起跳，消除"明明按了却没跳"
##   · 输入缓冲     —— 落地前按跳，落地瞬间自动生效，消除"按早了跳不起来"
## 这三个数值比任何动作数量都重要，是本地调参的第一优先级。
##
## 速度模型：本作速度不是恒定的。撞击会掉到 40% 并进入短暂僵直，
## 之后按较慢的恢复加速度爬回目标速度——「被追上」的压力就来自这段恢复期。

signal hit_taken(kind: String)

const LAYER_PLAYER := 2
const LAYER_WORLD := 1

## 站立碰撞盒（宽 × 高）。高度必须小于悬顶净空的反面条件：
## TerrainChunk.OVERHEAD_CLEARANCE 必须落在 [滑铲高度, 站立高度] 之间。
const STAND_W := 44.0
const STAND_H := 104.0

enum St { RUN, AIR, SLIDE, STUN, LAND }

@onready var _col: CollisionShape2D = $CollisionShape2D
@onready var _sprite: Sprite2D = $Sprite2D

var speed := 0.0
var state: St = St.RUN
var alive := true

var _anim: WhaleAnimator
var _rect: RectangleShape2D
var _coyote := 0.0
var _buffer := 0.0
## 下滑也有输入缓冲。没有它会出现一个很隐蔽的操作断层：
## 玩家在空中按住下滑键、落地却没反应——因为 is_action_just_pressed 只在按下那一帧为真，
## 而那一帧玩家不在落地状态，之后一直按住就再也不会触发。
## 实测中自动驾驶撞悬顶全部源于此，真人玩家同样会遇到。
var _slide_buffer := 0.0
var _slide_t := 0.0
var _stun := 0.0
var _invuln := 0.0
var _recovering := false
## 累计跑动距离，用于跑步动画按位移同步（比按时间同步更不容易"脚底打滑"）
var _stride_acc := 0.0
## 下落段帧序的基准：刚过最高点时离地面的高度。
## -1 表示还没进入下落段（起跳时重置）。
var _apex_dist := -1.0
## 上一跳的帧序逐帧记录，落地时打印。用来验证"落地帧确实在触地那一刻才出现"。
var _jump_trace: Array[String] = []
## 落地演出的剩余时间。>0 时播跳跃表末尾那几帧（带尘土的落地姿）。
var _land_t := 0.0
var _pre_land_vy := 0.0
var _fastfall_used := false

# ---------------------------------------------------------------- 擦身而过 / 冲刺
## 当前是否已经处在某个「近失外圈」里。
## 做成状态位而不是计数：连续两个障碍的外圈会重叠，进入事件会连发两次，
## 只结算"从没圈到有圈"那一次，一次贴险就只给一格势能。
## 上一次「擦身而过」给分时的世界 x。相邻/同组障碍的门会挨着，
## 用它保证**一次擦身只记一格**（见 `award_near_miss`）。
var _nm_award_x := -1e9
## 本次滑铲的**起滑位置**（世界 x）。悬顶的擦身判定要量"起滑离障碍多近"，
## 因为悬顶的净空恒为 11.9px，距离上不存在"更贴"这回事（见 `NearMissGate`）。
var _slide_started_x := -1e9
## 进入外圈那一刻的受击序号；退出时若序号变了 = 圈内撞到了，这次不算。
var _hit_serial := 0
## 已积攒的势能（格）。攒满 3 格按空格主动释放冲刺。
var dash_charge := 0
## 冲刺剩余时间
var _dash_t := 0.0
## 累计冲刺次数（自检统计用）
var dash_count := 0
## 冲刺特效（残影 + 粒子）。由 Main 注入。
## ⚠ 它是**世界层**节点，绝不能挂成 Player 的子节点 —— 玩家在世界里真前进，
## 挂在下面的话特效会跟着走，拖不出尾巴。缺省 null 时无特效，功能不受影响。
var dash_fx: DashFx = null


func _ready() -> void:
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	floor_snap_length = 8.0
	# 层级：Backdrop -50 < Terrain 0 < 冲刺残影 0 < 冲刺粒子 1 < **玩家 2**
	# < DeathWall 40 < Chaser 45。
	# 玩家必须抬到 2，否则冲刺特效会盖在角色脸上 —— 特效要落在身后才有速度感。
	z_index = 2

	_rect = RectangleShape2D.new()
	_col.shape = _rect
	_set_stand_shape()

	_anim = WhaleAnimator.new()
	_anim.setup(_sprite, GameConfig.CHARACTER_SCALE, Progress.equipped_skin)
	if not _anim.loaded:
		push_error("[Player] 鲸鱼娘帧序列加载失败，检查 sprites/ 目录")
	if not Progress.skin_changed.is_connected(_on_skin_changed):
		Progress.skin_changed.connect(_on_skin_changed)

	speed = GameConfig.run_speed_start


func reset(p_pos: Vector2) -> void:
	global_position = p_pos
	speed = GameConfig.run_speed_start
	velocity = Vector2.ZERO
	state = St.RUN
	alive = true
	_coyote = 0.0
	_buffer = 0.0
	_slide_buffer = 0.0
	_slide_t = 0.0
	_stun = 0.0
	_invuln = 0.0
	_recovering = false
	_stride_acc = 0.0
	_apex_dist = -1.0
	_land_t = 0.0
	_pre_land_vy = 0.0
	_fastfall_used = false
	_jump_trace.clear()
	_hit_serial = 0
	_nm_award_x = -1e9
	_slide_started_x = -1e9
	dash_charge = 0
	_dash_t = 0.0
	dash_count = 0
	if dash_fx != null:
		dash_fx.clear_all()      # 残影是 Tween 驱动的，重开一局必须显式回收
	_sprite.modulate = Color.WHITE
	_set_stand_shape()


func _set_stand_shape() -> void:
	_rect.size = Vector2(STAND_W, STAND_H)
	_col.position = Vector2(0.0, -STAND_H * 0.5)


func _set_slide_shape() -> void:
	var hh := STAND_H * GameConfig.slide_height_ratio
	_rect.size = Vector2(STAND_W * 1.25, hh)
	_col.position = Vector2(0.0, -hh * 0.5)


func is_sliding() -> bool:
	return state == St.SLIDE


func _dump_jump_trace() -> void:
	if not GameConfig.debug_jump_trace or _jump_trace.is_empty():
		return
	print("[跳跃帧序] 共 %d 帧（空中 + 落地演出）" % _jump_trace.size())
	for i in _jump_trace.size():
		print("   %2d  %s" % [i, _jump_trace[i]])
	_jump_trace.clear()


## 诊断用：当前播放的动画动作与帧率
func debug_anim_action() -> String:
	return _anim.current_action() if _anim != null else "-"


func debug_anim_fps() -> float:
	return _anim.last_fps if _anim != null else 0.0


## 吸附前的原始帧率。和 debug_anim_fps() 一起看，差值说明吸附改了多少。
func debug_anim_fps_raw() -> float:
	## 只有跑步走吸附；跳跃 / 滑铲是强制帧序，原始值没有意义，一并返回 0。
	return _anim.last_fps_raw if _anim != null else 0.0


func debug_anim_index() -> int:
	return _anim.current_index() if _anim != null else 0


func debug_anim_count() -> int:
	return _anim.frame_count(_anim.current_action()) if _anim != null else 0


## 跑步 clip 的帧数。和 debug_anim_count() 分开：那个跟着当前动作走，
## 而帧率换算 / 档位体检永远只关心跑步那一段。
func debug_run_frame_count() -> int:
	return _anim.frame_count("run") if _anim != null else 0


# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if not alive or not GameState.is_running():
		_tick_anim(delta)
		return

	_timers(delta)
	_read_input()
	_apply_horizontal(delta)
	_apply_gravity(delta)
	_do_move(delta)
	_update_state()
	_tick_anim(delta)


func _timers(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_buffer = maxf(0.0, _buffer - delta)
	_slide_buffer = maxf(0.0, _slide_buffer - delta)
	_land_t = maxf(0.0, _land_t - delta)
	_stun = maxf(0.0, _stun - delta)
	_invuln = maxf(0.0, _invuln - delta)
	var was_dashing := _dash_t > 0.0
	_dash_t = maxf(0.0, _dash_t - delta)
	# 冲刺刚结束的那一帧：通知特效停掉发射。
	# 用「上一帧还在冲、这一帧不冲了」判定边界，而不是每帧都喊一次 stop。
	if dash_fx != null and was_dashing and _dash_t <= 0.0:
		dash_fx.stop_dash()
	if is_sliding():
		_slide_t += delta
	# 视觉状态优先级：撞击闪白 > 冲刺提亮 > 常态
	if _invuln > 0.0:
		# 无敌期闪白，让"刚刚撞了"这件事在画面上有反馈
		var blink := fmod(_invuln, 0.12) < 0.06
		_sprite.modulate = Color(1.6, 1.2, 1.2) if blink else Color.WHITE
	elif _dash_t > 0.0:
		# 冲刺：提亮 + 偏青。配合帧率自动跳档（20→30fps），
		# 不需要额外特效就能读出"冲出去了"
		_sprite.modulate = Color(1.25, 1.45, 1.65)
	else:
		_sprite.modulate = Color.WHITE


func _read_input() -> void:
	# 冲刺有**独立的键**（空格），不再借用跳键。
	# 借用的时候要纠结"满格按跳到底算跳还是算冲"，而且两个效果会同时发生；
	# 拆开之后"上 = 跳、下 = 滑、空格 = 冲刺"三个键各管一件事，不用猜。
	if Input.is_action_just_pressed("dash") \
			and dash_charge >= GameConfig.dash_charge_max and not is_dashing():
		_start_dash()

	if Input.is_action_just_pressed("jump"):
		_buffer = GameConfig.jump_buffer

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		# 可变跳跃高度：早松手立刻削掉一部分上升速度
		velocity.y *= GameConfig.jump_cut_mult

	# 跳
	if _buffer > 0.0 and (_coyote > 0.0 or is_on_floor()):
		_do_jump()

	# 滑：地面按下立即开始；空中按下记入缓冲，并在空中转为快速下落
	# （快速下落不新增按键，仍是两个键；缓冲保证落地瞬间就能接上）
	if Input.is_action_just_pressed("slide"):
		if is_on_floor():
			_start_slide()
		else:
			_slide_buffer = GameConfig.jump_buffer
			if GameConfig.air_fastfall_enabled:
				velocity.y += GameConfig.air_fastfall_boost
				_fastfall_used = true

	# 滑：松手结束，但受最短持续时间限制，防止连点抖动
	if is_sliding() and not Input.is_action_pressed("slide") \
			and _slide_t >= GameConfig.slide_min_time:
		_end_slide()


func _do_jump() -> void:
	velocity.y = GameConfig.jump_velocity
	_buffer = 0.0
	_coyote = 0.0
	_apex_dist = -1.0          # 重置下落段基准，每次起跳都要重新测
	_land_t = 0.0              # 起跳打断落地演出
	_fastfall_used = false
	_jump_trace.clear()
	if is_sliding():
		_end_slide()
	state = St.AIR
	AudioManager.play_sfx_pitched("jump", -8.0)


func _start_slide() -> void:
	if is_sliding():
		return
	state = St.SLIDE
	_slide_started_x = global_position.x
	_slide_t = 0.0
	_set_slide_shape()


func _end_slide() -> void:
	if not is_sliding():
		return
	state = St.RUN
	_set_stand_shape()


func _apply_horizontal(delta: float) -> void:
	var mult := GameConfig.slide_speed_mult if is_sliding() else 1.0
	# 冲刺叠乘。它只改**目标速度**，实际速度仍受加速度限制 ——
	# 所以冲刺是"推着速度往上走"而不是瞬间位移，结束也会平滑降回来。
	if _dash_t > 0.0:
		mult *= GameConfig.dash_speed_mult
	var target := Difficulty.player_target_speed() * mult

	if _stun > 0.0:
		# 僵直期完全不加速，这是撞击惩罚最重的一部分
		velocity.x = speed
		return

	var accel := GameConfig.accel_recover if _recovering else GameConfig.accel_normal
	speed = move_toward(speed, target, accel * delta)
	if _recovering and speed >= Difficulty.player_target_speed() - 1.0:
		_recovering = false
	velocity.x = speed


func _apply_gravity(delta: float) -> void:
	var g := GameConfig.gravity
	if velocity.y > 0.0:
		g *= GameConfig.fall_gravity_mult
	velocity.y = minf(velocity.y + g * delta, GameConfig.max_fall_speed)


func _do_move(_delta: float) -> void:
	var before := global_position
	_pre_land_vy = velocity.y
	move_and_slide()
	if is_on_floor():
		_coyote = GameConfig.coyote_time
	_stride_acc += absf(global_position.x - before.x)


func _update_state() -> void:
	if _stun > 0.0:
		state = St.STUN
		return
	if not is_on_floor():
		if state != St.SLIDE:
			state = St.AIR
		return
	# 落地
	match state:
		St.AIR:
			# 进入落地演出：跳跃表末尾那几帧（脚后带尘土）只在触地这一刻起播，
			# 播完再回到跑步。这样空中永远不会出现"虚空扬尘"。
			state = St.LAND
			_land_t = GameConfig.jump_landing_time
			_set_stand_shape()
			_apex_dist = -1.0
			if _fastfall_used:
				AudioManager.play_sfx_pitched("heavy_land", -7.0, 0.08)
			if dash_fx != null and (_fastfall_used or _pre_land_vy >= 420.0):
				dash_fx.spawn_landing(global_position, clampf(_pre_land_vy / 760.0, 0.72, 1.0))
			_fastfall_used = false
			# 落地瞬间消化下滑缓冲。用「缓冲 或 键仍按住」两个条件：
			# 缓冲覆盖"空中点一下、落地才生效"；键仍按住覆盖"一直按着下滑键落地"。
			if _slide_buffer > 0.0 or Input.is_action_pressed("slide"):
				_slide_buffer = 0.0
				_start_slide()
		St.LAND:
			if _land_t <= 0.0:
				state = St.RUN
				# 落地演出播完才打印整跳轨迹，这样落地那几帧也在记录里
				_dump_jump_trace()


# ---------------------------------------------------------------- 动画
func _tick_anim(delta: float) -> void:
	if _anim == null or not _anim.loaded:
		return
	if is_sliding() and _anim.has_clip("slide"):
		var n := _anim.frame_count("slide")
		# 滑铲表是「起手 / 滑行 / 起身」三段，按已滑时间映射进度
		var t := clampf(_slide_t / maxf(GameConfig.slide_anim_time, 0.05), 0.0, 1.0)
		_anim.play("slide", delta, 0.0, int(t * float(n - 1)))
		return
	if state == St.LAND and _anim.has_clip("jump"):
		# 落地演出：只播跳跃表末尾那几帧（脚后带尘土的落地姿）。
		# 按剩余时间线性推进，保证起手帧一定出现、且只在触地之后出现。
		var nl := mini(GameConfig.jump_landing_frames, _anim.frame_count("jump"))
		var first := _anim.frame_count("jump") - nl
		var t := 1.0 - clampf(_land_t / maxf(GameConfig.jump_landing_time, 0.001),
			0.0, 1.0)
		var li := first + clampi(int(t * float(nl)), 0, nl - 1)
		if GameConfig.debug_jump_trace:
			_jump_trace.append("y=%5.0f [落地演出] frame=%2d" % [global_position.y, li])
		_anim.play("jump", delta, 0.0, li)
		return
	if not GameState.is_ready_phase() and not is_on_floor() and _anim.has_clip("jump"):
		var ji := _jump_frame_index()
		if GameConfig.debug_jump_trace:
			_jump_trace.append("y=%5.0f vy=%6.0f frame=%2d" % [global_position.y, velocity.y, ji])
		_anim.play("jump", delta, 0.0, ji)
		return
	var anim_spd := speed if not GameState.is_ready_phase() else maxf(speed, 220.0)
	# 跑步：帧率由速度反推，而不是给一个固定值。
	# 等价于「按位移推进动画」——速度变了不会跳帧，脚也不会打滑。
	# 旧写法是 fps = 12 * (速度/基准)，起步只有 12fps，一个循环 1.25 秒，
	# 15 帧被拉得太开，画面上就是明显的阶梯感。
	#
	# 反推出的帧率还要过一遍**吸附**：60Hz 屏幕上 23.5fps 意味着每帧停留
	# 2.55 个显示帧，停留时长会在 2 个 / 3 个之间交替 —— 那就是「跑起来鬼畜」。
	# 吸附到 刷新率/n 之后每帧时长恒定。详见 GameConfig.snap_anim_fps。
	var n_run := _anim.frame_count("run")
	var fps_raw := anim_spd * float(n_run) / maxf(GameConfig.run_cycle_px, 1.0)
	var fps := GameConfig.snap_anim_fps(fps_raw)
	_anim.play("run", delta, fps, -1, fps_raw)


# ---------------------------------------------------------------- 跳跃帧序
## 跳跃动画的帧序不能用「纵向速度比值」来映射。
##
## 踩过的坑：原来写的是 v = -velocity.y / |jump_velocity|，再 clamp 到 [-1,1]。
## 但下落重力有 1.35 倍加成，满跳落地时纵向速度会到 881，**超过参考值 760**，
## 于是被 clamp 卡住、帧序提前顶到最后一帧（落地姿）并一直保持——
## 表现就是「长按跳还在半空，动作已经是落地了」。短按跳得矮、落地速度不到 760，
## 所以不会触发，问题只在长按时出现。
##
## 正确做法：上升段用速度（那时速度不会超参考值），下落段用**离地高度**——
## 射线测出到地面的距离，按「距离 / 最高点高度」归一化，
## 这样无论跳多高，最后一帧一定在触地那一刻才出现。
func _jump_frame_index() -> int:
	var n := _anim.frame_count("jump")
	if n <= 1:
		return 0
	var apex_frame := int(float(n - 1) * clampf(GameConfig.jump_apex_frame_ratio, 0.1, 0.9))

	if velocity.y < 0.0:
		# 上升段：起跳 -> 最高点 映射到 0 -> apex_frame
		var t := 1.0 - clampf(-velocity.y / maxf(absf(GameConfig.jump_velocity), 1.0), 0.0, 1.0)
		return int(t * float(apex_frame))

	# 下落段：刚过最高点时记下离地高度作为基准
	var d := _dist_to_ground()
	if _apex_dist <= 0.0:
		_apex_dist = maxf(d, 1.0)
	var prog := 1.0 - clampf(d / _apex_dist, 0.0, 1.0)
	# 曲线指数 0.5 = 按时间推进（下落是匀加速，时间进度 = 距离比的平方根）。
	# 用距离推进（1.0）的话，顶点姿会挂很久、落地姿一闪而过，观感就是"砸下去"。
	prog = pow(prog, maxf(GameConfig.jump_fall_curve, 0.05))
	# 末尾几帧（脚后带落地尘土的）不属于空中，整段留给触地后的落地演出。
	# 这里只在上半段里分配，空中绝不会播到带尘土的帧。
	var airborne_last := maxi(apex_frame, n - 1 - GameConfig.jump_landing_frames)
	var span := airborne_last - apex_frame
	var idx := apex_frame + roundi(prog * float(span))
	idx = clampi(idx, 0, airborne_last)
	return idx


## 从脚底向下射线测到地面的距离。射线只查地面层（1），
## 障碍是 Area2D 且默认不参与射线，所以不会被障碍挡出假距离。
func _dist_to_ground() -> float:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + Vector2(0.0, GameConfig.ray_probe_len),
		LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return GameConfig.ray_probe_len
	return global_position.distance_to(hit["position"])


# ---------------------------------------------------------------- 撞击
## 撞到障碍：只减速 + 短暂无敌，不致命。致命判定只发生在被追上时。
func take_hit(kind: String) -> void:
	if not alive or not GameState.is_running():
		return
	if _invuln > 0.0:
		return
	if _dash_t > 0.0 and GameConfig.dash_ignores_hazard:
		# 冲刺期间硬穿障碍：不减速、不僵直、势能也不清。
		# 这是冲刺的价值所在 —— 攒满几格势能这个代价，换的就是"能硬冲一段"。
		return
	speed *= GameConfig.hit_speed_mult
	_stun = GameConfig.hit_stun
	_invuln = GameConfig.hit_invuln
	_recovering = true
	# 受击序号 +1 —— 让「这个近失外圈里到底撞没撞到」变得可判定（见 near_miss_exit）
	_hit_serial += 1
	# 贴险失败的代价：攒的势能全丢、正在冲的冲刺也被打断。
	# 这条是这个机制的关键 —— 少了它就成了"只有好处没有代价"，玩家会无脑贴。
	if GameConfig.dash_charge_lose_on_hit:
		dash_charge = 0
		_dash_t = 0.0
		if dash_fx != null:
			dash_fx.stop_dash()      # 冲刺被打断，特效也要跟着收
	AudioManager.play_sfx("hit", 0.0)
	if dash_fx != null:
		dash_fx.spawn_hit(global_position + Vector2(16.0, -14.0))
	hit_taken.emit(kind)
	GameState.player_hit.emit(kind)


# ---------------------------------------------------------------- 擦身而过
## 受击序号。`NearMissGate` 用它判断"过门的这段时间里到底撞没撞到"。
func hit_serial() -> int:
	return _hit_serial


## 本次滑铲的起滑世界 x（没滑过就是 -1e9）。见 `NearMissGate` 的悬顶规则。
func slide_started_x() -> float:
	return _slide_started_x


## 记一次「擦身而过」。**由 `NearMissGate` 在玩家离开障碍时调用** ——
## 判定（贴不贴、算不算）在门那边做，这里只管"给不给得起"。
##
## ⚠ 和旧实现的区别：旧的是"进膨胀圈 → 出圈就 +1"，一个 26px 把两种情况搞反了
## （悬顶必然在圈内、矮障碍正常起跳根本进不去，见 `NearMissGate` 的注释）。
func award_near_miss() -> bool:
	if not alive or not GameState.is_running():
		return false
	if _dash_t > 0.0:
		# 冲刺状态是"无视障碍"，穿过去不算擦身而过 ——
		# 否则一路冲一路白送势能，等于自己给自己续杯
		return false
	if dash_charge >= GameConfig.dash_charge_max:
		return false          # 已经满了，多的擦身而过不叠加
	# **一次擦身只记一格**：同组/相邻障碍的门是挨着的，不加这条的话
	# 一组长障碍（2~3 列悬顶）会连着给两三次。
	if global_position.x < _nm_award_x + float(GameConfig.TILE):
		return false
	_nm_award_x = global_position.x
	dash_charge += 1
	GameState.near_miss_awarded.emit()
	if dash_charge >= GameConfig.dash_charge_max:
		AudioManager.play_sfx("dash_ready", -2.0)
	else:
		AudioManager.play_sfx("near_miss", 0.0)
	# 攒满后**不自动释放** —— 由玩家按空格（dash 键）主动放（见 GameConfig.dash_charge_max）
	return true


func _start_dash() -> void:
	dash_charge = 0
	_dash_t = GameConfig.dash_time
	dash_count += 1
	GameState.dash_started.emit()
	if dash_fx != null:
		dash_fx.start_dash()
	AudioManager.play_sfx("dash", 2.0)


## 冲刺剩余比例（1 → 0），给 HUD 用
func dash_ratio() -> float:
	return _dash_t / maxf(GameConfig.dash_time, 0.001)


func is_dashing() -> bool:
	return _dash_t > 0.0


func _on_skin_changed(skin_id: String) -> void:
	if _anim == null:
		return
	_anim.set_skin(skin_id)
	var cur := _anim.current_action()
	if cur != "":
		_anim.play(cur, 0.0, 12.0, 0)


func kill(reason: String) -> void:
	if not alive:
		return
	alive = false
	speed = 0.0
	velocity = Vector2.ZERO
	GameState.end_run(reason)
