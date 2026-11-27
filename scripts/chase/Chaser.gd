extends Node2D
class_name Chaser
## 高潮追击：黑鲸娘贴身追赶。
##
## 与死亡边界的区别（这是"两者结合"的关键）：
##   死亡边界 —— 恒定前压，压力平缓，由玩家的累计失误喂养。
##   实体追兵 —— 速度 = 玩家当前速度 + 逼近速率，所以**它一定在靠近**。
##              玩家唯一能做的就是在这段距离内一次都不能撞。
##   所以追击段的紧张感来自"零容错"，而不是"慢慢被追上"。
##
## ## 美术（2026-10-17 换真素材）
## 素材由 `tools/chaser_prep.py` 从 `image/boss/pixel_art/chaser_chase_spritesheet.jpg`（追击循环 8 帧）和
## `image/boss/pixel_art/chaser_bite_spritesheet.png`（咬击 4 帧）切出并统一到 ~165px 高：
##   · 灰底抠像：**从四边 BFS 找"真背景"**，角色内部被围住的灰色算前景（不挖洞）
##   · 每格内部过滤连通块：丢碎点、丢**完全落在身体下方**的块（地面阴影；颜色判据分不开，
##     实测阴影平均色离背景 34 = 角色本体也是 34）
##   · 按"格心 x + 底边 y"对齐 ⇒ 保留动作本身的相对位移（前扑会往前探出去）
## · 按中位内容高统一缩放 ⇒ 两套素材切换时不会一大一小
##
## ⚠ **`USE_REAL_ART = false` 可以一键回到手画的占位剪影** ——
##   换美术这种事必须能肉眼 A/B，否则出问题只能靠猜。

const RUN_TEX := [
	preload("res://sprites/chaser_run/chaser_run_01.png"),
	preload("res://sprites/chaser_run/chaser_run_02.png"),
	preload("res://sprites/chaser_run/chaser_run_03.png"),
	preload("res://sprites/chaser_run/chaser_run_04.png"),
	preload("res://sprites/chaser_run/chaser_run_05.png"),
	preload("res://sprites/chaser_run/chaser_run_06.png"),
	preload("res://sprites/chaser_run/chaser_run_07.png"),
	preload("res://sprites/chaser_run/chaser_run_08.png"),
]
## 咬击 4 帧的语义：0 = 待机、1 = 张口前扑、2 = 低头咬合、3 = 回弹。
## 咬击时**从 1 开始**（0 是待机帧，放进咬击里会拖慢起手）。
const BITE_TEX := [
	preload("res://sprites/chaser_bite/chaser_bite_01.png"),
	preload("res://sprites/chaser_bite/chaser_bite_02.png"),
	preload("res://sprites/chaser_bite/chaser_bite_03.png"),
	preload("res://sprites/chaser_bite/chaser_bite_04.png"),
]
const CAST_TEX := [
	preload("res://sprites/chaser_cast/chaser_cast_01.png"),
	preload("res://sprites/chaser_cast/chaser_cast_02.png"),
	preload("res://sprites/chaser_cast/chaser_cast_03.png"),
	preload("res://sprites/chaser_cast/chaser_cast_04.png"),
]
## 咬击播放表：(用第几帧, 停留多久)。**咬合帧(2)停两拍** —— 那一帧是"咬住"的着力点。
const BITE_PLAN := [[1, 0.09], [2, 0.09], [2, 0.10], [3, 0.09]]
## 冲击帧的额外放大（impact scale）。素材在游戏里只有 ~165px 高、牙只有 5~6px，
## 咬合那一下放大 6% 会明显得多。
const BITE_IMPACT_SCALE := 1.06

## 轮廓光：把同一张贴图朝 8 个方向偏移画一遍（染冷青），再把本体盖上去 ⇒ 一圈**软**边。
## **不写 shader**（`--headless` 下 shader 编译不可依赖，而自检/抓帧全靠它）。
## ⚠ 必须克制：亮边会把"幽冥感"变成"vtuber 感" —— 冷、暗、低透明度，主要靠暗晕拉对比。
const RIM_COLOR := Color(0.40, 0.82, 1.0, 0.34)
const RIM_STEP := 1.6
const RIM_DIRS := [
	Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
	Vector2(-0.71, -0.71), Vector2(0.71, -0.71), Vector2(-0.71, 0.71), Vector2(0.71, 0.71),
]
## 身后**冷色雾光**（不是"暗晕"）。
## ⚠ 2026-10-17 改：原本是"她挡光"的暗晕，实测**完全看不出** ——
##   这片海底本来就接近黑（#0a1420），在已经黑了的地方再加黑等于没加。
##   反过来，在她背后加一点冷光 ⇒ 黑剪影被**背光**顶出来，"弹"得多。
const FOG_STEPS := 14          ## 层数少会有肉眼可见的色带（8 层时能看出）
const FOG_R := 1.5          ## 半径 = 精灵长边的一半 × 这个倍数
const FOG_A := 0.008        ## ⚠ 从 0.02 降到 0.008：冷光雾和黑雾是**打架的**
                            ## （一个提亮一个压暗，同时满功率只会糊成一团灰光）。
                            ## 现在只留一点点背光，主角交给墨雾。

## 粒子贴图（`tools/make_fx.py` 生成）。
## ⚠ 不用 `draw_circle`：那是**硬边实心圆**，没有高光/体积，再放大也只是"彩色圆点"——
##   这正是用户说"粒子很粗糙"的直接原因之一。
const TEX_BUBBLE := preload("res://sprites/fx/bubble.png")
const TEX_DUST := preload("res://sprites/fx/dust.png")

const USE_REAL_ART := true
## 咬到的判定距离（px）的**默认值**。实际用 `catch_margin`。
## 跑动帧右侧约有 22~25px 透明留白，取 6.0 让实体口鼻真正贴近主角尾巴/后背再判咬。
const CATCH_MARGIN := 6.0
## 实际判定距离。做成可改的 static，只为了 `-- --bite-demo` / `-- --bite-shot`：
## 追击一开始就直接进咬击，用来拍素材/验收（默认值不变）。
static var catch_margin := CATCH_MARGIN
## 咬合定格时画布右缘相对玩家中轴的目标偏移（贴合咬击帧 10~11px 右侧留白，落到尾巴/后背交界处）
const BITE_TARGET_X := 6.0
## 咬击帧 02/03 嘴爪中心离贴图底边的像素距离
const BITE_MOUTH_FROM_BOTTOM := 48.0
## 进入咬击瞬间对齐贴脸位置的前扑过渡时长（对齐 BITE_PLAN[0] 的 0.09s）
const BITE_LUNGE_DUR := 0.09
## 她脚底离地多高（悬空）。素材本身是浮空姿态、没有影子 ⇒ 悬空 + 无影 = "不像活人"。
const HOVER := 26.0
## 追击循环的前进距离（px/循环）。**只在 `RUN_TIME_DRIVEN = false` 时生效**。
## ⚠ "帧率跟世界位移走"这条规则是给**玩家**定的（脚不能打滑）。她**是飘的、脚不着地**，
##   套这条规则会变成"你跑得越快她抖得越快"：起步 21fps → 满速 **28fps**，
##   而 8 帧几乎一样的姿势以 28fps 轮播，眼睛读到的是**震动**而不是动作。
const RUN_CYCLE_PX := 210.0
## ★ **跑动循环按时间驱动**（2026-10-17）。悬空的东西不该跟位移走。
## 8fps × 8 帧 = 1.0s 一个循环，慢到能看清"呼吸"，快到不像卡住。
const RUN_TIME_DRIVEN := true
const RUN_FPS := 8.0
## 悬停浮动：**两条不同周期的正弦**（竖直 2.4s / 水平 3.1s）。
## 同周期会读成"机械地上下弹"，错开才有"浮在暗流里"的感觉。
const BOB_AMP := 6.0
const BOB_PERIOD := 2.4
const SWAY_AMP := 2.0
const SWAY_PERIOD := 3.1
## 画布右缘到"鼻尖"的距离。素材按"格心 + 底边"对齐，画布右缘是固定的前端参考，
## 所以这里取 0；`gap()` 量的就是她**探得最远时**能到的位置。
const SPRITE_NOSE_OFFSET := 0.0

var x := 0.0
var active := false
## 水流粒子（气泡 / 浮尘）。**手写粒子数组**，照 `DashFx` 的写法 ——
## 不用 GPUParticles2D：数量很小（≤40），而 headless / 抓帧路径不该依赖渲染后端。
class Bubble:
	## ⚠ **相对她"前端 x"的偏移**，不是世界坐标。
	## 她以 ≈773px/s 前进（玩家速度×1.18），世界坐标的气泡 **0.19s 就被甩出生成框**，
	## 屏幕上只剩零星几个"被落在后面"的点 —— 实测截图里就是那样。
	## 改成相对坐标之后，它们**跟着她走**，才会读作"绕着她在翻涌"。
	var off := Vector2.ZERO
	var vel := Vector2.ZERO
	var t := 0.0
	var life := 1.0
	var r := 6.0
	var a := 0.6
	var dust := false

## 墨雾：**绕着她身体转的一圈暗雾**（用户要求"用黑雾缠绕"）。
##
## ⚠ 黑雾在近黑背景上**看不见** —— 它必须靠"遮住亮的东西"才成立（地板块/背景脊线/光柱）。
##   所以做法不是"画一团很黑的东西"，而是：
##     · 用 `dust.png`（柔光斑）**染深色**当雾团 —— modulate 是乘法，浅色贴图 × 深色 = 暗色团 ✓
##     · 每个雾团先画一个**更大、更冷**的副本垫底 ⇒ 暗团外面有一圈冷光晕，空背景上也读得出
##     · 覆盖面积靠"数量 + 大小"，不靠 alpha 拉满（拉满就成一块脏斑了）
const MIST_COUNT := 16
const MIST_ELLIPSE := Vector2(0.62, 0.78)   ## 环绕半径 = 精灵一半宽高 × 这个比例
const MIST_RIM := Color(0.20, 0.36, 0.52, 0.05)   ## 只留一丝冷边，多了就成光环
const MIST_BODY := Color(0.04, 0.07, 0.12, 0.55)  ## 真正的黑靠这个（压暗底下的层次）

class Mist:
	var ang := 0.0        ## 绕她身体的极角
	var spin := 0.0       ## 角速度（rad/s）—— 正负都有，才不像一个整体在转
	var rad := 1.0        ## 半径倍率（呼吸）
	var breathe := 0.0    ## 呼吸相位
	var r := 44.0         ## 雾团半径（像素）
	var a := 0.42
	var t := 0.0

var _player: Player
var _bubbles: Array[Bubble] = []
var _mist: Array[Mist] = []
var _spawn_acc := 0.0

var _anim_t := 0.0
## 追击循环已经走了多少世界距离（驱动帧号）。
var _anim_px := 0.0
## 咬击计时。**< 0 = 没在咬**；>= 0 时按 `BITE_PLAN` 出帧。
var _bite_t := -1.0
## "亮爪子"计时。>0 时画咬击素材里的**蓄力/前扑**两帧，而不是巡航帧。
## 追击中玩家失误（被撞）时触发 —— 让她"有反应"，而不是匀速滑行的装饰。
var _taunt_t := -1.0
var _taunt_dur := 0.22
var _cast_t := -1.0
var _cast_dur := 0.60
var _rush_boost_t := 0.0
var _pose_stage := 0
var _knockback_rem := 0.0
var _hit_flash_t := 0.0
var _last_player_x := 0.0
var _stall_t := 0.0
## 失误急冲尚未走完的位移余量（px）
var _lunge_rem := 0.0
## 纵向追击/扑咬偏移（平时微弱跟随，咬击时对齐蓝鲸娘纵坐标实现凌空扑咬）
var _y_off := 0.0
var _bite_start_x := 0.0
var _bite_target_x := 0.0
var _bite_start_y := 0.0
var _bite_target_y := 0.0
## 咬击总时长（播放表求和）。播放表改了就自动跟着变，不要另写一个常量。
var _bite_total := 0.0
var _heartbeat_t := 0.0

## 当前透明度（0 = 完全透明、1 = 完全不透明）。
## ⚠ **出现/消失一律走这个值，不要再拿 `visible` 当开关** ——
## `visible = false` 就是"瞬间消失"，而那正是用户要改掉的东西（见 `end()`）。
var _fade := 0.0
var _fade_target := 0.0
## 本轮追击是否已经开始淡入。见 `_step_fade()`：淡入要等它**真的进画面**。
var _revealed := false
## 追击结束那一刻的缺口。淡出期间缺口从这里开始按 `chaser_leave_rate` 慢慢拉大 ——
## 光靠"x 停住"会让玩家在 0.75s 里把它甩出画面，淡出看不见（见 GameConfig 的注释）。
var _leave_gap := 0.0
var _bite_claw: PixelFxPlayer = null
var _dark_burst: PixelFxPlayer = null

class EnrageGhost:
	var px := 0.0
	var py := 0.0
	var tw := 0.0
	var th := 0.0
	var t := 0.0
	var life := 0.24
	var tex: Texture2D

var _ghosts: Array[EnrageGhost] = []
var _ghost_acc := 0.0


func setup(player: Player) -> void:
	_player = player
	# 追击中玩家失误 ⇒ 她猛扑（见 `_on_player_hit`）
	player.hit_taken.connect(_on_player_hit)
	z_index = 45
	for p in BITE_PLAN:
		_bite_total += float(p[1])
	_fade = 0.0
	_apply_fade()
	visible = false


func _init_mist() -> void:
	_mist.clear()
	for i in MIST_COUNT:
		var m := Mist.new()
		m.ang = randf() * TAU
		m.spin = randf_range(-0.9, 0.9)
		m.rad = randf_range(0.72, 1.15)
		m.breathe = randf() * TAU
		m.r = randf_range(44.0, 80.0)
		m.a = randf_range(0.34, 0.60)
		_mist.append(m)


func begin(player_x: float) -> void:
	_clear_fx()
	x = player_x - GameConfig.chaser_start_gap
	active = true
	_anim_t = 0.0
	_anim_px = 0.0
	_heartbeat_t = 0.6
	_bite_t = -1.0
	_taunt_t = -1.0
	_cast_t = -1.0
	_rush_boost_t = 0.0
	_pose_stage = clampi(GameState.boss_max_hp - GameState.boss_hp, 0, 3)
	if GameState.boss_enraged:
		_pose_stage = 3
	_stall_t = 0.0
	_last_player_x = player_x
	_knockback_rem = 0.0
	_hit_flash_t = 0.0
	_lunge_rem = 0.0
	_y_off = 0.0
	_ghosts.clear()
	_ghost_acc = 0.0
	# ⚠ 顺序要紧：**先把透明度归零写进 modulate，再 visible = true**。
	#   反过来的话第一帧会用上一次残留的 modulate（默认是 1）闪一下。
	_fade = 0.0
	_fade_target = 1.0
	_revealed = false
	_apply_fade()
	visible = true
	_bubbles.clear()
	# 追击开始时铺一圈墨雾（每个雾团自己转，不会被重生打断 ⇒ 才是"缠绕"）
	_init_mist()


## 追击正常结束：**交给淡出收尾**，不要直接隐藏。
##
## ⚠ 追击结束时黑鲸娘就在屏幕里，所以 `visible = false` 会被看见成"啪一下没了"。
## 这里只把目标透明度改成 0，真正的 `visible = false` 发生在淡出跑完之后。
func end() -> void:
	active = false
	_lunge_rem = 0.0
	_knockback_rem = 0.0
	_cast_t = -1.0
	_leave_gap = gap()
	_fade_target = 0.0


## 二阶段施法前摇与释放（播 4 帧 chaser_cast）
func trigger_cast(duration: float = 0.60) -> void:
	if _bite_t >= 0.0:
		return
	_cast_dur = maxf(duration, 0.20)
	_cast_t = _cast_dur
	queue_redraw()


## 二阶段转入“召弹试炼”时撤出贴身追击：不再同时在背后追咬玩家
func retreat_for_barrage() -> void:
	active = false
	_lunge_rem = 0.0
	_knockback_rem = 0.0
	_leave_gap = maxf(gap(), 120.0)
	_fade_target = 0.0


## 受到玩家近身 Space 水压冲击波命中：击退并切换对应扣血形态（图1/2/3），随即疾追回逼再慢慢消散
func knockback(dist_px: float) -> void:
	if not active or _bite_t >= 0.0:
		return
	_knockback_rem += maxf(dist_px, 0.0)
	_hit_flash_t = 0.26
	_rush_boost_t = GameConfig.boss_post_hit_rush_sec
	_pose_stage = clampi(GameState.boss_max_hp - GameState.boss_hp, 1, 3)
	if GameState.boss_enraged:
		_pose_stage = 3
	_lunge_rem = 0.0
	AudioManager.play_sfx("hit", 1.5, 0.78)
	queue_redraw()


## 二阶段红转黑锁血转场爆发特效
func play_enrage_burst() -> void:
	_spawn_dark_explosion()
	_hit_flash_t = 0.35
	queue_redraw()


## 真·神庙起跑过场（Phase.READY）：携带完整缠绕墨雾与奔跑帧从左涌入，再被跑道甩出左缘。
func begin_cameo(p_x: float) -> void:
	_clear_fx()
	x = p_x
	active = false
	_anim_t = 0.0
	_anim_px = 0.0
	_bite_t = -1.0
	_taunt_t = -1.0
	_cast_t = -1.0
	_rush_boost_t = 0.0
	_pose_stage = 0
	_stall_t = 0.0
	_last_player_x = p_x
	_knockback_rem = 0.0
	_hit_flash_t = 0.0
	_lunge_rem = 0.0
	_y_off = 0.0
	_ghosts.clear()
	_ghost_acc = 0.0
	_fade = 0.35
	_fade_target = 1.0
	_revealed = true
	_apply_fade()
	visible = true
	_bubbles.clear()
	_init_mist()
	queue_redraw()


func trigger_cameo_taunt(duration: float = 0.34) -> void:
	_taunt_dur = maxf(duration, 0.05)
	_taunt_t = _taunt_dur
	_spawn_dark_explosion()
	queue_redraw()


func step_cameo(delta: float, p_x: float, fade_target: float, fade_rate: float = 4.5, spawn_dust: bool = true) -> void:
	x = p_x
	_anim_t += delta
	if _taunt_t > 0.0:
		_taunt_t = maxf(0.0, _taunt_t - delta)
	_fade_target = clampf(fade_target, 0.0, 1.0)
	_fade = move_toward(_fade, _fade_target, fade_rate * delta)
	_apply_fade()
	_sync_fx_pos()
	_step_bubbles(delta, spawn_dust and _fade > 0.20)
	visible = _fade > 0.005
	if visible:
		queue_redraw()


## 立刻隐藏、不淡出。**只用于重置/重开**（`Main._on_run_started`）——
## 那是必须硬切的地方：新一局开始的瞬间不该看到上一局残留的淡出/咬击。
func snap_hidden() -> void:
	_clear_fx()
	active = false
	_fade = 0.0
	_fade_target = 0.0
	_revealed = false
	_leave_gap = 0.0
	_bite_t = -1.0
	_taunt_t = -1.0
	_cast_t = -1.0
	_rush_boost_t = 0.0
	_pose_stage = 0
	_stall_t = 0.0
	_last_player_x = 0.0
	_knockback_rem = 0.0
	_hit_flash_t = 0.0
	_lunge_rem = 0.0
	_y_off = 0.0
	_ghosts.clear()
	_ghost_acc = 0.0
	_mist.clear()
	_anim_t = 0.0
	_anim_px = 0.0
	_heartbeat_t = 0.0
	_apply_fade()
	visible = false


## 把 `_fade` 写进 `modulate`。用 modulate 而不是在每个 `draw_*` 里乘 alpha：
## 一处生效、也不用每帧重画（modulate 是渲染期属性，改了立刻生效）。
func _apply_fade() -> void:
	modulate = Color(1.0, 1.0, 1.0, _fade)


## 造型的"鼻尖"是否已经越过可视左边缘。
##
## 为什么需要它：追击一开始黑鲸娘在玩家身后 `chaser_start_gap`(520px)，
## 而相机把玩家钉在屏幕 30% 处 ⇒ 可视左边缘只到 `player.x − 0.30·viewport`(384px)。
## 也就是说**开局它在画面外 136px**，要等缺口收到 ~378px 才露头。
## 不等进画面就淡入的话，整个过程全发生在屏幕外 —— 玩家看到的还是"从左边直接滑进来"。
## 口径与 `Main._hazard_on_screen()` 一致（同一个相机公式）。
func _sprite_in_view() -> bool:
	if _player == null:
		return true
	var vw := get_viewport_rect().size.x
	var left_edge := _player.global_position.x \
		- GameConfig.camera_player_screen_ratio * vw
	return x - SPRITE_NOSE_OFFSET >= left_edge


## 推进淡入/淡出。
##
## ⚠ **必须跑在 `active` 判定之前**：淡出要在 `active` 已经变 false 之后继续跑完
## （`end()` 只改目标值，不隐藏）。原来 `update()` 第一行就是 `if not active: return`，
## 那种结构下"结束之后还要继续播的动画"根本推进不了。
func _step_fade(delta: float) -> void:
	if _fade_target > 0.0 and not _revealed:
		if not _sprite_in_view():
			return
		_revealed = true
		_spawn_dark_explosion()
	var fade_in_spd := GameConfig.boss_p2_fade_in_speed if GameState.boss_enraged else GameConfig.chaser_fade_in_speed
	var speed := fade_in_spd if _fade_target > 0.0 \
		else GameConfig.chaser_fade_out_speed
	_fade = move_toward(_fade, _fade_target, speed * delta)
	_apply_fade()
	if _fade_target <= 0.0 and _fade <= 0.0:
		# 淡出跑完才真正隐藏：省掉之后的每帧绘制，也让"消失"有一个可见的收尾
		visible = false
		_revealed = false


func gap() -> float:
	if _player == null:
		return 0.0
	return _player.global_position.x - x


## 当前透明度（0~1）。给自检日志用 —— 淡入淡出是**时序**行为，
## 只看截图很难确认"是不是真的渐变的"，把数值打出来才能一眼验证。
func opacity() -> float:
	return _fade


## 压迫感强度 0~1（给镜头/暗角用）：缺口从 `chaser_start_gap` 收到 `chaser_min_gap` 时升到 1。
## ⚠ 用**缺口**而不是时间：失误猛扑让她掉到 130 以下之后，这个值会一直保持 1 ✓
##   那正是想要的 —— 她贴着你的时候，画面应该一直是紧的。
func pressure() -> float:
	if _player == null or not active:
		return 0.0
	var span := GameConfig.chaser_start_gap - GameConfig.chaser_min_gap
	return clampf(1.0 - (gap() - GameConfig.chaser_min_gap) / span, 0.0, 1.0)


## 玩家被撞：**她当场加速猛扑一段**。
##
## 不直接瞬移 +60px、也不提前亮张嘴咬击帧，而是用 ~0.20s 平滑急冲拉近距离：
## 只有真的冲到贴身判定线以内时，才亮爪扑咬，避免"明明隔着一段却突然定住咬人"。
func _on_player_hit(_kind: String) -> void:
	if not active or _player == null:
		return
	_lunge_rem += GameConfig.chaser_hit_lunge
	if _dark_burst == null or not is_instance_valid(_dark_burst):
		_spawn_dark_explosion()
	queue_redraw()


## 是否正在播咬击（给自检/调试看）。
func is_biting() -> bool:
	return _bite_t >= 0.0


func update(delta: float) -> void:
	_step_fade(delta)
	_step_bubbles(delta)
	if _player == null or not GameState.is_running():
		return
	if not active:
		# 淡出期间：**一边慢慢后退一边淡**（缺口从 `end()` 那一刻的值开始拉大）。
		# 不这样处理的话玩家会立刻把它甩出画面，淡出等于发生在屏幕外。
		if _fade > 0.0:
			_leave_gap += GameConfig.chaser_leave_rate * delta
			x = _player.global_position.x - _leave_gap
			queue_redraw()
		return

	var anim_mult := 1.0
	if _lunge_rem > 0.0 or _rush_boost_t > 0.0:
		anim_mult = 1.45
	elif GameState.boss_enraged:
		anim_mult = 1.25
	_anim_t += delta * anim_mult
	if _taunt_t > 0.0:
		_taunt_t -= delta
	if _rush_boost_t > 0.0:
		_rush_boost_t = maxf(0.0, _rush_boost_t - delta)
	if _cast_t > 0.0:
		_cast_t = maxf(-1.0, _cast_t - delta)
		if _cast_t == 0.0:
			_cast_t = -1.0
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)

	# 狂暴(第3次扣血/二阶段)拖尾残影步进
	var alive_ghosts: Array[EnrageGhost] = []
	for g in _ghosts:
		g.t += delta
		if g.t < g.life:
			alive_ghosts.append(g)
	_ghosts = alive_ghosts
	if (GameState.boss_enraged or _pose_stage >= 3) and _bite_t < 0.0 and _fade > 0.20:
		_ghost_acc += delta
		if _ghost_acc >= 0.045:
			_ghost_acc -= 0.045
			var sel_g := _select_draw_tex()
			var g_tex: Texture2D = sel_g[0]
			var g_mul := float(sel_g[1])
			var g := EnrageGhost.new()
			g.tex = g_tex
			g.tw = float(g_tex.get_width()) * g_mul
			g.th = float(g_tex.get_height()) * g_mul
			var bob_g := sin(_anim_t * TAU / BOB_PERIOD) * BOB_AMP
			var sway_g := sin(_anim_t * TAU / SWAY_PERIOD) * SWAY_AMP
			g.px = x + sway_g - g.tw
			g.py = -HOVER + _y_off + bob_g - g.th
			_ghosts.append(g)
			if _ghosts.size() > 6:
				_ghosts.pop_front()

	if absf(_player.global_position.x - _last_player_x) < 12.0 * delta:
		_stall_t += delta
	else:
		_stall_t = 0.0
	_last_player_x = _player.global_position.x

	# 追击贴身心跳（越近越急促、音量越大）
	if _fade > 0.05 and _bite_t < 0.0:
		_heartbeat_t -= delta
		if _heartbeat_t <= 0.0:
			var pr := pressure()
			_heartbeat_t = lerpf(1.15, 0.42, pr)
			var v_db := lerpf(-6.0, 1.5, pr)
			AudioManager.play_sfx("chase_heartbeat", v_db)

	# ★ 被弹开后先用新怒态迅速追上来再消散；二阶段彻底狂暴时逼近更猛；若玩家卡墙停滞则忽略最小距离直接扑咬
	var close_ratio := GameConfig.boss_p2_close_ratio if GameState.boss_enraged else GameConfig.chaser_close_ratio
	var min_gap := GameConfig.boss_p2_min_gap if GameState.boss_enraged else GameConfig.chaser_min_gap
	if _rush_boost_t > 0.0:
		close_ratio = maxf(close_ratio, GameConfig.boss_post_hit_close_ratio)
		min_gap = minf(min_gap, 82.0)
	var v := _player.speed
	if _stall_t > 0.60:
		v = maxf(_player.speed, 540.0) * 1.38
	else:
		var room := gap() - min_gap
		if room > 0.0:
			var extra := (_player.speed * close_ratio - _player.speed) * delta
			v = _player.speed + minf(extra, room) / maxf(delta, 0.0001)
	var lunge_step := 0.0
	if _lunge_rem > 0.0:
		lunge_step = minf(_lunge_rem, GameConfig.chaser_lunge_speed * delta)
		_lunge_rem -= lunge_step
	var kb_step := 0.0
	if _knockback_rem > 0.0:
		kb_step = minf(_knockback_rem, 620.0 * delta)
		_knockback_rem -= kb_step
	x += v * delta + lunge_step - kb_step
	var target_y := clampf(_player.global_position.y * 0.45, -96.0, 128.0)
	_y_off = lerpf(_y_off, target_y, clampf(5.0 * delta, 0.0, 1.0))
	# 动画帧号跟**世界位移**走（不跟时间走），和玩家 run 动画同口径
	_anim_px = fmod(_anim_px + v * delta + lunge_step, RUN_CYCLE_PX * float(RUN_TEX.size()))
	_sync_fx_pos()
	queue_redraw()

	if _player.global_position.x - x <= catch_margin:
		_start_bite()


## 被咬到：**不立刻隐藏，就地播完咬击再收网**。
##
## ⚠ 这里仍然**立刻**调用 `_player.kill()` —— 那是故意的：
##   `kill()` 让 `GameState` 进入 ENDED ⇒ `Main._physics_process` 直接返回 ⇒
##   **整个世界冻结（hit-stop）**。冻结的这 ~0.4s 里只有本节点的 `_process` 在推进咬击帧，
##   于是玩家看到的是"最后一帧定住 + 她凌空扑上去真咬住尾巴/后背"。
func _start_bite() -> void:
	if _bite_t >= 0.0:
		return
	_bite_t = 0.0
	_lunge_rem = 0.0
	_taunt_t = -1.0
	_bite_target_x = _player.global_position.x + BITE_TARGET_X
	_bite_start_x = maxf(x, _player.global_position.x - 36.0)
	x = _bite_start_x
	_bite_start_y = _y_off
	var player_cy := _player.global_position.y - (28.0 if _player.is_sliding() else 52.0)
	_bite_target_y = minf(player_cy + HOVER + BITE_MOUTH_FROM_BOTTOM, _player.global_position.y + HOVER)
	_fade = 1.0
	_apply_fade()
	visible = true
	_spawn_bite_claw(player_cy)
	queue_redraw()
	AudioManager.play_sfx("chase_bite", 2.0)
	_player.kill("caught_by_chaser")


func _spawn_bite_claw(player_cy: float) -> void:
	if _bite_claw != null and is_instance_valid(_bite_claw):
		_bite_claw.queue_free()
	var fx := PixelFxPlayer.new()
	fx.z_index = 1
	fx.scale = Vector2(1.85, 1.85)
	fx.modulate = Color(1.0, 1.0, 1.0, 0.96)
	fx.position = Vector2(_player.global_position.x - 74.0, player_cy + 33.0)
	add_child(fx)
	if not fx.play("chase/claw_swipe", true, 1.65, 0.02, true):
		fx.queue_free()
		return
	_bite_claw = fx


func _spawn_dark_explosion() -> void:
	if _dark_burst != null and is_instance_valid(_dark_burst):
		_dark_burst.queue_free()
	var fx := PixelFxPlayer.new()
	fx.z_index = -1
	fx.scale = Vector2(1.15, 1.15)
	fx.modulate = Color(0.85, 0.95, 1.0, 0.72)
	add_child(fx)
	if not fx.play("chase/dark_explosion", true, 1.80, 0.13, true):
		fx.queue_free()
		return
	_dark_burst = fx
	_sync_fx_pos()


func _sync_fx_pos() -> void:
	if _dark_burst != null and is_instance_valid(_dark_burst):
		_dark_burst.position = Vector2(x - 84.0, -HOVER + _y_off - 22.0)
	elif _dark_burst != null:
		_dark_burst = null


func _clear_fx() -> void:
	if _bite_claw != null and is_instance_valid(_bite_claw):
		_bite_claw.queue_free()
	_bite_claw = null
	if _dark_burst != null and is_instance_valid(_dark_burst):
		_dark_burst.queue_free()
	_dark_burst = null
	_ghosts.clear()
	_ghost_acc = 0.0


## 咬击帧推进。**不走 `update()`**：世界已经冻结（`is_running() == false`），
## `update()` 靠 `Main._physics_process` 调，那时已经不再调用它了。
func _process(delta: float) -> void:
	if _bite_t < 0.0:
		return
	if _bite_t > _bite_total + 0.8:
		return          # 面板早就弹出来了，不用再重画
	_bite_t += delta
	var lp := clampf(_bite_t / BITE_LUNGE_DUR, 0.0, 1.0)
	var ease_lp := 1.0 - pow(1.0 - lp, 2.0)
	x = lerpf(_bite_start_x, _bite_target_x, ease_lp)
	_y_off = lerpf(_bite_start_y, _bite_target_y, ease_lp)
	queue_redraw()


## 推进水流粒子，并按贴近度补充新粒子。
## 她越近水越"浑"（生成率 14 → 46 /s）；淡出期间只更新不补充，让它们自然飘散。
func _step_bubbles(delta: float, force_spawn: bool = false) -> void:
	for m in _mist:
		m.t += delta
		m.ang += m.spin * delta
	# 墨雾只是衰减时慢慢散开（`_fade` 归零后一并收掉）
	if _fade <= 0.01:
		_mist.clear()

	var alive: Array[Bubble] = []
	for b in _bubbles:
		b.t += delta
		b.off += b.vel * delta
		if not b.dust:
			# 气泡边上浮边左右微摆（用 t 和 r 当相位，避免所有泡同步摆）
			b.vel.y -= 6.0 * delta
			b.vel.x += sin((b.t + b.r) * 7.0) * 10.0 * delta
		if b.t < b.life:
			alive.append(b)
	_bubbles = alive

	if not force_spawn and (not active or _bite_t >= 0.0 or _player == null):
		return
	# 生成率从 14~46/s 降到 7~16/s：**少而清楚 > 多而看不见**（原来那些只有 1~3px）
	# 只留浮尘（气泡换成墨雾了 —— 两者混在一起会脏）
	var rate := 8.0 if force_spawn else (lerpf(4.0, 9.0, pressure()) + (10.0 if _lunge_rem > 0.0 else 0.0))
	if GameState.boss_enraged or _pose_stage >= 3:
		rate += 16.0
	_spawn_acc += delta * rate
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		var b := Bubble.new()
		var flame := GameState.boss_enraged or _pose_stage >= 3
		b.dust = not flame
		# off.x ∈ [-150, 0]（她身体的范围，0 = 前端）；off.y ∈ [-195, -30]（她身体的高度）
		b.off = Vector2(-randf() * 150.0, randf_range(-195.0, -30.0))
		if flame:
			b.r = randf_range(4.0, 9.0)
			b.a = randf_range(0.42, 0.72)
			b.life = randf_range(0.32, 0.62)
			b.vel = Vector2(randf_range(-240.0, -110.0), randf_range(-42.0, 26.0))
		elif b.dust:
			b.r = randf_range(3.0, 6.0)
			b.a = randf_range(0.20, 0.35)
			b.life = randf_range(0.9, 1.7)
			b.vel = Vector2(randf_range(-16.0, -6.0), randf_range(-14.0, -4.0))
		else:
			b.r = randf_range(6.0, 11.0)
			b.a = randf_range(0.45, 0.75)
			b.life = randf_range(0.7, 1.3)
			b.vel = Vector2(randf_range(-14.0, -5.0), randf_range(-26.0, -10.0))
		_bubbles.append(b)
		if _bubbles.size() > 36:
			_bubbles.pop_front()


## 墨雾：先垫一层更大更冷的，再盖一层暗的 ⇒ 暗团 + 冷光晕。
## 位置在**她身体的椭圆轨道**上 ⇒ 读作"缠绕"，而不是"随机飘"。
func _draw_mist(center: Vector2, tw: float, th: float, front: bool) -> void:
	var rx := tw * 0.5 * MIST_ELLIPSE.x
	var ry := th * 0.5 * MIST_ELLIPSE.y
	var fade_k := clampf(_fade, 0.0, 1.0)
	var idx := 0
	for m in _mist:
		# 一半雾团在前、一半在后 ⇒ 有的雾会从她身上飘过去
		var is_front := (idx % 2) == 1
		idx += 1
		if is_front != front:
			continue
		var br := 1.0 + 0.12 * sin(m.breathe + m.t * 1.7)
		var p := center + Vector2(cos(m.ang) * rx * m.rad * br,
			sin(m.ang) * ry * m.rad * br)
		var r := m.r * br
		# 冷光晕（垫底）
		draw_texture_rect(TEX_DUST, Rect2(p.x - r * 1.55, p.y - r * 1.55,
			r * 3.1, r * 3.1), false,
			Color(MIST_RIM.r, MIST_RIM.g, MIST_RIM.b, MIST_RIM.a * fade_k))
		# 暗雾本体（modulate 是乘法：浅色柔光斑 × 深色 = 暗色团）
		draw_texture_rect(TEX_DUST, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false,
			Color(MIST_BODY.r, MIST_BODY.g, MIST_BODY.b, m.a * fade_k))


func _draw_bubbles() -> void:
	for b in _bubbles:
		var k := 1.0 - b.t / b.life
		var p := Vector2(x + b.off.x, b.off.y + _y_off)      # 世界位置 = 她的前端 + 相对偏移
		var r := b.r * (0.75 + 0.25 * k)            # 将消失时略微缩小
		var tex := TEX_DUST if b.dust else TEX_BUBBLE
		var tint := Color(1.0, 1.0, 1.0, b.a * k)
		if not b.dust and (GameState.boss_enraged or _pose_stage >= 3):
			tint = Color(0.95, 0.26, 0.68, b.a * k) if int(b.r * 10.0) % 2 == 0 else Color(0.40, 0.92, 1.0, b.a * k)
		draw_texture_rect(tex, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, tint)


## 咬击播放表 → 当前该用哪一帧、要不要放大。
func _bite_frame() -> Array:
	var t := _bite_t
	for p in BITE_PLAN:
		var dur := float(p[1])
		if t < dur:
			return [int(p[0]), true if int(p[0]) == 2 else false]
		t -= dur
	return [int(BITE_PLAN[BITE_PLAN.size() - 1][0]), false]


## 返回当前应绘制的纹理与倍率：[Texture2D, scale_mul]，保证阶段姿态与咬击特写零鬼畜
func _select_draw_tex() -> Array:
	if _taunt_t > 0.0 and _bite_t < 0.0:
		var ph := 1.0 - _taunt_t / maxf(_taunt_dur, 0.001)
		return [BITE_TEX[1] if ph < 0.62 else BITE_TEX[0], 1.0]
	if _bite_t >= 0.0:
		# 二阶段狂暴咬住：专用图 4（chaser_cast_03.png）扑抓爆裂；一阶段维持原张口扑咬
		if GameState.boss_enraged:
			return [CAST_TEX[2], BITE_IMPACT_SCALE]
		var bf := _bite_frame()
		return [BITE_TEX[int(bf[0]) % BITE_TEX.size()], BITE_IMPACT_SCALE if bf[1] else 1.0]
	if _cast_t >= 0.0 or GameState.boss_enraged or _pose_stage >= 3:
		# 第3次扣血 & 整个狂暴阶段：定用图 3（chaser_cast_02.png），杜绝鬼畜乱跳
		return [CAST_TEX[1], 1.0]
	if _pose_stage == 2:
		# 第2次扣血：定用图 2（chaser_cast_01.png）
		return [CAST_TEX[0], 1.0]
	if _pose_stage == 1:
		# 第1次扣血：定用图 1（chaser_cast_04.png）
		return [CAST_TEX[3], 1.0]
	var n := RUN_TEX.size()
	var idx := 0
	if RUN_TIME_DRIVEN:
		idx = posmod(int(_anim_t * RUN_FPS), n)
	else:
		idx = posmod(int(_anim_px / RUN_CYCLE_PX * float(n)), n)
	return [RUN_TEX[idx], 1.0]


func _draw() -> void:
	if not USE_REAL_ART:
		_draw_placeholder()
		return

	var sel := _select_draw_tex()
	var tex: Texture2D = sel[0]
	var mul := float(sel[1])

	var tw := float(tex.get_width()) * mul
	var th := float(tex.get_height()) * mul
	var enr_anim := (GameState.boss_enraged or _pose_stage >= 3) and _bite_t < 0.0
	if enr_anim:
		var breath := 1.0 + 0.042 * sin(_anim_t * 14.0)
		tw *= breath
		th *= (2.0 - breath)
	# 悬停浮动。⚠ 咬击时让它 0.1s 内收掉：咬住那一下要"定住"，
	#   不然她一边咬一边往上飘，冲击力就散了。
	var settle := 1.0
	if _bite_t >= 0.0:
		settle = clampf(1.0 - _bite_t / 0.1, 0.0, 1.0)
	var bob := sin(_anim_t * TAU / BOB_PERIOD) * BOB_AMP * settle
	var sway := sin(_anim_t * TAU / SWAY_PERIOD) * SWAY_AMP * settle
	var px := x + sway - tw
	var py := -HOVER + _y_off + bob - th

	# 0) 狂暴残影拖尾（猩红/暗紫水影拉出高速俯冲动效）
	for g in _ghosts:
		if g.tex == null:
			continue
		var gk := 1.0 - clampf(g.t / maxf(g.life, 0.01), 0.0, 1.0)
		var g_back := (1.0 - gk) * 32.0
		var gs := 0.94 + 0.06 * gk
		var gw := g.tw * gs
		var gh := g.th * gs
		draw_texture_rect(
			g.tex,
			Rect2(g.px - g_back + (g.tw - gw) * 0.5, g.py + (g.th - gh) * 0.5, gw, gh),
			false,
			Color(0.98, 0.20, 0.52, 0.42 * gk * clampf(_fade, 0.0, 1.0))
		)

	# ① 身后背光（常态冷青 / 二阶段狂暴猩红暗紫）
	var cx := px + tw * 0.5
	var cy := py + th * 0.5
	var fr := maxf(tw, th) * 0.5 * FOG_R
	var fog_col := Color(0.85, 0.14, 0.34, FOG_A * 2.1) if GameState.boss_enraged else Color(0.30, 0.58, 0.85, FOG_A)
	for i in FOG_STEPS:
		var k := float(i) / float(FOG_STEPS)
		draw_circle(Vector2(cx, cy), fr * (1.0 - k * 0.62), fog_col)

	# ② 墨雾（后半）：垫在她身后
	_draw_mist(Vector2(cx, cy), tw, th, false)

	# ②b 浮尘 / 狂暴火花
	_draw_bubbles()

	# ③ 拉丝：她掀起的细水流
	for i in 3:
		var ph := _anim_t * (1.7 + 0.5 * float(i)) + float(i) * 2.1
		var sl := (70.0 + 45.0 * sin(ph)) * (1.45 if (_lunge_rem > 0.0 or GameState.boss_enraged) else 1.0)
		var yy := -48.0 + _y_off - float(i) * 42.0
		var aa := (0.07 + 0.05 * sin(ph * 1.37)) * clampf(_fade, 0.0, 1.0)
		if aa > 0.01:
			var streak_col := Color(1.0, 0.28, 0.52, aa * 1.6) if GameState.boss_enraged else Color(0.55, 0.80, 0.98, aa)
			draw_line(Vector2(px - 6.0, yy), Vector2(px - 6.0 - sl, yy + 2.5), streak_col, 2.0 if GameState.boss_enraged else 1.5)

	# ③ 轮廓光 + 本体（狂暴态叠加前倾俯冲摇摆变换，拒绝死板平推）
	var tilt := (0.065 + 0.025 * sin(_anim_t * 14.0)) if enr_anim else 0.0
	if tilt != 0.0:
		draw_set_transform(Vector2(px + tw * 0.5, py + th), tilt, Vector2.ONE)
	var draw_px := -tw * 0.5 if tilt != 0.0 else px
	var draw_py := -th if tilt != 0.0 else py

	var rim_col := RIM_COLOR
	var rim_step := RIM_STEP
	if GameState.boss_enraged or _pose_stage >= 3:
		rim_col = Color(1.0, 0.16, 0.42, 0.72)
		rim_step = 2.2
	elif _pose_stage > 0:
		rim_col = Color(1.0, 0.34, 0.28, 0.42)
	for o in RIM_DIRS:
		draw_texture_rect(tex, Rect2(draw_px + o.x * rim_step, draw_py + o.y * rim_step, tw, th),
			false, rim_col)

	# ④ 本体（受击时短暂亮青闪白）
	var body_col := Color(1.45, 1.80, 2.0, 1.0) if _hit_flash_t > 0.0 else Color.WHITE
	draw_texture_rect(tex, Rect2(draw_px, draw_py, tw, th), false, body_col)
	if tilt != 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ⑤ 墨雾（前半）：**压在她身上**的那几团 —— 这一层才是缠绕的来源。
	#    只有画在身体之上、又半透明，才会读成雾绕着她，而不是她背后有团光。
	_draw_mist(Vector2(cx, cy), tw, th, true)


## 占位剪影（`USE_REAL_ART = false` 时用）。留着是为了能一键 A/B 真素材。
func _draw_placeholder() -> void:
	var wob := sin(_anim_t * 9.0) * 7.0
	var cy := 40.0 + wob
	var pts := PackedVector2Array([
		Vector2(x - 150.0, cy),
		Vector2(x - 90.0, cy - 66.0),
		Vector2(x - 10.0, cy - 74.0),
		Vector2(x - 6.0, cy + 70.0),
		Vector2(x - 100.0, cy + 60.0),
	])
	draw_colored_polygon(pts, Color(0.03, 0.05, 0.09, 0.96))
	draw_polyline(PackedVector2Array([pts[1], pts[2]]),
		Color(0.55, 0.75, 0.95, 0.7), 3.0)
	for i in 4:
		var a := 0.30 - float(i) * 0.07
		var off := float(i) * 46.0
		draw_rect(Rect2(x - 260.0 - off, cy - 34.0 + float(i) * 8.0, 120.0, 62.0),
			Color(0.03, 0.05, 0.09, a))
