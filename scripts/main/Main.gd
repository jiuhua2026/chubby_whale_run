extends Node2D
## Main —— 场景装配与主循环。
##
## 完整的节点树（大部分在代码里搭，原因见下方注释）：
##   Main (Node2D)
##   ├── Backdrop (Node2D)          视差背景，world 层
##   ├── Terrain (Node2D)           TerrainGenerator，生成 TerrainChunk
##   ├── Actors (Node2D)
##   │   ├── Player (CharacterBody2D)   z=2
##   │   ├── DashFx (Node2D)            冲刺残影 + 粒子（z=1；残影 0）
##   │   ├── DeathWall (Node2D)     常态压力
##   │   └── Chaser (Node2D)        高潮追兵
##   ├── ChaseDirector (Node)       两模式切换
##   ├── Camera2D
##   └── HUD (CanvasLayer)
##
## 为什么节点树用代码搭而不是 .tscn：
##   垂直切片阶段节点结构还在高频变动，代码搭改一行就生效；
##   而且代码创建不会出现手写 .tscn 语法错误导致整个工程打不开的情况。
##   Player 单独做成了 scenes/Player.tscn，因为它是最需要可视化调碰撞盒的节点。

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
## 玩家的世界起点。相机把玩家固定在屏幕左侧 30%，所以起点放在视野内即可。
const START_POS := Vector2(320.0, 0.0)
## 相机相对玩家脚底的纵向偏移（往上抬，让水平线落在画面下三分之一）
const CAMERA_Y_OFFSET := -210.0

var backdrop: Backdrop
var ambient_fx: AmbientSeaFx
var terrain: TerrainGenerator
var actors: Node2D
var player: Player
## 冲刺特效（残影 / 粒子）。挂在 Actors 下与 Player **同级**，见 _build() 里的说明。
var dash_fx: DashFx
var wall: DeathWall
var chaser: Chaser
var boss_proj: BossProjectile
var director: ChaseDirector
var cam: Camera2D
var hud: HUD
var menu: MainMenu
var intro: OpeningIntro
## 暂停面板（layer 150：压在 HUD 100 之上、主菜单 200 之下）
var pause_panel: PausePanel
var _toast: AchievementToast
## 像素溶解转场（layer 220：压在主菜单之上、开场动画之下）
var _transition: TransitionOverlay
## 取消暂停后短暂忽略 ESC 的剩余秒数。见 `_on_pause_resumed()`。
var _pause_ignore := 0.0

## 真·神庙式起跑追逐衔接计时（< 0 表示未在起跑过场中）：世界/地面实时推进，黑鲸娘实体猛冲扑咬后被甩出左画面边缘
const READY_DURATION := 1.25
var _ready_t := -1.0
var _ready_taunted := false
var _came_from_ready := false
## 自动化验收开关：`-- --intro-shot=SEC` / `-- --intro-shot-replay` / `-- --ready-shot`
var _intro_shot_t := -1.0
var _intro_shot_replay := false
var _ready_shot := false
var _bite_shot := false
var _wall_shot := false

var _prev_x := 0.0
## 冲刺抓帧：`-- --dashshot` 时在冲刺开始那一刻连抓 SHOT_FRAMES 帧，然后退出。
## 另一个等价开关是 `-- --shot-at=N`（第 N 个渲染帧开抓），用来看任意时刻的画面 ——
## 比如刚改完地形/障碍贴图，想看一眼实际长什么样。
## 存在的理由：这个项目的手感/特效调参一直是「无头验证 + 交给用户实机看」，
## 但无头模式拿不到画面 —— AI 自己看不到效果，就没法判断调好没调好。
## ⚠ 必须**不加 --headless** 运行（headless 下视口纹理是空的，存出来全黑）。
var _shot := false
var _shot_left := -1
var _shot_n := 0
## >= 0 时改用「第 N 帧」触发，而不是等冲刺
var _shot_from_frame := -1
## `-- --shot-over`：等「屏幕里真的有悬顶障碍」才开抓。
##
## 为什么需要它：`--shot-at=N` 是**盲猜帧号**，而悬顶出现在哪一列是随机的，
## 猜错就是抓一屏没有悬顶的图（第一次验证悬顶贴图时正是这样白跑一趟）。
## 这个触发器直接问地形数据「视野里有没有 OVERHEAD 列」，命中率 100%。
var _shot_over_only := false
## `-- --shot-low`：等「屏幕里真的有贴地矮障碍」才开抓。同上的理由 ——
## 矮障碍也是按世界列号轮换的，盲猜帧号经常抓到一屏没有障碍的图。
## 换尺寸/换素材后逐款验收：`-- --shot-low --low-variant=1`
var _shot_low_only := false
## `-- --shot-frag`：等「屏幕里真的有断桥段」才开抓（判据见 `_frag_on_screen`）。
## 验收"割裂感"必须用它 —— 断桥段出现在哪一段是随机的，
## 而"随便抓一帧"拍到的多半是实体段的普通凹陷，看图和没改一样。
var _shot_frag_only := false
## `-- --pause-shot`：跑到固定帧数时打开暂停面板并抓帧（验收面板排版/配色）。
## 只开面板、**不真的暂停树** —— 抓的是一张静止图，冻不冻世界对结果没影响。
var _pause_shot := false
var _pause_shot_settings := false
var _pause_shot_done := false
## `-- --pause-demo`：真暂停 0.6s，打印暂停前后的距离增量。
## 这是唯一能证明"世界真的停了"的自动验证 —— 画面看着不动可能是刚好没在动。
var _pause_demo := false
## `-- --restart-demo`：验证死亡后按 R 的防误触延迟（0.45s 咬击期间屏蔽）与重开走 Phase.READY。
var _restart_demo := false
## `-- --achievements-demo`：验证全部 6 张纪念画片、8 个成就触发、顶部 Toast 弹出、练习模式隔离与图鉴面板交互。
var _achievements_demo := false
var _phase1_demo := false
var _phase2_demo := false
var _shop_shot := false
var _pv_scene := ""
var _pv_dodge := false
var _pv_dodge_timer := 0.0
var _pv_parry_next := false
## 抓多少帧。要覆盖「冲刺全程 + 尾巴粒子飘完」：
## 冲刺 1.0s（60 帧）+ 尾迹最长寿命 0.46s ≈ 88 帧，取 80 够看完整段。
## 悬顶模式用得长得多：造型按「世界列号 mod 4」轮换（`TerrainChunk._variant_of`
## 的乘子 mod 4 = 1），一段悬顶只呈现一款，所以要看全 4 款就得跨过好几段 ——
## 420 帧 ≈ 7s ≈ 走 50 列，通常能覆盖 2~3 段。
const SHOT_FRAMES := 80
const SHOT_FRAMES_OVER := 420
## 矮障碍用不着那么长：它只有 1 列宽、玩家一步就跳过去了。
## 240 帧（4s，约 8 列）足够覆盖「进画面 → 起跳 → 越过 → 出画面」。
const SHOT_FRAMES_LOW := 240
## 断桥段要看完一整段：一段 2~3 块、约 70~110 列（= 4~7 屏），
## 450 帧（7.5s，约 45 列）能拍到"进入 → 连跳几次 → 走出这一段"。
const SHOT_FRAMES_FRAG := 450
## 无头冒烟自检：带 `-- --selftest` 启动时，每秒打印一次运行状态。
## 用途是「不开窗口也能确认生成器在出地形、边界在收网、追击在触发」，
## 适合挂到 CI 或改完地形规则后快速回归。
var _selftest := false
var _st_tick := 0
## `--chase-trace`：按帧打印黑鲸娘的透明度 / 缺口 / 追击状态。
##
## 验证"淡入 → 停留 → 淡出"这种**时序**行为只能靠它：
## 自检行每 2s 才打一次，而淡入只有 0.45s、淡出 0.75s —— 采样间隔比过程本身还长，
## 光看自检行会以为"透明度直接从 0 跳到 1"。
var _chase_trace := false
## 纯可解性模式：把死亡边界与追兵停掉，只验证「地形能不能靠跳/滑走完」
var _solvable_only := false
var autopilot: AutoPilot
## 追击暗角。强度平滑跟随 `Chaser.pressure()`（见 `ChaseVignette` 的注释）。
var _vig: ChaseVignette
var _vig_cur := 0.0
## 命中冲击的震动余量（1 → 0，约 0.25s）。
var _shake_kick := 0.0

## 掉到「世界地面（层高 0）以下多少像素」就判定为坠入断崖。
##
## 为什么用绝对阈值而不是"本地地面高度"：本作地形只有 `0 / 1 / 2` 三档层高，
## **最深的地板是层高 2 = 128px**。
## ⚠ 能不能站得住要按段落看（见 `TerrainChunk.broken`）：
##   · **实体段**：坑列有碰撞体 ⇒ 最深只到 128px，踩下去能爬出来，**不会触发这里**；
##   · **断桥段**：坑列没有碰撞体 ⇒ 掉进去会一直下坠，越过 150 就被判定坠崖。
## 取 150 = 128 + 22px 余量：既不会误判实体段的坑底/台阶，
## 又**几乎是掉下去就立刻结算**（下坠 150px 约 0.38s，够看见人掉进沟里，
## 又不会让人有"我还能救一下"的错觉）。
const FALL_KILL_DEPTH := 150.0


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	_selftest = user_args.has("--selftest") or user_args.has("--solvable") \
		or user_args.has("--testmode") or user_args.has("--practice")
	_solvable_only = user_args.has("--solvable")
	_shot = user_args.has("--dashshot")
	# --shot-at=N：第 N 个渲染帧开抓（看任意时刻的画面，比如地形里的障碍贴图）
	for a in user_args:
		if a.begins_with("--shot-at="):
			_shot = true
			_shot_from_frame = int(a.substr("--shot-at=".length()))
	_shot_over_only = user_args.has("--shot-over")
	if _shot_over_only:
		_shot = true
	_shot_low_only = user_args.has("--shot-low")
	if _shot_low_only:
		_shot = true
	# --chase-trace 也顺手把自检打开（它的计数器挂在自检上）
	# --nm-trace：逐次打印"过了擦身门，但为什么给/不给"（调擦身判定用）
	if user_args.has("--nm-trace"):
		NearMissGate.debug_trace = true
		_selftest = true
	# --bite-demo：把咬到判定放到很大 ⇒ 追击一开始就进"咬击"，用来验收那 4 帧素材。
	#   没有它的话自动驾驶几乎不会被真咬到（追击段只逼近 78px/s），素材改坏了看不出来。
	if user_args.has("--bite-demo"):
		Chaser.catch_margin = 900.0
		_selftest = true
	_bite_shot = user_args.has("--bite-shot")
	if _bite_shot:
		Chaser.catch_margin = 900.0
		_selftest = true
		_shot = true
	_wall_shot = user_args.has("--wall-shot")
	if _wall_shot:
		_selftest = true
		_shot = true
		_shot_from_frame = 25
	_chase_trace = user_args.has("--chase-trace")
	if _chase_trace:
		_selftest = true
	_shot_frag_only = user_args.has("--shot-frag")
	if _shot_frag_only:
		_shot = true
	# --pause-shot：跑到第 600 帧（约 100m，画面里有地形起伏）时开暂停面板再抓帧。
	# 复用 `--shot-at` 的帧号触发器：这里只负责"在它抓之前把面板打开"。
	_pause_shot = user_args.has("--pause-shot")
	# --pause-shot-settings：同上，但把设置面板也叠上来（验收三层叠加的观感）
	_pause_shot_settings = user_args.has("--pause-shot-settings")
	if _pause_shot_settings:
		_pause_shot = true
	if _pause_shot:
		_selftest = true          # 借自动驾驶把距离跑起来，别停在 0m
		_shot = true
		_shot_from_frame = 600
	# --pause-demo：真暂停 0.6s，验证世界被冻住
	_pause_demo = user_args.has("--pause-demo")
	if _pause_demo:
		_selftest = true
	_restart_demo = user_args.has("--restart-demo")
	_achievements_demo = user_args.has("--achievements-demo")
	_phase1_demo = user_args.has("--phase1-demo")
	_phase2_demo = user_args.has("--phase2-demo")
	_shop_shot = user_args.has("--shop-shot")
	if _shop_shot:
		_shot = true
		_shot_from_frame = 8
	if _selftest or _shot or _pause_demo or _restart_demo or _achievements_demo or _phase1_demo or _phase2_demo or _intro_shot_t >= 0.0:
		Settings.record_save_enabled = false
	# --over-variant=N / --low-variant=N：强制某一组障碍只用第 N 款造型
	# （逐款核对贴图用，见 TerrainChunk）
	for a in user_args:
		if a.begins_with("--over-variant="):
			TerrainChunk.debug_over_variant = int(a.substr("--over-variant=".length()))
		elif a.begins_with("--low-variant="):
			TerrainChunk.debug_low_variant = int(a.substr("--low-variant=".length()))
		elif a.begins_with("--intro-shot="):
			_intro_shot_t = float(a.substr("--intro-shot=".length()))
		elif a.begins_with("--pv-scene="):
			_pv_scene = a.substr("--pv-scene=".length())
	if _pv_scene != "":
		Settings.record_save_enabled = false
		Settings.intro_seen = true
	_intro_shot_replay = user_args.has("--intro-shot-replay")
	_ready_shot = user_args.has("--ready-shot")
	if _ready_shot:
		_shot = true
		_shot_from_frame = 3
	elif _intro_shot_t >= 0.0:
		_shot = true
		_shot_from_frame = 2

	_build()
	GameState.ready_started.connect(_on_ready_started)
	GameState.run_started.connect(_on_run_started)
	GameState.run_ended.connect(_on_run_ended)
	GameState.chase_started.connect(_on_chase_started)
	GameState.chase_ended.connect(_on_chase_ended)
	GameState.boss_enraged_started.connect(_on_boss_enraged)
	GameState.menu_opened.connect(_on_menu_opened)
	menu.mode_chosen.connect(_on_mode_chosen)
	menu.replay_intro_requested.connect(_on_replay_intro_requested)
	hud.shop_requested.connect(_on_end_shop_requested)
	intro.reveal_ready.connect(_on_intro_reveal_ready)
	intro.finished.connect(_on_intro_finished)

	if _selftest:
		# 无头自检跳过主界面，直接开跑。--testmode 用来验证测试模式。
		# 自检的入口模式：`--testmode` = 沙盒，`--practice` = 练习，都不给 = 正常
		var m := GameState.Mode.NORMAL
		if user_args.has("--testmode"):
			m = GameState.Mode.TEST
		elif user_args.has("--practice"):
			m = GameState.Mode.PRACTICE
		GameState.start_run(m)
		# `-- --ladder` 只打一次档位体检就够。用它可以在不开窗口的情况下
		# 确认 run_cycle_px 有没有让速度区间跨越档位边界（那会造成可见的换档跳变）。
		if user_args.has("--ladder"):
			Callable(self, "_report_anim_ladder").call_deferred()
	else:
		# 启动进主界面。先把场景摆好当作背景：平坦地面 + 角色原地跑
		terrain.flat_only = true
		terrain.reset()
		player.reset(START_POS)
		wall.reset(player.global_position.x)
		wall.active = false
		_snap_camera()

		if _ready_shot:
			_on_mode_chosen(GameState.Mode.NORMAL)
		elif _intro_shot_t >= 0.0:
			menu.set_intro_blocking(true)
			intro.seek_for_capture(_intro_shot_t, _intro_shot_replay)
			if _intro_shot_t >= OpeningIntro.T_HANDOFF:
				menu.reveal_ui(0.0, clampf((_intro_shot_t - OpeningIntro.T_HANDOFF) / 0.45, 0.0, 1.0))
		elif not _shot and not _pause_demo and not _restart_demo and not _achievements_demo and not _phase1_demo and not _phase2_demo \
				and _pv_scene == "" \
				and not user_args.has("--settings") \
				and not user_args.has("--wardrobe") \
				and not user_args.has("--shop") \
				and not user_args.has("--achievements") and not Settings.intro_seen:
			menu.set_intro_blocking(true)
			intro.play(false)
		else:
			AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.0)
			AudioManager.play_bgm("menu", 0.6)
			if _shop_shot:
				Callable(self, "_prepare_shop_shot").call_deferred()

	if _pv_scene != "":
		Callable(self, "_run_pv_scene").call_deferred()

	if _pause_demo:
		Callable(self, "_run_pause_demo").call_deferred()
	if _restart_demo:
		Callable(self, "_run_restart_demo").call_deferred()
	if _achievements_demo:
		Callable(self, "_run_achievements_demo").call_deferred()
	if _phase1_demo:
		Callable(self, "_run_phase1_demo").call_deferred()
	if _phase2_demo:
		Callable(self, "_run_phase2_demo").call_deferred()


func _on_mode_chosen(p_mode: int) -> void:
	if (p_mode == GameState.Mode.NORMAL or p_mode == GameState.Mode.HARD) and not _selftest and (not _shot or _ready_shot):
		GameState.begin_ready(p_mode)
	else:
		GameState.start_run(p_mode)


func _on_replay_intro_requested() -> void:
	Settings.intro_replay_count += 1
	Settings.save_cfg()
	AudioManager.stop_bgm(0.25)
	menu.set_intro_blocking(true)
	intro.play(true)


func _on_intro_reveal_ready() -> void:
	AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.0)
	AudioManager.play_bgm("menu", 0.8)
	menu.reveal_ui(0.45)


func _on_intro_finished() -> void:
	menu.set_intro_blocking(false)


func _clear_dynamic_actors() -> void:
	if boss_proj != null:
		boss_proj.reset()
	if actors != null:
		for c in actors.get_children():
			if c is PlantPickup:
				c.queue_free()


func _on_menu_opened() -> void:
	_ready_t = -1.0
	_came_from_ready = false
	chaser.snap_hidden()
	_clear_dynamic_actors()
	AudioManager.stop_sfx()
	AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.35)
	if intro == null or not intro.is_playing():
		AudioManager.play_bgm("menu", 0.7)
	cam.offset = Vector2.ZERO
	terrain.flat_only = true
	terrain.reset()
	player.reset(START_POS)
	wall.reset(player.global_position.x)
	wall.active = false
	_snap_camera()


func _on_run_ended(_reason: String, _distance: float, _score: int) -> void:
	AudioManager.set_bgm_muffled(true, -7.0, 580.0, 0.45)
	if _selftest:
		print("[selftest] 本局结束：原因=%s 距离=%.0fm 得分=%d　|　%s"
			% [_reason, _distance / 64.0, _score, autopilot.report()])


func _on_chase_started(_index: int) -> void:
	AudioManager.play_sfx("chase_warning", 1.0)
	AudioManager.play_bgm("chase", 0.45)


func _on_boss_enraged() -> void:
	_shake_kick = 1.35
	AudioManager.play_bgm("chase", 0.25)


func _on_chase_ended(_index: int) -> void:
	if GameState.is_running():
		AudioManager.play_bgm("run", 0.9)


func _build() -> void:
	_make_gradient_background()

	backdrop = Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)

	ambient_fx = AmbientSeaFx.new()
	ambient_fx.name = "AmbientSeaFx"
	add_child(ambient_fx)

	terrain = TerrainGenerator.new()
	terrain.name = "Terrain"
	add_child(terrain)

	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)

	player = PLAYER_SCENE.instantiate()
	player.name = "Player"
	actors.add_child(player)

	# 冲刺特效必须和 Player **同级**，不能挂成它的子节点：
	# 玩家在世界里真前进，挂在下面的话特效会跟着一起走，只会"贴在身上"，
	# 拖不出尾巴。挂在这里，粒子按世界坐标发射、残影留在原地，才有速度感。
	# z 序由各自的 z_index 决定（残影 0 / 粒子 1 / 玩家 2），与添加顺序无关。
	dash_fx = DashFx.new()
	dash_fx.name = "DashFx"
	actors.add_child(dash_fx)
	dash_fx.setup(player)
	player.dash_fx = dash_fx

	wall = DeathWall.new()
	wall.name = "DeathWall"
	actors.add_child(wall)

	chaser = Chaser.new()
	chaser.name = "Chaser"
	actors.add_child(chaser)

	boss_proj = BossProjectile.new()
	boss_proj.name = "BossProjectile"
	actors.add_child(boss_proj)

	director = ChaseDirector.new()
	director.name = "ChaseDirector"
	add_child(director)

	cam = Camera2D.new()
	cam.name = "Camera"
	cam.position_smoothing_enabled = false
	add_child(cam)

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)

	menu = MainMenu.new()
	menu.name = "MainMenu"
	add_child(menu)          # layer 200，压在 HUD 之上

	_toast = AchievementToast.new()
	_toast.name = "AchievementToast"
	add_child(_toast)        # layer 210，成就解锁顶部轻提示

	intro = OpeningIntro.new()
	intro.name = "OpeningIntro"
	add_child(intro)         # layer 250，盖在主菜单之上演出，落幕无缝融合进菜单

	_transition = TransitionOverlay.new()
	_transition.name = "TransitionOverlay"
	add_child(_transition)   # layer 220，死亡按 R 重开与返回主菜单的像素溶解转场

	# 暂停层：150 —— 压在 HUD(100) 之上、主菜单(200) 之下。
	# 面板自己在 `_ready()` 里设 `process_mode = ALWAYS`（树暂停后它还得收输入），
	# 这里不要替它设，免得两处不一致时看不出是谁在生效。
	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseLayer"
	pause_layer.layer = 150
	add_child(pause_layer)
	pause_panel = PausePanel.new()
	pause_panel.name = "PausePanel"
	pause_layer.add_child(pause_panel)
	pause_panel.resumed.connect(_on_pause_resumed)
	pause_panel.menu_requested.connect(_on_pause_menu)

	# 屏幕边缘：单独一层，压在世界之上、HUD 之下
	var vig_layer := CanvasLayer.new()
	vig_layer.layer = 10
	add_child(vig_layer)
	# 恒定的上缘渐隐（背景纹理的上边界露出来过，见 `ScreenFrame` 的注释）
	var frame := ScreenFrame.new()
	vig_layer.add_child(frame)
	_vig = ChaseVignette.new()
	vig_layer.add_child(_vig)

	wall.setup(player)
	chaser.setup(player)
	boss_proj.setup(player, terrain, actors)
	# 撞到障碍 ⇒ 屏震一下（"失误有代价"的可感知形式）
	player.hit_taken.connect(_on_player_hit_shake)
	director.setup(wall, chaser, terrain, player, boss_proj)

	autopilot = AutoPilot.new()
	autopilot.setup(player, terrain)
	# 两种自检模式下都启用自动驾驶：
	#   --selftest  → 开机 + 开边界，验证整局循环
	#   --solvable  → 只开自动驾驶、关掉一切致命判定，纯验地形可解性
	autopilot.enabled = _selftest
	if _solvable_only:
		wall.active = false


## 最底层的全屏水体渐变。用 CanvasLayer 保证它完全不受相机影响。
func _on_player_hit_shake(_kind: String) -> void:
	_shake_kick = 1.0


func _make_gradient_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GradientBG"
	layer.layer = -100
	var grad := Gradient.new()
	# ⚠ 2026-10-18 压暗：原来 0.04/0.11/0.20 和远景剪影（0.045/0.095/0.155）几乎同色
	#   ⇒ 背景层再画也看不出来。压到这里之后，远层/近层/地形板才有可读的亮度阶梯。
	grad.set_color(0, Color(0.028, 0.072, 0.135))
	grad.set_color(1, Color(0.006, 0.016, 0.030))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4
	tex.height = 256
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(tr)
	add_child(layer)


func _on_ready_started() -> void:
	_ready_t = 0.0
	_ready_taunted = false
	_came_from_ready = false
	terrain.flat_only = false
	Difficulty.speed_override = -1.0
	terrain.reset()
	# 蓝鲸娘从正常起点 START_POS 起直接加速向前奔跑（地面/镜头同步移动，零原地滑步感）
	player.reset(START_POS)
	player.speed = 320.0
	wall.reset(START_POS.x)
	wall.active = false
	_clear_dynamic_actors()
	director.reset()
	autopilot.reset()
	AudioManager.stop_sfx()
	AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.25)
	AudioManager.play_bgm("run", 0.55)
	_prev_x = START_POS.x
	_shake_kick = 0.0
	_vig_cur = 0.0
	_vig.strength = 0.0
	cam.offset = Vector2.ZERO
	_snap_camera()
	# 黑鲸娘带着完整墨雾从左侧水幕边缘动态冲进画面追近
	chaser.begin_cameo(START_POS.x - 290.0)


func _on_run_started() -> void:
	# 只有**沙盒**才改地形/关边界/锁速度；练习模式必须和正常模式一模一样。
	var sandbox := GameState.is_sandbox()

	if _came_from_ready:
		_came_from_ready = false
		wall.reset(player.global_position.x)
		wall.active = not sandbox
		chaser.snap_hidden()
		cam.offset = Vector2.ZERO
		_prev_x = player.global_position.x
		AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.2)
		return

	_ready_t = -1.0
	# 沙盒：平坦地面、关掉死亡边界，速度固定住方便观察
	terrain.flat_only = sandbox
	Difficulty.speed_override = GameConfig.test_speed_default if sandbox else -1.0

	player.reset(START_POS)
	terrain.reset()
	wall.reset(player.global_position.x)
	if _wall_shot:
		wall.x = player.global_position.x - 160.0
	wall.active = not sandbox
	# ⚠ 这里必须是**硬隐藏**（`snap_hidden`）而不是 `end()`：`end()` 现在是"淡出"，
	# 新一局开始的瞬间要干净，不能看到上一局残留的淡出尾巴。
	chaser.snap_hidden()
	_clear_dynamic_actors()
	director.reset()
	autopilot.reset()
	AudioManager.stop_sfx()
	AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.25)
	AudioManager.play_bgm("run", 0.5)
	_prev_x = player.global_position.x
	_shake_kick = 0.0
	cam.offset = Vector2.ZERO
	_snap_camera()


func _update_ready(delta: float) -> void:
	# 夹住单帧长卡顿（如首帧着色器编译），保证玩家不会漏掉扑咬高潮
	var dt := minf(delta, 0.05)
	_ready_t += dt

	# 1. 蓝鲸娘真实沿跑道推进：起步加速 → 甩开爆发（0.40~0.80s）→ 平顺贴合正常起跑速 470
	var cur_speed: float
	if _ready_t < 0.40:
		var s := clampf(_ready_t / 0.40, 0.0, 1.0)
		s = s * s * (3.0 - 2.0 * s)
		cur_speed = lerpf(320.0, 500.0, s)
	elif _ready_t < 0.80:
		var burst := sin((_ready_t - 0.40) / 0.40 * PI)
		cur_speed = 500.0 + 55.0 * burst
	else:
		var s2 := clampf((_ready_t - 0.80) / (READY_DURATION - 0.80), 0.0, 1.0)
		s2 = s2 * s2 * (3.0 - 2.0 * s2)
		cur_speed = lerpf(500.0, GameConfig.run_speed_start, s2)

	player.speed = cur_speed
	player.velocity = Vector2(cur_speed, 60.0)
	player.move_and_slide()

	var dx := player.global_position.x - _prev_x
	_prev_x = player.global_position.x
	GameState.add_distance(maxf(dx, 0.0))
	terrain.update_for(player.global_position.x)

	# 2. 黑鲸娘始终「向前游动追赶」（绝不倒退走路）：
	#    · 0.00..0.42s：疾冲逼近至贴身间距 ~142px；在 0.22s 张嘴咆哮咬击示威
	#    · 0.42..1.25s：蓝鲸娘甩开爆发，黑鲸娘前速降至 125px/s 被真实卷出画面左侧
	var chaser_v: float
	if _ready_t < 0.42:
		var lp := _ready_t / 0.42
		chaser_v = cur_speed + 700.0 * (1.0 - lp)
	else:
		var dp := clampf((_ready_t - 0.42) / 0.36, 0.0, 1.0)
		dp = dp * dp * (3.0 - 2.0 * dp)
		chaser_v = lerpf(cur_speed, 125.0, dp)

	var new_cx := chaser.x + chaser_v * dt
	if not _ready_taunted and _ready_t >= 0.22:
		_ready_taunted = true
		chaser.trigger_cameo_taunt(0.34)
		AudioManager.play_sfx("chase_warning", 1.0)
		_shake_kick = 0.48

	var c_gap := player.global_position.x - new_cx
	var vw := get_viewport_rect().size.x
	var left_edge := player.global_position.x - GameConfig.camera_player_screen_ratio * vw
	# 保持不透明直到真正贴出左侧边界或收尾 0.22s，绝不原地蒸发
	var fade_tgt := 0.0 if (new_cx < left_edge - 20.0 or _ready_t >= READY_DURATION - 0.22) else 1.0
	chaser.step_cameo(dt, new_cx, fade_tgt, 4.2, c_gap < 390.0)

	# 3. 相机与 HUD 距离完全同步（起跑过场不叠加四周暗角压迫，保持海底开阔透亮）
	_update_camera(dt)
	hud.update_live(player, director)

	if _ready_t >= READY_DURATION:
		_ready_t = -1.0
		_came_from_ready = true
		player.speed = GameConfig.run_speed_start
		player.velocity = Vector2(GameConfig.run_speed_start, 0.0)
		_vig_cur = 0.0
		_vig.strength = 0.0
		cam.offset = Vector2.ZERO
		chaser.snap_hidden()
		GameState.commit_ready()


# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if GameState.is_ready_phase():
		_update_ready(delta)
		if _shot:
			_update_shot()
		return
	if not GameState.is_running():
		# ⚠ 死后仍要推进抓帧：**"被咬到"那一下正是最该看的画面**，
		#   而咬击是在世界冻结之后才播的（见 `Chaser._start_bite`），
		#   原来这里直接 return ⇒ 抓帧永远不会在死后的那 0.4s 里发生。
		#   只在开了 `--shot*` 时做，正常运行不付这份成本。
		if _shot:
			_update_shot()
		return

	# 距离以玩家真实位移为准，而不是用速度乘时间——
	# 后者会和物理求解的结果慢慢漂移，导致分数和画面对不上。
	var dx := player.global_position.x - _prev_x
	_prev_x = player.global_position.x
	GameState.add_distance(maxf(dx, 0.0))

	if _selftest or _pv_scene != "":
		autopilot.tick(delta)
	if _pv_dodge:
		_pv_tick_proj_dodge(delta)

	terrain.update_for(player.global_position.x)

	_update_fall(delta)

	# 模式分流（放在主控统一拦截，模块不该知道自己跑在哪种模式里）：
	#   沙盒  —— 边界、追兵、追击调度**全部不跑**（平地观察）
	#   练习  —— **边界照跑**（掉坑/落后照样死），只不跑追兵与追击调度
	#   正常  —— 全跑
	if not GameState.is_sandbox():
		wall.update(delta)
		if not GameState.is_practice():
			chaser.update(delta)
			if not _solvable_only:
				boss_proj.update(delta)
				director.update(delta)

	# 暗角强度：目标 = 她的贴近程度，按帧平滑逼近（追击结束/开始都不会硬切）
	_vig_cur = move_toward(_vig_cur,
		chaser.pressure() * GameConfig.chase_vignette_max, 2.5 * delta)
	_vig.strength = _vig_cur

	_update_camera(delta)
	hud.update_live(player, director)
	# --pause-shot：提前 3 帧把面板打开，之后由 `--shot-at` 的帧号触发抓帧。
	# 早几帧是为了让 `_fit()` 的 `call_deferred` 和首帧布局都跑完再拍。
	if _pause_shot and not _pause_shot_done \
			and Engine.get_process_frames() >= _shot_from_frame - 3:
		_pause_shot_done = true
		pause_panel.open(GameState.distance, GameState.score)
		if _pause_shot_settings:
			pause_panel.debug_open_settings()
	_update_shot()

	if _solvable_only:
		# 纯可解性模式：掐掉一切死亡来源，只验地形能不能走完。
		# 边界推到三千米外，追兵与追击调度全部停摆。
		wall.x = player.global_position.x - 3000.0
		chaser.end()
		director.in_chase = false

	if _selftest:
		_st_tick += 1
		if _chase_trace and _st_tick % 6 == 0:
			print("[chase] t=%.2f 追击=%s 透明度=%.3f 缺口=%.0f"
				% [_st_tick / 60.0, "是" if director.in_chase else "否",
					chaser.opacity(), chaser.gap()])
		if _st_tick % 120 == 0:
			print("[selftest] t=%.1fs 距离=%.0fm 速度=%.0f 动画=%s@%.0f→%.0ffps 边界间距=%.0f 块=%d 列=%d 追击=%s 黑鲸娘=%.2f 状态=%d 势能=%d/%d 冲刺=%d%s 特效=%d/%d %s"
				% [_st_tick / 60.0, GameState.distance / 64.0, player.speed,
					player.debug_anim_action(), player.debug_anim_fps_raw(),
					player.debug_anim_fps(),
					wall.gap(), terrain.chunk_count(), terrain.total_cols_generated(),
					"是" if director.in_chase else "否", chaser.opacity(), player.state,
					player.dash_charge, GameConfig.dash_charge_max, player.dash_count,
					"*" if player.is_dashing() else "",
					dash_fx.particle_count(), dash_fx.ghost_count(),
					autopilot.report()])
		# 每分钟打一次地形使用分布。某个模式长期为 0 说明它的准入条件永远满足不了，
	# 是调地形规则时最容易漏掉的问题（写了的模式其实从没出现过）。
		if _st_tick % 3600 == 0:
			print("[terrain] 使用分布：", terrain.usage_stats)
			print("[terrain] 拒绝统计：", terrain.reject_stats)
			print("[terrain] 首次拒绝原因：", terrain.reject_reasons)


func _process(delta: float) -> void:
	if _pause_ignore > 0.0:
		_pause_ignore = maxf(0.0, _pause_ignore - delta)
	backdrop.follow(cam.position.x, cam.position.y)
	ambient_fx.follow(cam.position.x, cam.position.y)


## 冲刺抓帧（只有在 `-- --dashshot` 时有动作，见 _shot 的注释）。
## 等到第一次冲刺发生那一刻开始，连抓 SHOT_FRAMES 帧（覆盖完整的冲刺 + 尾巴）。
##
## 注意第 1 张会晚一帧：`_process` 里读到的视口纹理是**上一帧**的画面。
## 所以第 1 张其实是"冲刺前一帧" —— 正好可以当对照，不改。
func _update_shot() -> void:
	if not _shot:
		return
	if _shot_left < 0:
		var trig := false
		if _bite_shot:
			trig = chaser.is_biting()
		elif _shot_over_only:
			trig = _hazard_on_screen(TerrainPatterns.OVERHEAD)
		elif _shot_low_only:
			trig = _hazard_on_screen(TerrainPatterns.LOW)
		elif _shot_frag_only:
			trig = _frag_on_screen()
		elif _shot_from_frame >= 0:
			trig = Engine.get_process_frames() >= _shot_from_frame
		else:
			trig = player.is_dashing() and GameState.is_running()
		if trig:
			if _intro_shot_t >= 0.0 or _shop_shot:
				_shot_left = 1
			elif _ready_shot:
				_shot_left = 90
			elif _bite_shot:
				_shot_left = 40
			elif _shot_over_only:
				_shot_left = SHOT_FRAMES_OVER
			elif _shot_low_only:
				_shot_left = SHOT_FRAMES_LOW
			elif _shot_frag_only:
				_shot_left = SHOT_FRAMES_FRAG
			else:
				_shot_left = SHOT_FRAMES
			_shot_n = 0
			# 输出目录可能不存在（tools/_preview 下没这个文件夹），自己建
			var d := ProjectSettings.globalize_path("res://tools/_preview/_shot")
			if not DirAccess.dir_exists_absolute(d):
				DirAccess.make_dir_recursive_absolute(d)
		return
	_shot_left -= 1
	_shot_n += 1
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://tools/_preview/_shot")
	img.save_png("%s/%02d.png" % [dir, _shot_n])
	if _shot_left == 0:
		print("[shot] 已抓 %d 帧 → tools/_preview/_shot/" % _shot_n)
		get_tree().quit()


## 视野里是否已经出现指定类型的障碍（`-- --shot-over` / `-- --shot-low` 的触发条件）。
##
## 用 `TerrainGenerator.sample()` 直接读地形数据，不去问渲染层 ——
## 判据必须和「地形生成器真的排了一段这种障碍」严格一致，否则会漏抓或空抓。
##
## 触发区间取「屏幕右侧 60%」：相机把玩家钉在屏幕 30% 处，
## 所以左边缘 = px − 0.3·vw、右边缘 = px + 0.7·vw。
## 从 px + 0.10·vw 开始扫，是为了让障碍还有一段距离要走完 ——
## 抓帧窗口足够看完它从右边走到左边并被越过。
func _hazard_on_screen(want: int) -> bool:
	if not GameState.is_running() or player.is_dashing():
		return false
	var vw := get_viewport_rect().size.x
	var px := player.global_position.x
	var c0 := int(floor((px + 0.10 * vw) / float(GameConfig.TILE)))
	var cols := int((0.60 * vw) / float(GameConfig.TILE))
	for d in terrain.sample(float(c0) * float(GameConfig.TILE), cols):
		if int(d["hazard"]) == want:
			return true
	return false


## 视野里是否已经出现「断桥段」的地面（`-- --shot-frag` 的触发条件）。
##
## 判据用**坑列占比**而不是「有没有坑」：割裂感是"地面被挖掉多大比例"的观感，
## 单列坑到处都是（实体段的点缀起伏也是坑），随便抓一帧只能拍到普通凹陷。
## 要求前方 20 列里有 ≥ 8 列是坑，拍到的一定是"一串分开的台子"。
##
## 同 `_hazard_on_screen` 的理由：**不要靠猜帧号**（`--shot-at`）。
## 断桥段出现在哪一段是随机的，猜帧号经常抓到一屏平地。
func _frag_on_screen() -> bool:
	if not GameState.is_running() or player.is_dashing():
		return false
	var vw := get_viewport_rect().size.x
	var px := player.global_position.x
	var c0 := int(floor((px + 0.10 * vw) / float(GameConfig.TILE)))
	var cols := int((0.60 * vw) / float(GameConfig.TILE))
	var pits := 0
	var seen := 0
	for d in terrain.sample(float(c0) * float(GameConfig.TILE), cols):
		seen += 1
		if int(d["level"]) > 0:
			pits += 1
	return seen > 0 and float(pits) / float(seen) >= 0.40


## 坠崖判定与（可解性模式下的）救援。每帧在 `terrain.update_for()` 之后调用。
##
## **为什么必须有这个函数**：坑列不再有碰撞体（见 `TerrainChunk._build()`），
## 所以"掉进断崖"是一个**会一直往下掉**的状态，必须有东西收网 ——
## 否则玩家掉出世界、相机跟着往下、地形也不再前进，整个游戏静默卡死。
##
## 两种模式处理不同：
##   · 正常 / 测试模式 → `player.kill("fell_into_chasm")`，本局结束（断崖是致命地形）；
##   · `--solvable`（掐掉一切死亡的纯地形验证）→ **把玩家捞回前方最近的实地**，
##     并计入 `autopilot.pit_falls`。不捞的话可解性测试会一头栽进第一个坑、再也没动静。
func _update_fall(delta: float) -> void:
	if player == null or not player.alive:
		return
	if player.global_position.y <= FALL_KILL_DEPTH:
		return

	if autopilot != null:
		autopilot.note_chasm_fall()
	_dump_fall_context()

	if not _solvable_only:
		AudioManager.play_sfx("fall", 1.0)
		player.kill("fell_into_chasm")
		return

	# 救援：往前找最近一块层高 0 的实地，把玩家放上去、清掉速度。
	# 用 `terrain.sample()` / `level_at_world()` 读地形数据（不去问碰撞层）——
	# 判据必须和生成器的实际输出一致，否则会救到一块不存在的地面上。
	var tile := float(GameConfig.TILE)
	var c0 := int(floor(player.global_position.x / tile))
	for d in 40:
		var c := c0 + d
		var lv := terrain.level_at_world(float(c) * tile + tile * 0.5)
		if lv > TerrainGenerator.LEVEL_UNLOADED and lv <= 0:
			player.global_position = Vector2(float(c) * tile + tile * 0.5, float(lv) * tile)
			player.velocity = Vector2.ZERO
			player.state = Player.St.RUN
			player._set_stand_shape()
			# 复位位移基准：救援把玩家往前挪了最多 40 列，不重置的话
			# 下一帧的 `dx` 会把这段位移算成"跑过的距离"，距离与分数会跳一大截。
			_prev_x = player.global_position.x
			return
	push_warning("坠崖救援失败：前方 40 列内没有有效落点")


## 坠崖现场的诊断快照（和 `AutoPilot` 的撞击回放同一个思路）。
##
## 为什么必须有：`掉坑 N` 只告诉你"发生了多少次"，看不出**是哪一种地形害的** ——
## 是坑太宽跳不过去、还是坑后面平台太短没落住、还是被上一个动作卡住起跳不了。
## 这三种的修法完全不同，靠猜会改错地方（实测猜错过一次）。
func _dump_fall_context() -> void:
	var tile := float(GameConfig.TILE)
	var k := int(floor(player.global_position.x / tile))
	var hs := ""
	for d in range(-6, 18):
		var lv := terrain.level_at_world(float(k + d) * tile + tile * 0.5)
		if lv <= TerrainGenerator.LEVEL_UNLOADED:
			hs += "?"
		elif lv == -1:
			hs += "a"
		elif lv <= -2:
			hs += "b"
		else:
			hs += str(clampi(lv, 0, 9))
	var ring: Array = autopilot.recent(3) if autopilot != null else []
	print("[fall] 坠崖！中心列=%d 玩家x=%.0f y=%.0f 速度=%.0f 版本=%s\n  h[%d..%d]=%s\n  最近帧：%s"
		% [k, player.global_position.x, player.global_position.y, player.speed,
			"solvable(已救援)" if _solvable_only else "normal(判死)",
			k - 6, k + 17, hs, str(ring)])


func _update_camera(delta: float) -> void:
	var vw := get_viewport_rect().size.x
	var target_x := player.global_position.x \
		+ vw * (0.5 - GameConfig.camera_player_screen_ratio)
	cam.position.x = target_x
	var target_y := player.global_position.y + CAMERA_Y_OFFSET
	cam.position.y = lerpf(cam.position.y, target_y,
		clampf(GameConfig.camera_y_smooth * delta, 0.0, 1.0))
	# 震动 = 追击项（∝ pressure³）+ 命中冲击项。
	#   · 三次方 ⇒ 她还在远处时几乎不抖、最后 1 秒明显（平方时 2.4px 实测感觉不到）
	#   · 命中冲击：撞一下给 8px 再快速衰减，是"失误有代价"最直接的可感知形式
	# ⚠ 用 `cam.offset` 而不是 `cam.position`：position 是 y 方向 lerp 的基准，
	#   往上叠位移会被下一帧当成"上一帧位置"继续追 ⇒ 震幅会累积成漂移。
	_shake_kick = move_toward(_shake_kick, 0.0, 4.5 * delta)
	var p := chaser.pressure()
	# 乘 `Settings.shake_scale`：设计值留在 GameConfig 里不动，
	# 玩家设置的"关/50%/100%"只是倍率（0 时整块震动彻底消失）
	var amp := (p * p * p * GameConfig.chase_shake_px \
		+ _shake_kick * GameConfig.hit_shake_px) * Settings.shake_scale
	if amp > 0.05:
		cam.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO


func _snap_camera() -> void:
	var vw := get_viewport_rect().size.x
	cam.position = Vector2(
		player.global_position.x + vw * (0.5 - GameConfig.camera_player_screen_ratio),
		player.global_position.y + CAMERA_Y_OFFSET)
	backdrop.follow(cam.position.x, cam.position.y)
	ambient_fx.follow(cam.position.x, cam.position.y)


# ---------------------------------------------------------------- 暂停
## 暂停一局。**用 `get_tree().paused`，而不是给 GameState 加一个 PAUSED 相位**：
## 该停的东西散在 `Player` 的动画 tick、`DashFx` 的残影发射、黑鲸娘的双正弦浮动里，
## 它们都不归 `is_running()` 管；加相位得逐个补门控，漏一个就是"世界半冻结"
## （人还在原地跑、残影还在往外吐）。`paused` 一行停掉整棵树（含 Tween / 粒子）。
func _pause_game() -> void:
	if get_tree().paused:
		return
	# ⚠ 屏震是往 `cam.offset` 叠随机值（见 `_update_camera`）。暂停后它不再重算，
	#   **那个随机偏移会永久定格** ⇒ 整幅世界歪着不动，要等恢复才自己归位。
	#   所以暂停这一帧必须显式清零。
	cam.offset = Vector2.ZERO
	AudioManager.set_bgm_muffled(true, -5.0, 650.0, 0.2)
	pause_panel.open(GameState.distance, GameState.score)
	get_tree().paused = true


func _on_pause_resumed() -> void:
	AudioManager.set_bgm_muffled(false, 0.0, 20500.0, 0.2)
	get_tree().paused = false
	# 取消暂停后节点立刻又能收事件，同一次 ESC 有可能再被喂到这里 ⇒
	# 变成"刚继续就立刻又暂停"。面板已经 `set_input_as_handled()`，这里再挡一下兜底。
	_pause_ignore = 0.2


func _on_pause_menu() -> void:
	get_tree().paused = false
	_pause_ignore = 0.2
	_run_transition(func() -> void: GameState.to_menu())


func _run_transition(action: Callable) -> void:
	if _transition == null or _selftest or _restart_demo or _pause_demo or _shot:
		action.call()
		return
	_transition.play_dissolve(action)


## `-- --pause-demo`：真暂停 0.6s，打印暂停前后的距离增量。
## ⚠ 暂停后 `Main._physics_process` 不再跑，所以这里的等待必须用
##   `create_timer(秒, true)`（process_always）——普通 Timer 会被一起冻住，永远不超时。
func _run_pause_demo() -> void:
	await get_tree().create_timer(2.0, true).timeout
	var d0 := GameState.distance
	_pause_game()
	print("[pause] 已暂停 paused=%s 距离=%.0fm" % [get_tree().paused, d0 / 64.0])
	await get_tree().create_timer(0.6, true).timeout
	var d1 := GameState.distance
	print("[pause] 停 0.6s 后距离=%.0fm 增量=%.1fpx（必须 0）" % [d1 / 64.0, d1 - d0])
	# 用**真实按键事件**走一遍 ESC，验证两件事：
	#   1. 暂停时面板确实能收到输入（`process_mode = ALWAYS` 生效，否则按 ESC 会毫无反应）；
	#   2. 恢复后同一次事件不会又把游戏暂停回去（`_pause_ignore` + `set_input_as_handled()`）。
	_send_key(KEY_ESCAPE, true)
	await get_tree().create_timer(0.2, true).timeout
	print("[pause] 注入 ESC 后 paused=%s（必须 false）" % get_tree().paused)
	_send_key(KEY_ESCAPE, false)
	await get_tree().create_timer(0.5, true).timeout
	print("[pause] 恢复 0.5s 后距离=%.0fm 增量=%.1fpx（必须 > 0）"
		% [GameState.distance / 64.0, GameState.distance - d1])

	# ① 设置入口：下移一格 → 回车 ⇒ 设置面板盖上来，但**游戏必须还停着**
	_pause_game()
	await get_tree().create_timer(0.2, true).timeout
	_tap(KEY_DOWN)
	await get_tree().create_timer(0.1, true).timeout
	_tap(KEY_ENTER)
	await get_tree().create_timer(0.2, true).timeout
	print("[pause] 打开设置后 设置可见=%s paused=%s（必须 true / true）"
		% [pause_panel.settings_visible(), get_tree().paused])
	# ② ESC 关设置 ⇒ 必须回到暂停，**不能连游戏一起继续**（一次按键退两层）
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.2, true).timeout
	print("[pause] 关设置后 设置可见=%s paused=%s（必须 false / true）"
		% [pause_panel.settings_visible(), get_tree().paused])
	# ③ 再按一次 ESC 才是继续
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.2, true).timeout
	print("[pause] 再 ESC 后 paused=%s（必须 false）" % get_tree().paused)

	# ④ 返回主菜单：暂停 → 下移两格（继续 → 设置 → 返回主菜单）→ 回车。
	#    这条最容易漏的是**恢复 paused** —— 漏了就是"菜单出来了但整棵树还是冻的"，
	#    人站在菜单前面什么都按不动。
	await get_tree().create_timer(0.3, true).timeout     # 等 `_pause_ignore` 过期
	_pause_game()
	await get_tree().create_timer(0.2, true).timeout
	_tap(KEY_DOWN)
	_tap(KEY_DOWN)
	await get_tree().create_timer(0.1, true).timeout
	_tap(KEY_ENTER)
	await get_tree().create_timer(0.3, true).timeout
	print("[pause] 选「返回主菜单」后 paused=%s 在菜单=%s（必须 false / true）"
		% [get_tree().paused, GameState.is_menu()])
	var ok := (not get_tree().paused) and GameState.is_menu()

	# ⑤ 起跑过场 Phase.READY 期间真实按 ESC：必须进入暂停，不能直接跳主界面；恢复后能完成交接
	await get_tree().create_timer(0.25, true).timeout    # 等 `_pause_ignore` 过期
	GameState.begin_ready(GameState.Mode.NORMAL)
	await get_tree().create_timer(0.25, true).timeout
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.15, true).timeout
	var ready_paused := get_tree().paused and GameState.is_ready_phase() and not GameState.is_menu()
	print("[pause] Phase.READY 按 ESC 后 paused=%s ready=%s menu=%s（必须 true / true / false）"
		% [get_tree().paused, GameState.is_ready_phase(), GameState.is_menu()])
	ok = ok and ready_paused

	_tap(KEY_ESCAPE)
	await get_tree().create_timer(1.2, true).timeout
	var ready_resumed := (not get_tree().paused) and GameState.is_running()
	print("[pause] Phase.READY 恢复并走完后 paused=%s running=%s（必须 false / true）"
		% [get_tree().paused, GameState.is_running()])
	ok = ok and ready_resumed

	# ⑥ Phase.RUNNING 期间真实按 ESC：必须直接弹出暂停（而不是只靠 _pause_game()）
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.15, true).timeout
	var run_paused := get_tree().paused and GameState.is_running() and not GameState.is_menu()
	print("[pause] Phase.RUNNING 按 ESC 后 paused=%s running=%s menu=%s（必须 true / true / false）"
		% [get_tree().paused, GameState.is_running(), GameState.is_menu()])
	ok = ok and run_paused
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.25, true).timeout

	# ⑦ 咬击演出期间（结算弹窗未出）按 ESC 不误退；弹出后再按 ESC 正常回主界面
	player.kill("caught_by_chaser")
	await get_tree().create_timer(0.15, true).timeout
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.1, true).timeout
	var end_early_kept := (GameState.phase == GameState.Phase.ENDED) and not GameState.is_menu()
	print("[pause] 咬击 0.25s 弹窗未出按 ESC：phase=%s menu=%s（必须 ENDED / false）"
		% [GameState.phase, GameState.is_menu()])
	ok = ok and end_early_kept
	await get_tree().create_timer(0.45, true).timeout
	_tap(KEY_ESCAPE)
	await get_tree().create_timer(0.1, true).timeout
	var end_panel_menu := GameState.is_menu()
	print("[pause] 结算弹窗出现后按 ESC：menu=%s（必须 true）" % end_panel_menu)
	ok = ok and end_panel_menu

	if ok:
		print("[pause] ALL PASS")
		get_tree().quit(0)
	else:
		push_error("[pause] FAIL")
		get_tree().quit(1)


## `-- --restart-demo`：验证死亡后按 R 的防误触延迟与重开走 Phase.READY。
func _run_restart_demo() -> void:
	var ok := true
	var fail := func(msg: String) -> void:
		ok = false
		push_error("[restart-demo] FAIL: " + msg)
		print("[restart-demo] FAIL: " + msg)

	# 1. 进入正常模式并触发黑鲸娘咬死
	GameState.start_run(GameState.Mode.NORMAL)
	await get_tree().create_timer(0.15, true).timeout
	_shake_kick = 1.0
	cam.offset = Vector2(6.0, -6.0)
	player.kill("caught_by_chaser")
	await get_tree().create_timer(0.15, true).timeout
	var early_panel := hud.is_end_panel_visible()
	print("[restart-demo] 1) 咬死 0.15s：结算面板=%s（必须 false）" % early_panel)
	if early_panel:
		fail.call("step 1: 结算面板在 0.15s 时提前显示")
	_tap(KEY_R)
	await get_tree().create_timer(0.05, true).timeout
	print("[restart-demo] 2) 0.15s 误触按 R：phase=%s（必须 ENDED=%s）"
		% [GameState.phase, GameState.Phase.ENDED])
	if GameState.phase != GameState.Phase.ENDED:
		fail.call("step 2: 0.45s 延迟期间按 R 不应提前重开")

	# 3. 等过 0.45s 后结算面板弹出，再按 R 应进入 Phase.READY
	await get_tree().create_timer(0.35, true).timeout
	var shown := hud.is_end_panel_visible()
	print("[restart-demo] 3a) >0.45s 后：结算面板=%s（必须 true）" % shown)
	if not shown:
		fail.call("step 3a: >0.45s 后结算面板未弹出")
	_tap(KEY_R)
	await get_tree().create_timer(0.10, true).timeout
	print("[restart-demo] 3b) 弹出后按 R：ready=%s chaser=%s wall=%s panel=%s menu=%s cam_off=%s"
		% [GameState.is_ready_phase(), chaser.visible, wall.active,
			hud.is_end_panel_visible(), menu.visible, cam.offset])
	if not (GameState.is_ready_phase() and chaser.visible and not wall.active
			and not hud.is_end_panel_visible() and not menu.visible
			and cam.offset == Vector2.ZERO):
		fail.call("step 3b: 按 R 未正确进入 Phase.READY 或状态未复位")

	# 4. 等待 READY_DURATION(1.25s) 过渡到正式 RUNNING
	await get_tree().create_timer(1.35, true).timeout
	print("[restart-demo] 4) 起跑衔接结束后：running=%s chaser=%s wall=%s"
		% [GameState.is_running(), chaser.visible, wall.active])
	if not (GameState.is_running() and not chaser.visible and wall.active):
		fail.call("step 4: Phase.READY 结束后未顺利交接至 Phase.RUNNING")

	# 5. 非咬死（坠崖）立即弹出结算面板，按 R 直接走 Phase.READY
	player.kill("fell_into_chasm")
	await get_tree().create_timer(0.05, true).timeout
	var chasm_shown := hud.is_end_panel_visible()
	_tap(KEY_R)
	await get_tree().create_timer(0.10, true).timeout
	print("[restart-demo] 5) 坠崖死后按 R：chasm_panel=%s ready=%s chaser=%s wall=%s"
		% [chasm_shown, GameState.is_ready_phase(), chaser.visible, wall.active])
	if not (chasm_shown and GameState.is_ready_phase() and chaser.visible and not wall.active):
		fail.call("step 5: 坠崖死后按 R 未立即结算并进 Phase.READY")

	# 6. 练习模式坠崖死后按 R 应跳过 Phase.READY 直接开跑
	GameState.start_run(GameState.Mode.PRACTICE)
	await get_tree().create_timer(0.05, true).timeout
	player.kill("fell_into_chasm")
	await get_tree().create_timer(0.05, true).timeout
	var prac_shown := hud.is_end_panel_visible()
	_tap(KEY_R)
	await get_tree().create_timer(0.10, true).timeout
	print("[restart-demo] 6) 练习模式死后按 R：panel=%s running=%s practice=%s"
		% [prac_shown, GameState.is_running(), GameState.is_practice()])
	if not (prac_shown and GameState.is_running() and GameState.is_practice()):
		fail.call("step 6: 练习模式按 R 未跳过 Phase.READY 直接重开")

	if ok:
		print("[restart-demo] ALL PASS")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


## `-- --achievements-demo`：在内存测试沙盒内完整验证 6 套皮肤立绘/大头贴、20 个成就解锁、按成就数量解锁皮肤、换装与设置→成就交互。
func _run_achievements_demo() -> void:
	var st := {"ok": true}
	var fail := func(msg: String) -> void:
		st["ok"] = false
		push_error("[achievements] FAIL: " + msg)
		print("[achievements] FAIL: " + msg)

	Progress.begin_test_sandbox()

	# 1. 所有 6 套皮肤全身立绘 & 正面大头贴资源必须存在，且主角保持默认精修动作帧（8/10/10）
	if SkinCatalog.ARTWORKS.size() != 6:
		fail.call("皮肤总数应为 6，实际=%d" % SkinCatalog.ARTWORKS.size())
	for a: Dictionary in SkinCatalog.ARTWORKS:
		var pv := String(a["preview"])
		var av := String(a.get("avatar", ""))
		if not ResourceLoader.exists(pv):
			fail.call("缺少皮肤立绘: " + pv)
		if av == "" or not ResourceLoader.exists(av):
			fail.call("缺少皮肤大头贴: " + av)
	if not player._anim.loaded \
			or player._anim.frame_count("run") != 8 \
			or player._anim.frame_count("jump") != 10 \
			or player._anim.frame_count("slide") != 10:
		fail.call("默认深海女仆动作帧加载异常")
	if SkinCatalog.ACHIEVEMENTS.size() != 26:
		fail.call("成就总数应为 26，实际=%d" % SkinCatalog.ACHIEVEMENTS.size())

	# 1b. 成就数不足 3 时不得装备 cozy_knit
	if Progress.set_equipped_skin("cozy_knit"):
		fail.call("成就数不足 3 时不应允许装备 cozy_knit")

	# 2. 练习模式下跑动 / 擦身 / 冲刺 / 追击 / 死亡不能计入正式成就
	GameState.start_run(GameState.Mode.PRACTICE)
	GameState.add_distance(1600.0 * 64.0)
	GameState.near_miss_awarded.emit()
	GameState.dash_started.emit()
	GameState.chase_ended.emit(0)
	GameState.end_run("caught_by_chaser")
	if Progress.unlocked_achievement_count() != 0 or int(Progress.stats["total_dist_m"]) != 0:
		fail.call("练习模式不应计入正式成就与累计数据")

	# 3a. 先测“无伤游侠”会被撞障打断（200m 撞障 -> 跑满 500m 仍不应解锁）
	GameState.start_run(GameState.Mode.NORMAL)
	GameState.add_distance(200.0 * 64.0)
	GameState.player_hit.emit("obstacle")
	GameState.add_distance(400.0 * 64.0) # 共 600m（解锁初潜突围 & 深海长泳 = 2个成就），撞过障不解锁无伤游侠
	await get_tree().process_frame
	if not Progress.is_achievement_unlocked("ach_dive_300m") or not Progress.is_achievement_unlocked("ach_dive_600m"):
		fail.call("600m 未解锁 初潜突围 或 深海长泳")
	if Progress.is_achievement_unlocked("ach_nohit_500m"):
		fail.call("局内撞障后跑满 600m 不应解锁 无伤游侠")
	if Progress.is_skin_unlocked("cozy_knit"):
		fail.call("只有 2 个成就时不应提前解锁 cozy_knit（需 3 个）")
	if not _toast.is_showing():
		fail.call("成就解锁后 Toast 未弹出")
	# 验证 Toast 至少稳定停留且在 >1.2s 后仍然完全可见（未提前淡出消失）
	await get_tree().create_timer(1.2).timeout
	if not _toast.is_showing() or _toast._card.modulate.a < 0.9 or _toast._holder.position.y < 40.0:
		fail.call("Toast 在 1.2s 时提前消失或未停稳 (showing=%s alpha=%.2f y=%.1f)" % [
			_toast.is_showing(), _toast._card.modulate.a, _toast._holder.position.y
		])

	# 3b. 新开一局零撞障跑满 1500m + 单局 10 擦身(累计100擦身) + 单局 50 冲刺 + 摆脱追击，触发第3+成就及全部技巧/追击类成就
	GameState.start_run(GameState.Mode.NORMAL)
	GameState.add_distance(500.0 * 64.0)
	if not Progress.is_achievement_unlocked("ach_nohit_500m"):
		fail.call("零撞障跑满 500m 应解锁 无伤游侠")
	if not Progress.is_skin_unlocked("cozy_knit"):
		fail.call("累计 3 个成就后应解锁 cozy_knit")
	for _i in 10:
		GameState.near_miss_awarded.emit()
	if not Progress.is_achievement_unlocked("ach_nearmiss_run_10"):
		fail.call("单局 10 次擦身未解锁 刀尖圆舞曲")
	for _i in 90:
		GameState.near_miss_awarded.emit()
	if not Progress.is_achievement_unlocked("ach_nearmiss_20") or not Progress.is_achievement_unlocked("ach_nearmiss_100"):
		fail.call("累计 100 次擦身未解锁 贴脸舞者 或 浪尖舞王")
	for _i in 4:
		GameState.dash_started.emit()
	GameState.add_distance(500.0 * 64.0) # 1000m 但只有 4 冲刺 -> 不解锁甩尾大师
	if Progress.is_achievement_unlocked("ach_master_1000m_5dash"):
		fail.call("1000m + 4 次冲刺时不应提前解锁 甩尾大师")
	GameState.dash_started.emit() # 第 5 冲刺 -> 解锁甩尾大师
	if not Progress.is_achievement_unlocked("ach_master_1000m_5dash"):
		fail.call("1000m 后补足第 5 次冲刺应立即解锁 甩尾大师")
	GameState.add_distance(500.0 * 64.0) # 1500m -> 解锁无底深潜者
	if not Progress.is_achievement_unlocked("ach_dive_1500m"):
		fail.call("1500m 未解锁 无底深潜者")
	for _i in 45:
		GameState.dash_started.emit() # 单局&累计 50 次 -> 解锁极限推进 & 深海疾风 & 涡轮鲸娘
	if not Progress.is_achievement_unlocked("ach_dash_run_8") \
			or not Progress.is_achievement_unlocked("ach_dash_15") \
			or not Progress.is_achievement_unlocked("ach_dash_50"):
		fail.call("冲刺成就（极限推进 / 深海疾风 / 涡轮鲸娘）未解锁")
	GameState.chase_ended.emit(0)
	if not Progress.is_achievement_unlocked("ach_chase_escape_1"):
		fail.call("首次摆脱追击未解锁 鲸口逃生")
	for c_idx in range(1, 5):
		GameState.chase_ended.emit(c_idx)
	if not Progress.is_achievement_unlocked("ach_chase_escape_5"):
		fail.call("累计 5 次摆脱追击未解锁 追逐大师")
	GameState.end_run("caught_by_chaser")
	if not Progress.is_achievement_unlocked("ach_easter_caught"):
		fail.call("caught_by_chaser 未解锁彩蛋 美味大肥鱼")

	# 4. 补足累计 15000m 与累计 30 局 + v2.0 Boss/星光藻/弹幕与小店成就 ⇒ 全部 26 个成就均应解锁
	for r in 29:
		GameState.start_run(GameState.Mode.HARD if r == 0 else GameState.Mode.NORMAL)
		if r == 0:
			GameState.add_distance(13000.0 * 64.0) # 累计达 15100m -> 解锁 全勤打工鱼(5000m) & 深海马拉松(15000m)
			GameState.boss_enraged_started.emit()
			for _sa in 3:
				GameState.run_plants["star_algae"] = int(GameState.run_plants.get("star_algae", 0)) + 1
			GameState.run_proj_dodged += 15
		GameState.end_run("caught_by_wall" if r == 0 else "fell_into_chasm")
	Progress.record_shop_instant(10, 1, 5)
	if Progress.unlocked_achievement_count() != SkinCatalog.ACHIEVEMENTS.size():
		fail.call("全部 26 个成就应均已解锁，实际=%d" % Progress.unlocked_achievement_count())
	for a: Dictionary in SkinCatalog.ARTWORKS:
		var sid := String(a["id"])
		if not Progress.is_skin_unlocked(sid):
			fail.call("全成就后皮肤未解锁: " + sid)

	# 5. UI 面板与换装校验（验证切换到 cozy_knit 后 8/10/10 帧可正常加载；待开发皮肤不得装备）
	if not Progress.set_equipped_skin("cozy_knit"):
		fail.call("满 3 个成就后应可装备 cozy_knit")
	if Progress.set_equipped_skin("burger_crew"):
		fail.call("实机动作待开发的 burger_crew 不应允许装备出战")
	if not player._anim.loaded \
			or player._anim.frame_count("run") != 8 \
			or player._anim.frame_count("jump") != 10 \
			or player._anim.frame_count("slide") != 10:
		fail.call("cozy_knit 皮肤动作帧加载异常")
	Progress.set_equipped_skin("default")
	GameState.to_menu()
	await get_tree().process_frame
	menu._choose(2) # 3 换装
	await get_tree().process_frame
	if not menu._wardrobe.visible:
		fail.call("主菜单选 3 换装 未打开 WardrobePanel")
	_tap(KEY_ESCAPE)
	await get_tree().process_frame
	if menu._wardrobe.visible:
		fail.call("ESC 未关闭 WardrobePanel")

	var has_ach_row := false
	for row: Dictionary in menu._settings._rows:
		if String(row["id"]) == "achievements":
			has_ach_row = true
	if not has_ach_row:
		fail.call("SettingsPanel 应包含 achievements（成就图鉴）行")
	menu._choose(3) # 4 设置
	await get_tree().process_frame
	menu._settings.open("achievements")
	menu._settings._adjust(menu._settings._sel, 1)
	await get_tree().process_frame
	if not menu._achievements.visible:
		fail.call("设置面板选择成就图鉴未打开 AchievementsPanel")
	_tap(KEY_ESCAPE)
	await get_tree().process_frame
	if menu._achievements.visible or not menu._settings.visible:
		fail.call("从成就面板按 ESC 应退回 SettingsPanel")
	_tap(KEY_ESCAPE)
	await get_tree().process_frame

	Progress.end_test_sandbox()
	if st["ok"]:
		print("[achievements] ALL PASS (artworks=%d achievements=%d/%d)" % [
			SkinCatalog.ARTWORKS.size(), SkinCatalog.ACHIEVEMENTS.size(), SkinCatalog.ACHIEVEMENTS.size()
		])
		get_tree().quit(0)
	else:
		push_error("[achievements] FAIL")
		get_tree().quit(1)


## `-- --phase1-demo`：验证 v2.0 Phase 1 全套核心链路：
##   4 种植物资源、保鲜箱上限替换、水泡护盾免减速、冲刺破障、红血削减→红转黑锁血、水压退场与右向左技能预警。
func _run_phase1_demo() -> void:
	var st := {"ok": true}
	var fail := func(msg: String) -> void:
		st["ok"] = false
		push_error("[phase1] FAIL: " + msg)
		print("[phase1] FAIL: " + msg)

	Progress.begin_test_sandbox()

	# 1. 植物贴图、黑鲸娘二阶段施法 4 帧、黑鲸娘飞行物 2 款、Phase 5 pixelfx 全部可加载
	for pid: String in GameState.PLANT_RARITY:
		if not PlantPickup.PLANT_TEX.has(pid) or PlantPickup.PLANT_TEX[pid] == null:
			fail.call("缺少植物贴图: " + pid)
	for tex in Chaser.CAST_TEX:
		if tex == null:
			fail.call("缺少 chaser_cast 贴图")
	if BossProjectile.TEX_PROJ_LOW == null or BossProjectile.TEX_PROJ_MID == null or BossProjectile.TEX_PROJ_HIGH == null:
		fail.call("缺少黑鲸风飞行物贴图 proj_low / proj_mid / proj_high")
	for fx_k in ["action/obstacle_break", "action/bubble_shield_break", "action/dash_shockwave",
			"chase/wall_retreat", "chase/skill_warning"]:
		if not FxCatalog.SPECS.has(fx_k) or not ResourceLoader.exists(String(FxCatalog.SPECS[fx_k]["path"])):
			fail.call("缺少 pixelfx 资源: " + fx_k)

	# 2. 鲸尾兜容量(9 格常规 + 1 格星光藻专属 = 10 格) & 互不顶替
	GameState.start_run(GameState.Mode.NORMAL)
	if GameState.basic_cap != 9 or GameState.star_cap != 1 or GameState.cooler_cap != 10:
		fail.call("鲸尾兜初始容量应为 9+1=10，实际=%d+%d=%d" % [
			GameState.basic_cap, GameState.star_cap, GameState.cooler_cap
		])
	for _i in 4:
		if not GameState.add_plant("kelp"):
			fail.call("装入第 %d 棵 kelp 失败" % (_i + 1))
	for _i in 3:
		if not GameState.add_plant("nori"):
			fail.call("装入第 %d 棵 nori 失败" % (_i + 1))
	for _i in 2:
		if not GameState.add_plant("seaweed"):
			fail.call("装入第 %d 棵 seaweed 失败" % (_i + 1))
	if GameState.basic_plants_count() != 9:
		fail.call("常规 9 格计数异常=%d" % GameState.basic_plants_count())
	if GameState.add_plant("nori") or GameState.add_plant("kelp"):
		fail.call("常规 9 格满后不应继续装入或顶替普通植物")
	if not GameState.add_plant("star_algae"):
		fail.call("常规 9 格满后专属第 10 格应可收入 star_algae")
	if int(GameState.run_plants["kelp"]) != 4 or int(GameState.run_plants["nori"]) != 3 \
			or int(GameState.run_plants["seaweed"]) != 2 or int(GameState.run_plants["star_algae"]) != 1:
		fail.call("星光藻收入后不得顶替已有植物: " + str(GameState.run_plants))
	if GameState.add_plant("star_algae"):
		fail.call("星光藻专属 1 格满后不应超收")

	# 3. 水泡护盾：免除 1 次碰撞减速硬直、保留 dash_charge 且不滑落收集物；碰障有 30% 概率滑落收集物与提示
	if not is_equal_approx(GameConfig.hit_plant_drop_chance, 0.30):
		fail.call("碰障滑落概率应为 0.30")
	player.bubble_shield = 1
	player.dash_charge = 2
	var spd_before := player.speed
	player.take_hit("low")
	if player.bubble_shield != 0 or player._stun > 0.0 or player.speed < spd_before * 0.99 or player.dash_charge != 2:
		fail.call("水泡护盾未正确免除减速或误扣势能")
	if GameState.total_plants() != 10:
		fail.call("水泡护盾抵挡撞击时不应滑落收集物")
	var dropped_p := GameState.drop_random_plant(true)
	if dropped_p == "" or GameState.total_plants() != 9 \
			or not hud._lbl_drop_toast.visible \
			or not hud._lbl_drop_toast.text.begins_with("有物品不小心滑落（"):
		fail.call("收集物滑落逻辑或 HUD 提示异常: dropped=%s toast=%s" % [
			dropped_p, hud._lbl_drop_toast.text
		])

	# 4. 冲刺破障 + ~1500m 采满节奏/等概率随机/无低障顶部悬空
	terrain.reset()
	var broke_any := false
	var seen_chunk_cols := {}
	var spawned_plants: Array[Dictionary] = []
	for k in 120:
		terrain.update_for(player.global_position.x + float(k) * 800.0)
		for chunk in terrain._chunks:
			if seen_chunk_cols.has(chunk.start_col):
				continue
			seen_chunk_cols[chunk.start_col] = true
			if not broke_any:
				for c in chunk.b.size():
					if chunk.b[c] == TerrainPatterns.LOW:
						chunk._break_hazard_col(c)
						if not chunk._broken_cols.has(c) or GameState.run_obstacles_broken < 1:
							fail.call("冲刺破障未标记破损或未计数")
						broke_any = true
						break
			for sub in chunk.get_children():
				var pick := sub as PlantPickup
				if pick == null:
					continue
				var lcol := int(floor(pick.position.x / float(GameConfig.TILE)))
				if lcol >= 0 and lcol < chunk.b.size() and chunk.b[lcol] == TerrainPatterns.LOW:
					fail.call("陆地矮障碍列上不得悬浮刷新收集物: " + pick.plant_id)
				spawned_plants.append({"gcol": chunk.start_col + lcol, "id": pick.plant_id})
	if not broke_any:
		fail.call("测试用地形未找到可破坏矮障碍")
	if spawned_plants.size() < 6:
		fail.call("1500m 区间内收集物过少: %d" % spawned_plants.size())
	else:
		var max_gap := 0
		for idx_p in spawned_plants.size():
			var item: Dictionary = spawned_plants[idx_p]
			var pid_s := String(item["id"])
			if idx_p > 0:
				var prev_item: Dictionary = spawned_plants[idx_p - 1]
				if String(prev_item["id"]) == pid_s:
					fail.call("收集物连续出现同种植物: " + pid_s)
				max_gap = maxi(max_gap, int(item["gcol"]) - int(prev_item["gcol"]))
		if max_gap > 205:
			fail.call("植物间距偏大(>205m): %d 列" % max_gap)

	# 5. 常规模式不狂暴只追击击退；困难模式近身弹开(<=240px) 1/2/3 扣血切图并进狂暴二阶段
	GameState.start_run(GameState.Mode.NORMAL)
	director._wave_timer = 0.01
	director.update(0.016)
	chaser.x = player.global_position.x - 180.0
	player.dash_charge = GameConfig.dash_charge_max
	player._start_dash()
	await get_tree().process_frame
	player._dash_t = 0.0
	hud.update_live(player, director)
	if GameState.boss_hp != 3 or GameState.boss_enraged or not director._post_hit_rush or hud._boss_bar.visible:
		fail.call("常规模式近身弹开应震退回逼且不扣 Boss 血条、不显示血条")

	GameState.start_run(GameState.Mode.HARD)
	if GameConfig.boss_max_hp != 3 or not is_equal_approx(GameConfig.boss_proj_star_drop_chance, 0.12):
		fail.call("Boss 血量或星光藻 12%% 掉率配置异常")
	director._wave_timer = 0.01
	director.update(0.016)
	if not director.in_chase or not chaser.active:
		fail.call("时间驱动倒计时归零后未正常触发追击进入一阶段")
	# 远处（gap > 240px）按 Space 不应打中黑鲸娘
	player.dash_charge = GameConfig.dash_charge_max
	player._start_dash()
	await get_tree().process_frame
	player._dash_t = 0.0
	if GameState.boss_hp != 3 or director._post_hit_rush:
		fail.call("黑鲸娘尚在远处(gap=%.1f)按 Space 不应隔空扣血" % chaser.gap())

	# 第 1 次近身弹开 → 切图1 (CAST_TEX[3]) → 疾追回逼 ~1.8s → 慢慢消散
	chaser.x = player.global_position.x - 180.0
	player.dash_charge = GameConfig.dash_charge_max
	player._start_dash()
	await get_tree().process_frame
	player._dash_t = 0.0
	if GameState.boss_hp != 2 or chaser._select_draw_tex()[0] != Chaser.CAST_TEX[3] or not director._post_hit_rush:
		fail.call("第 1 次近身弹开应扣血切图 1 并进入回逼追击")
	for _s1 in 40:
		player.global_position.x += player.speed * 0.05
		wall.update(0.05)
		chaser.update(0.05)
		director.update(0.05)
	if director.in_chase or chaser.active or chaser._fade_target > 0.0:
		fail.call("第 1 次弹开回逼后应结束追击并慢慢消散")

	# 第 2 次近身弹开 → 切图2 (CAST_TEX[0]) → 疾追回逼 → 慢慢消散
	director._wave_timer = 0.01
	director.update(0.016)
	chaser.x = player.global_position.x - 180.0
	player.dash_charge = GameConfig.dash_charge_max
	player._start_dash()
	await get_tree().process_frame
	player._dash_t = 0.0
	if GameState.boss_hp != 1 or chaser._select_draw_tex()[0] != Chaser.CAST_TEX[0]:
		fail.call("第 2 次近身弹开应扣血切图 2")
	for _s2 in 40:
		player.global_position.x += player.speed * 0.05
		wall.update(0.05)
		chaser.update(0.05)
		director.update(0.05)

	# 第 3 次近身弹开 → 切图3 (CAST_TEX[1]) + 红转黑锁血 + 水压墙屏幕左缘退场 → 图3 回逼 → 消散进二阶段召弹
	director._wave_timer = 0.01
	director.update(0.016)
	chaser.x = player.global_position.x - 180.0
	player.dash_charge = GameConfig.dash_charge_max
	player._start_dash()
	await get_tree().process_frame
	player._dash_t = 0.0
	if GameState.boss_hp != 0 or not GameState.boss_enraged or chaser._select_draw_tex()[0] != Chaser.CAST_TEX[1]:
		fail.call("第 3 次近身弹开应触发红转黑锁血并切图 3")
	if not wall._retreating and wall.active:
		fail.call("进入二阶段后 DeathWall 未启动退场")
	if wall.x < player.global_position.x - 420.0:
		fail.call("进入二阶段时 DeathWall 未拉入可见左侧边缘播放退场 (wall_x=%.1f player_x=%.1f)" % [
			wall.x, player.global_position.x
		])
	# 推进完成图3回逼(1.8s)+消散等待(2.0s)+首弹计时(1.65s)后进二阶段召弹试炼直道
	for _step in 120:
		player.global_position.x += player.speed * 0.05
		wall.update(0.05)
		chaser.update(0.05)
		director.update(0.05)
		boss_proj.update(0.05)
	if wall.active:
		fail.call("DeathWall 在二阶段推进后仍未彻底退场")
	if not director.in_barrage or not terrain.barrage_safe_mode:
		fail.call("第 3 次消散后应进入二阶段无障碍召弹试炼 (barrage=%s safe=%s)" % [
			str(director.in_barrage), str(terrain.barrage_safe_mode)
		])
	if not boss_proj.is_busy():
		fail.call("ChaseDirector 进入二阶段召弹后未自动触发右向左技能")

	boss_proj.reset()
	GameState.phase = GameState.Phase.RUNNING
	GameState.boss_enraged = true
	player.alive = true
	var lane_base_y := boss_proj._safe_surface_y(player.global_position.x + 280.0)
	player.global_position.y = lane_base_y
	boss_proj.spawn_attack(1)
	if boss_proj._warns.size() != 1:
		fail.call("BossProjectile 未生成右侧预警")
	# 1) 中高度(lane 1)：下滑可躲，同时检查世界坐标高速左移
	player.state = Player.St.SLIDE
	player._set_slide_shape()
	var prev_proj_wx := 1e12
	var moved_left := false
	for _step2 in 90:
		boss_proj.update(0.05)
		if not boss_proj._projs.is_empty():
			var cur_wx := boss_proj._projs[0].world_x
			if prev_proj_wx < 1e11 and cur_wx < prev_proj_wx - 10.0:
				moved_left = true
			prev_proj_wx = cur_wx
	if not moved_left:
		fail.call("飞行物世界横坐标未相对地面高速左移")
	if GameState.run_proj_dodged < 1:
		fail.call("二阶段中高度下滑躲避后未计数 (dodged=%d)" % GameState.run_proj_dodged)

	# 2) 中高度(lane 1)：跳跃同样可躲
	boss_proj.reset()
	player.state = Player.St.AIR
	player._set_stand_shape()
	player.global_position.y = lane_base_y - 110.0
	boss_proj.spawn_attack(1)
	for _step2b in 90:
		boss_proj.update(0.05)
	if GameState.run_proj_dodged < 2 or GameState.phase == GameState.Phase.ENDED:
		fail.call("中高度(lane 1)跳跃同样应可躲过")

	# 3) 高高度(lane 2)：下滑可躲，跳跃则会撞中致命
	boss_proj.reset()
	player.global_position.y = lane_base_y
	player.state = Player.St.SLIDE
	player._set_slide_shape()
	boss_proj.spawn_attack(2)
	for _step2c in 90:
		boss_proj.update(0.05)
	if GameState.run_proj_dodged < 3 or GameState.phase == GameState.Phase.ENDED:
		fail.call("高高度(lane 2)下滑应可躲过")

	boss_proj.reset()
	player.state = Player.St.AIR
	player._set_stand_shape()
	player.global_position.y = lane_base_y - 110.0
	boss_proj.spawn_attack(2)
	for _step2d in 80:
		boss_proj.update(0.05)
		if GameState.phase == GameState.Phase.ENDED:
			break
	if GameState.phase != GameState.Phase.ENDED or GameState.death_reason != "caught_by_boss_proj":
		fail.call("高高度(lane 2)起跳应撞中致命")
	# 恢复存活态以继续后续停滞与低空检查
	GameState.start_run(GameState.Mode.NORMAL)
	GameState.boss_enraged = true
	player.alive = true
	player.global_position.y = 0.0

	# 验证掉入凹地形原地跑时（distance=0），时间驱动仍能正常加速推波次（不死锁）
	director.in_barrage = false
	director.in_chase = false
	director._wave_timer = 1.0
	director._stall_t = 2.0
	director._last_px = player.global_position.x
	for _st_i in 10:
		director.update(0.05)
	if not director.in_chase:
		fail.call("原地停滞卡地形时时间驱动未按期触发黑鲸娘追击")

	# 验证狂暴阶段咬击切用图 4 (CAST_TEX[2])
	chaser.begin(player.global_position.x)
	chaser._start_bite()
	if chaser._select_draw_tex()[0] != Chaser.CAST_TEX[2]:
		fail.call("狂暴阶段被咬住应切用图 4 (CAST_TEX[2])")

	# 重置活体后验证站立硬吃贴地飞行物(lane 0)直接触发致命结算（而非仅减速）
	GameState.start_run(GameState.Mode.HARD)
	GameState.boss_enraged = true
	boss_proj.reset()
	player.alive = true
	player.state = Player.St.RUN
	player._set_stand_shape()
	player._dash_t = 0.0
	boss_proj.spawn_attack(0)
	for _step3 in 80:
		boss_proj.update(0.05)
		if GameState.phase == GameState.Phase.ENDED:
			break
	if GameState.phase != GameState.Phase.ENDED or GameState.death_reason != "caught_by_boss_proj":
		fail.call("中了二阶段飞行物应直接死亡结算 (phase=%s reason=%s)" % [
			str(GameState.phase), GameState.death_reason
		])

	Progress.end_test_sandbox()
	if st["ok"]:
		print("[phase1] ALL PASS (plants=4 cast=4 enraged=true wall_retreated=true proj_dodged=%d broken=%d)" % [
			GameState.run_proj_dodged, GameState.run_obstacles_broken
		])
		get_tree().quit(0)
	else:
		push_error("[phase1] FAIL")
		get_tree().quit(1)


func _on_end_shop_requested() -> void:
	if GameState.phase != GameState.Phase.ENDED or not hud.is_end_panel_visible():
		return
	_run_transition(func() -> void:
		GameState.to_menu()
		menu.open_shop()
	)


func _prepare_shop_shot() -> void:
	Progress.begin_test_sandbox()
	Progress.ingredients = {"kelp": 5, "nori": 4, "seaweed": 5, "star_algae": 2}
	Progress.shell_coins = 180
	Progress.shop_decor_lv = 1
	Progress.total_boss_enrages = 1
	menu.open_shop()
	var sp := menu._shop
	sp._start_shift()
	# 摆上热腾腾出餐托盘 + 一台正在金脆区的油炸锅 + 多名海洋顾客（含乔装黑鲸娘）方便截图验收
	sp._on_craft_dish("fries")
	sp._cook_slots[0].progress = 0.72
	sp._try_place_on_tray("burger", true)
	sp._try_place_on_tray("supreme", true)
	sp._cust_slots[0].occupied = true
	sp._cust_slots[0].cust_id = "seahorse"
	sp._cust_slots[0].max_patience = 28.0
	sp._cust_slots[0].patience = 24.0
	sp._cust_slots[0].orders.clear()
	sp._cust_slots[0].orders.append("fries")
	sp._cust_slots[1].occupied = true
	sp._cust_slots[1].cust_id = "jelly"
	sp._cust_slots[1].orders.clear()
	sp._cust_slots[1].orders.append("nuggets")
	sp._cust_slots[1].max_patience = 32.0
	sp._cust_slots[1].patience = 28.0
	sp._cust_slots[2].occupied = true
	sp._cust_slots[2].cust_id = "shark"
	sp._cust_slots[2].orders.clear()
	sp._cust_slots[2].orders.append("supreme")
	sp._cust_slots[2].max_patience = 34.0
	sp._cust_slots[2].patience = 29.0
	sp._refresh_ui()


func _run_phase2_demo() -> void:
	await get_tree().process_frame
	Progress.begin_test_sandbox()
	var st := {"ok": true}
	var fail := func(msg: String):
		push_error("[phase2] FAIL: " + msg)
		st["ok"] = false

	# 1. 验证主菜单已重整为 4 大入口（出海奔跑 / 鲸堡小店 / 换装 / 设置）
	if MainMenu.OPTIONS.size() != 4 or String(MainMenu.OPTIONS[0]["title"]) != "出海奔跑" \
			or String(MainMenu.OPTIONS[1]["title"]) != "鲸堡小店":
		fail.call("MainMenu 入口配置异常")

	# 2. 打开小店并验证首次开业赠礼、2分半营业、固定座位(含水母姐妹)、慢火金脆与黑鲸娘双倍小费
	menu.open_shop()
	var sp := menu._shop
	if not sp.visible or int(Progress.ingredients["kelp"]) != 3 or int(Progress.ingredients["nori"]) != 2:
		fail.call("小店首次打开赠礼异常: " + str(Progress.ingredients))
	if not is_equal_approx(ShopPanel.SHIFT_DURATION, 150.0):
		fail.call("小店单轮营业时长应为 150s (2:30)")

	sp._start_shift()
	# 开局先于 Booth 1 迎来水母姐妹，Slot 0 固定海马，Slot 1 下次轮到海龟爷爷，Slot 2 为锤头鲨/黑鲸娘
	if not sp._cust_slots[1].occupied or sp._cust_slots[1].cust_id != "jelly":
		fail.call("Slot 1 首客应保障水母姐妹登场: " + sp._cust_slots[1].cust_id)
	sp._cust_slots[0].leave_cd = 0.0
	sp._try_spawn_customer(0)
	if not sp._cust_slots[0].occupied or sp._cust_slots[0].cust_id != "seahorse":
		fail.call("Slot 0 外卖窗应固定海马: " + sp._cust_slots[0].cust_id)
	sp._cust_slots[1].occupied = false
	sp._cust_slots[1].leave_cd = 0.0
	sp._try_spawn_customer(1)
	if sp._cust_slots[1].cust_id != "turtle":
		fail.call("Slot 1 轮转应出现海龟爷爷: " + sp._cust_slots[1].cust_id)

	sp._on_craft_dish("fries")
	if not sp._cook_slots[0].active or sp._cook_slots[0].dish_id != "fries" or sp._cook_slots[0].duration < 2.5:
		fail.call("海苔咔嚓长条未成功下锅或烹饪节奏未放慢 (dur=%.2f)" % sp._cook_slots[0].duration)
	sp._cook_slots[0].progress = 0.72
	if not sp._trigger_crisp_hit("fryer"):
		fail.call("金脆区按键判定未触发")
	if sp._tray[0].dish_id != "fries" or not sp._tray[0].crisp:
		fail.call("金脆出锅菜品未落入出餐托盘")

	sp._cust_slots[2].occupied = true
	sp._cust_slots[2].cust_id = "blackwhale"
	sp._cust_slots[2].eating = false
	sp._cust_slots[2].orders.clear()
	sp._cust_slots[2].orders.append("fries")
	sp._cust_slots[2].max_patience = 30.0
	sp._cust_slots[2].patience = 30.0
	var coins_before := Progress.shell_coins
	if not sp._serve_customer_slot(2):
		fail.call("递餐给乔装黑鲸娘失败")
	# 基础 12 * 金脆 1.3 * 黑鲸娘 2.0 = 31
	if Progress.shell_coins - coins_before < 30 or not sp._cust_slots[2].eating:
		fail.call("黑鲸娘双倍贝壳币或开心嚼嚼状态异常: +%d" % (Progress.shell_coins - coins_before))

	# 3. 店铺 3 条升级线与保鲜兜容量联动
	Progress.add_shell_coins(400)
	if not Progress.upgrade_shop_track("fryer") or Progress.shop_fryer_lv != 1:
		fail.call("炸锅升级失败")
	if not Progress.upgrade_shop_track("decor") or Progress.shop_decor_lv != 1:
		fail.call("装潢升级失败")
	if not Progress.upgrade_shop_track("cooler") or Progress.cooler_upgrade_lv != 1 or Progress.cooler_capacity != 12:
		fail.call("保鲜兜扩容失败: cap=%d" % Progress.cooler_capacity)

	# 验证升级双锅后可同时烹饪 2 份油炸菜
	Progress.ingredients["kelp"] += 4
	Progress.ingredients["seaweed"] += 4
	sp._on_craft_dish("burger")
	sp._on_craft_dish("nuggets")
	if not sp._cook_slots[0].active or not sp._cook_slots[1].active:
		fail.call("双联炸锅未支持同时烹饪 2 份")
	sp._cook_slots[0].progress = 1.0
	sp._cook_slots[1].progress = 1.0
	sp._process(0.05)

	# 4. 验证试吃 Buff → 正常出海联动：
	#    (a) 脆藻双层堡：开局 1 层水泡护盾，且不与练习模式消耗混淆
	var tray_burger := -1
	for ti in sp._tray.size():
		if sp._tray[ti].dish_id == "burger":
			tray_burger = ti
			break
	if tray_burger < 0:
		fail.call("托盘未找到做好的脆藻双层堡")
	else:
		sp._on_eat_tray_buff(tray_burger)
	if Progress.active_meal_buff != "burger":
		fail.call("试吃脆藻双层堡后未设置赛前 Buff")
	sp.close()

	GameState.start_run(GameState.Mode.PRACTICE)
	if Progress.active_meal_buff != "burger" or player.bubble_shield != 0:
		fail.call("练习模式不应偷跑消耗正常出海 Buff")

	GameState.start_run(GameState.Mode.NORMAL)
	if Progress.active_meal_buff != "" or GameState.active_run_buff != "shield" or player.bubble_shield != 1:
		fail.call("正常出海未正确消费并激活护盾 Buff (shield=%d)" % player.bubble_shield)
	if GameState.cooler_cap != 12 or GameState.basic_cap != 11:
		fail.call("扩容后的保鲜兜容量未同步到出航状态 (%d/%d)" % [GameState.basic_cap, GameState.cooler_cap])

	#    (b) 海藻脆脆块：势能上限 2 格即可冲刺 + (c) 海苔长条：对一阶段黑鲸娘 2 格伤
	Progress.set_active_meal_buff("nuggets")
	GameState.start_run(GameState.Mode.NORMAL)
	if GameState.effective_dash_charge_max() != 2:
		fail.call("海藻脆脆块快充 Buff 未将上限改为 2 格")

	Progress.set_active_meal_buff("fries")
	GameState.start_run(GameState.Mode.HARD)
	director._wave_timer = 0.01
	director.update(0.016)
	chaser.x = player.global_position.x - 160.0
	player.dash_charge = GameState.effective_dash_charge_max()
	player._start_dash()
	await get_tree().process_frame
	if GameState.boss_hp != 1:
		fail.call("困难模式海苔长条冲刺增压未造成 2 格伤害 (boss_hp=%d)" % GameState.boss_hp)

	#    (d) 星光特饮 22% 掉率 + 至尊堡 1.35s 冲刺+护盾 + 困难/常规均可吃Buff存档
	Progress.set_active_meal_buff("soda")
	GameState.start_run(GameState.Mode.HARD)
	if not is_equal_approx(GameState.effective_star_drop_chance(), 0.22):
		fail.call("困难模式星光藻皇特饮未将星光藻掉率提升至 22%%")

	Progress.set_active_meal_buff("supreme")
	GameState.start_run(GameState.Mode.HARD)
	if player.bubble_shield != 1:
		fail.call("困难模式星光海藻至尊堡未附带水泡护盾")
	player._start_dash()
	if player._dash_t <= GameConfig.dash_time * 1.30:
		fail.call("星光海藻至尊堡未延长冲刺时间")

	Progress.end_test_sandbox()
	if st["ok"]:
		print("[phase2] ALL PASS (shop_ui=ok buffs=6 upgrades=3 disguise_double=ok)")
		get_tree().quit(0)
	else:
		push_error("[phase2] FAIL")
		get_tree().quit(1)


## 点一下某个键（按下 + 抬起）。只用于 `--pause-demo`。
func _tap(k: Key) -> void:
	_send_key(k, true)
	_send_key(k, false)


## 造一个真的按键事件塞进输入队列（`--pause-demo` 用）。
## 走 `Input.parse_input_event` 是为了让事件真的过一遍 `_unhandled_input` 分发，
## 直接调 `_pause_game()` 是测不出"暂停后还能不能收到输入"的。
func _send_key(k: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = pressed
	Input.parse_input_event(ev)


# ---------------------------------------------------------------- 调试
func _unhandled_input(event: InputEvent) -> void:
	if intro != null and intro.is_playing():
		return
	if _transition != null and _transition.is_playing():
		return
	if event.is_action_pressed("back_to_menu"):
		if GameState.is_menu():
			return
		# 暂停中的 ESC 由 `PausePanel` 自己接 —— 树被暂停后这里根本收不到事件
		if _pause_ignore > 0.0:
			return
		# 正常 / 练习（含正常模式 1.25s 起跑过场 Phase.READY）：ESC = **暂停**，
		# 避免起跑瞬间误按 ESC 直接弃局回主界面；
		# 沙盒例外：那是开发观察用的，ESC 保持直通菜单，别让暂停再多挡一层；
		# 结算期只有面板已弹出时才允许 ESC 回主界面（与 R 键同样保护 0.45s 咬击演出）。
		if (GameState.is_running() or GameState.is_ready_phase()) and not GameState.is_sandbox():
			_pause_game()
			get_viewport().set_input_as_handled()
		elif GameState.is_sandbox():
			_run_transition(func() -> void: GameState.to_menu())
			get_viewport().set_input_as_handled()
		elif GameState.phase == GameState.Phase.ENDED and hud.is_end_panel_visible():
			_run_transition(func() -> void: GameState.to_menu())
			get_viewport().set_input_as_handled()
		return
	if GameState.is_menu():
		return          # 界面上的按键交给 MainMenu 自己处理
	if event.is_action_pressed("restart"):
		if GameState.phase == GameState.Phase.ENDED:
			# 被黑鲸娘咬死时需等 0.45s 咬击播完、结算面板弹出后再响应 R/B，避免误触跳过咬击动画；
			# 其余死法结算面板会立刻弹出，按 R/B 即可马上重开或进店。
			if hud.is_end_panel_visible():
				_run_transition(func() -> void: _on_mode_chosen(GameState.mode))
		elif GameState.is_sandbox():
			_on_mode_chosen(GameState.mode)
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_B \
			and GameState.phase == GameState.Phase.ENDED and hud.is_end_panel_visible():
		_on_end_shop_requested()
		get_viewport().set_input_as_handled()
		return

	# ---- 沙盒：手动调速。一路调到很慢就是逐帧慢放 ----
	if GameState.is_sandbox():
		if event.is_action_pressed("test_slower"):
			_set_test_speed(Difficulty.speed_override - GameConfig.test_speed_step)
			return
		if event.is_action_pressed("test_faster"):
			_set_test_speed(Difficulty.speed_override + GameConfig.test_speed_step)
			return

	# ---- 手感热调：定下来之后把数值写回 GameConfig 即可固化 ----
	if event.is_action_pressed("debug_toggle"):
		_dump_debug()
		return
	if event.is_action_pressed("tune_faster"):
		GameConfig.run_cycle_px = maxf(80.0, GameConfig.run_cycle_px - 20.0)
		_report_tuning()
	elif event.is_action_pressed("tune_slower"):
		GameConfig.run_cycle_px = minf(900.0, GameConfig.run_cycle_px + 20.0)
		_report_tuning()
	elif event.is_action_pressed("nudge_up") or event.is_action_pressed("nudge_down"):
		var a := player.debug_anim_action()
		if a == "" or not GameConfig.anim_y_offset.has(a):
			return
		var dir := 1.0 if event.is_action_pressed("nudge_up") else -1.0
		GameConfig.anim_y_offset[a] = float(GameConfig.anim_y_offset[a]) \
			+ dir * GameConfig.anim_y_offset_step
		_report_tuning()
	elif event.is_action_pressed("toggle_fps_snap"):
		GameConfig.anim_fps_snap = not GameConfig.anim_fps_snap
		print("[动画] 帧率吸附 = %s　（%.0fHz 上吸附后每帧恒定占整数个显示帧）"
			% ["开" if GameConfig.anim_fps_snap else "关", GameConfig.anim_refresh_rate()])
	elif event.is_action_pressed("toggle_uniform_h"):
		GameConfig.anim_uniform_height = not GameConfig.anim_uniform_height
		print("[动画] 帧身高统一 = %s　（只影响 run；关掉即回到逐帧原尺寸）"
			% ["开" if GameConfig.anim_uniform_height else "关"])


func _set_test_speed(v: float) -> void:
	Difficulty.speed_override = clampf(v, GameConfig.test_speed_min,
		GameConfig.test_speed_max)
	print("[测试模式] 速度 = %.0f px/s　（, 减速 / . 加速；调到 0 就是慢放静止）"
		% Difficulty.speed_override)


func _report_tuning() -> void:
	print("[热调] 跑步循环 = %.0f px（越小腿转越快）　纵向微调 = %s（正数上移）"
		% [GameConfig.run_cycle_px, str(GameConfig.anim_y_offset)])
	var n := player.debug_run_frame_count()
	var raw := player.speed * float(n) / maxf(GameConfig.run_cycle_px, 1.0)
	var snap := GameConfig.snap_anim_fps(raw)
	print("       当前动作 %s　帧率 原始 %.1f → 吸附 %.1f fps（每帧 %.1f 个显示帧）"
		% [player.debug_anim_action(), raw, snap,
			GameConfig.anim_refresh_rate() / maxf(snap, 0.01)])


## 档位体检：把 470~720 整个速度区间扫一遍，看吸附后会不会跨档。
## 跨档意味着跑着跑着动画帧率会突然变一档（每帧 2 个显示帧 ↔ 3 个），
## 那本身就是一次可见的跳变 —— 所以要靠这个检查来选 run_cycle_px。
## 在两个相邻采样速度之间二分，找出**精确的换档速度**。
##
## 为什么需要它：采样步长 30px/s，而 15↔20 的真实分界在 459.4px/s ——
## 采样会把这次换档报到 480 那个点上，而 480 落在跑速区间内，
## 于是"区间内换档次数"凭空多出 1，把一次无害的区间外换档读成问题。
##
## ⚠ 每次试探前都要 `reset_anim_fps_ladder()`：`snap_anim_fps()` 带迟滞状态，
##   而二分是乱序取点的，带着迟滞去比会得到不自洽的结果。
func _gear_boundary(lo: float, hi: float, n: int) -> float:
	var a := lo
	var b := hi
	GameConfig.reset_anim_fps_ladder()
	var fa := GameConfig.snap_anim_fps(a * float(n) / maxf(GameConfig.run_cycle_px, 1.0))
	for i in 24:
		var m := (a + b) * 0.5
		GameConfig.reset_anim_fps_ladder()
		var fm := GameConfig.snap_anim_fps(m * float(n) / maxf(GameConfig.run_cycle_px, 1.0))
		if absf(fm - fa) > 0.01:
			b = m
		else:
			a = m
	GameConfig.reset_anim_fps_ladder()
	return b


func _report_anim_ladder() -> void:
	var n := player.debug_run_frame_count()
	if n <= 0:
		print("[档位] 跑步帧序列没加载，检查 sprites/run")
		return
	print("========== 跑步动画档位体检（刷新率 %.0fHz）=========="
		% GameConfig.anim_refresh_rate())
	print("run_cycle_px = %.0f，%d 帧" % [GameConfig.run_cycle_px, n])
	var last := -1.0
	var last_sp := 0.0
	var switches := 0
	var in_range := 0
	# ⚠ 这一趟扫的是 300~900px/s **整条曲线**，比实际跑速区间宽。
	#   所以「换档次数」这个总数天生不为 0（区间外那几次无害），
	#   真正要看的是**区间内**有没有换档 —— 只有它会让玩家看见跳变。
	var sp_lo := GameConfig.run_speed_start
	var sp_hi := GameConfig.run_speed_start + GameConfig.run_speed_bonus_max
	for i in 21:
		var sp := 300.0 + float(i) * 30.0
		var raw := sp * float(n) / maxf(GameConfig.run_cycle_px, 1.0)
		var sn := GameConfig.snap_anim_fps(raw)
		var mark := ""
		if last > 0.0 and absf(sn - last) > 0.01:
			# 采样步长 30px/s 太粗：分界落在 459.4 时会被报成"480 处换档"，
			# 而 480 落在跑速区间内 —— 于是凭空多报一次"区间内换档"。
			# 所以二分求出**精确的换档速度**再判定。
			var at := _gear_boundary(last_sp, sp, n)
			var inside := at > sp_lo and at <= sp_hi
			mark = "  <== 换档 @ %.0f px/s" % at + ("★ 在跑速区间内" if inside else "（区间外，无害）")
			switches += 1
			if inside:
				in_range += 1
		last = sn
		last_sp = sp
		print("  速度 %5.0f  px/s　原始 %5.1f → 吸附 %5.1f fps　每帧 %4.1f 个显示帧%s"
			% [sp, raw, sn, GameConfig.anim_refresh_rate() / maxf(sn, 0.01), mark])
	print("换档次数 = %d，其中**跑速区间 %.0f~%.0f 内 %d 次**（希望是 0）"
		% [switches, sp_lo, sp_hi, in_range])
	print("=====================================================")
	# 这趟扫描会把迟滞里的「上一档」写脏，清掉免得影响下一帧的真实播放
	GameConfig.reset_anim_fps_ladder()


func _dump_debug() -> void:
	print("========== 运行状态 ==========")
	print("距离 %.0f px (%.0f m)  档位 %d  目标速度 %.0f  平衡间距 %.0f"
		% [GameState.distance, GameState.distance / 64.0, Difficulty.current_tier(),
			Difficulty.player_target_speed(), Difficulty.equilibrium_gap()])
	print("运动包络：apex %.1f px (%.2f 格)  滞空 %.3f s  跳距 %.0f px (%.2f 格)"
		% [GameConfig.jump_apex_height(), GameConfig.jump_apex_height() / 64.0,
			GameConfig.jump_air_time(),
			GameConfig.jump_distance(Difficulty.player_target_speed()),
			GameConfig.jump_distance(Difficulty.player_target_speed()) / 64.0])
	print("安全余量：最大坑宽 %d 格  最大台阶 %d 格  最小障碍间距 %.0f px"
		% [Difficulty.max_safe_gap_tiles(), Difficulty.max_safe_step_tiles(),
			Difficulty.min_hazard_spacing_px()])
	print("地形：已生成 %d 列，活动块 %d，剧本剩余 %d"
		% [terrain.total_cols_generated(), terrain.chunk_count(),
			terrain.script_remaining()])
	print("动画：当前动作 %s，帧率 原始 %.1f → 吸附 %.1f fps（跑步循环 %.0fpx / 循环）"
		% [player.debug_anim_action(), player.debug_anim_fps_raw(),
			player.debug_anim_fps(), GameConfig.run_cycle_px])
	print("      帧率吸附 %s　帧身高统一 %s（只影响 run）　刷新率 %.0fHz"
		% ["开" if GameConfig.anim_fps_snap else "关",
			"开" if GameConfig.anim_uniform_height else "关",
			GameConfig.anim_refresh_rate()])
	print("动画纵向微调：", GameConfig.anim_y_offset, "　（; ' 微调，[ ] 改循环，- = 开关修复项）")
	print("死亡边界间距 %.0f / 平衡值 %.0f  %s"
		% [wall.gap(), Difficulty.equilibrium_gap(),
			"（追击中，已停车）" if director.in_chase else ""])
	print("模式拒绝统计：", terrain.reject_stats)
	_report_anim_ladder()
	print("=============================")


func _pv_tick_proj_dodge(delta: float) -> void:
	if _pv_dodge_timer > 0.0:
		_pv_dodge_timer -= delta
		if _pv_dodge_timer <= 0.0:
			Input.action_release("jump")
			Input.action_release("slide")
			Input.action_release("dash")
			if autopilot != null and _pv_scene == "boss":
				autopilot.enabled = true
	if boss_proj == null or player == null:
		return
	var px := player.global_position.x
	for pi in boss_proj._projs:
		var dx: float = float(pi.world_x) - px
		if _pv_parry_next and pi.lane == 1 and dx > 30.0 and dx < 220.0:
			_pv_parry_next = false
			if autopilot != null:
				autopilot.enabled = false
			Input.action_release("jump")
			Input.action_release("slide")
			player.dash_charge = 3
			Input.action_press("dash")
			_pv_dodge_timer = 0.16
			break
		if dx > 50.0 and dx < 310.0 and _pv_dodge_timer <= 0.0:
			if autopilot != null:
				autopilot.enabled = false
			if pi.lane == 0:
				Input.action_release("slide")
				Input.action_press("jump")
				_pv_dodge_timer = 0.42
			else:
				Input.action_release("jump")
				Input.action_press("slide")
				_pv_dodge_timer = 0.48
			break


## `-- --pv-scene=<intro|cold_open|parkour|boss|shop|shield>`：60fps 宣传 PV 导演录制专场（仅保留纯净 SFX）。
func _run_pv_scene() -> void:
	AudioManager.stop_bgm(0.0)
	AudioManager.set_bus_volumes(0.0, 1.0)
	Progress.begin_test_sandbox()
	Progress._force_track_for_test = false
	if _toast != null:
		_toast.visible = false

	match _pv_scene:
		"intro":
			menu.set_intro_blocking(true)
			menu.visible = false
			intro.play(false)
			intro._skip_lbl.text = ""
			intro._subtitle_lbl.text = ""
		"cold_open":
			menu.visible = false
			GameState.start_run(GameState.Mode.HARD)
			AudioManager.stop_bgm(0.0)
			AudioManager.set_bus_volumes(0.0, 1.0)
			autopilot.enabled = true
			terrain.push_script(["low1", "flat8"])
			await get_tree().create_timer(0.25).timeout
			director._wave_timer = 0.02
			director.update(0.016)
			chaser.x = player.global_position.x - 165.0
			chaser._fade = 1.0
			chaser._apply_fade()
			await get_tree().create_timer(0.75).timeout
			autopilot.enabled = false
			player.dash_charge = 3
			Input.action_press("dash")
			await get_tree().create_timer(0.10).timeout
			Input.action_release("dash")
			await get_tree().create_timer(0.60).timeout
			autopilot.enabled = true
		"parkour":
			menu.visible = false
			GameState.start_run(GameState.Mode.NORMAL)
			AudioManager.stop_bgm(0.0)
			AudioManager.set_bus_volumes(0.0, 1.0)
			autopilot.enabled = true
			director._wave_timer = 999.0
			var pk_t0 := Time.get_ticks_msec()
			await get_tree().create_timer(12.2).timeout
			for _wait_f in 120:
				if player.is_on_floor() and player._anim.current_action() == "run" and int(player._anim._index) == 0:
					break
				await get_tree().process_frame
			var swap_sec := float(Time.get_ticks_msec() - pk_t0) / 1000.0
			print("[pv] parkour_swap_sec=%.3f" % swap_sec)
			Progress.unlocked_achievements["ach_dive_300m"] = true
			Progress.unlocked_achievements["ach_dive_600m"] = true
			Progress.unlocked_achievements["ach_dive_1500m"] = true
			Progress.set_equipped_skin("cozy_knit")
			terrain.rng.seed = 20261130
			player.global_position = Vector2(0.0, 0.0)
			_prev_x = 0.0
			terrain.reset()
			_snap_camera()
			director._wave_timer = 999.0
		"boss":
			menu.visible = false
			GameState.start_run(GameState.Mode.HARD)
			AudioManager.stop_bgm(0.0)
			AudioManager.set_bus_volumes(0.0, 1.0)
			autopilot.enabled = true
			_pv_dodge = true
			_pv_parry_next = false
			GameState.boss_hp = 1
			await get_tree().create_timer(0.25).timeout
			director._wave_timer = 0.02
			director.update(0.016)
			chaser.x = player.global_position.x - 170.0
			chaser._fade = 1.0
			chaser._apply_fade()
			await get_tree().create_timer(0.85).timeout
			player.dash_charge = 3
			Input.action_press("dash")
			await get_tree().create_timer(0.10).timeout
			Input.action_release("dash")
			await get_tree().create_timer(0.55).timeout
			director._wave_timer = 0.02
			director._p2_next_is_barrage = true
			director.update(0.016)
			await get_tree().create_timer(1.25).timeout
			autopilot.enabled = true
			wall.active = false
			wall.x = player.global_position.x - 2400.0
			boss_proj._spawn_star_algae_reward()
			# 高密度一镜到底 Climax：跳低刃 -> 滑高刃星光藻 -> 正面 Space 碎飞轮 -> 再连闪两波 -> 狂暴黑鲸贴脸扑咬！
			boss_proj.spawn_attack(0)
			await get_tree().create_timer(0.92).timeout
			boss_proj.spawn_attack(2)
			boss_proj._spawn_star_algae_reward()
			await get_tree().create_timer(0.92).timeout
			_pv_parry_next = true
			boss_proj.spawn_attack(1)
			await get_tree().create_timer(1.05).timeout
			boss_proj.spawn_attack(0)
			await get_tree().create_timer(0.85).timeout
			boss_proj.spawn_attack(2)
			boss_proj._spawn_star_algae_reward()
			await get_tree().create_timer(0.85).timeout
			# 终极压迫 Climax：清空多余弹幕后狂暴黑鲸本体贴脸逼近并凌空张嘴扑咬，定格红爪瞬间白闪断音！
			director._finish_barrage()
			boss_proj.reset()
			director._begin()
			chaser._pose_stage = 3
			chaser.x = player.global_position.x - 175.0
			chaser._fade = 1.0
			chaser._apply_fade()
			await get_tree().create_timer(0.95).timeout
			if GameState.is_running() and chaser != null:
				chaser._start_bite()
		"shop":
			Progress.ingredients = {"kelp": 18, "nori": 15, "seaweed": 15, "star_algae": 5}
			Progress.shop_fryer_lv = 2
			Progress.shop_decor_lv = 2
			Progress.shell_coins = 180
			menu.open_shop()
			AudioManager.stop_bgm(0.0)
			AudioManager.set_bus_volumes(0.0, 1.0)
			var sp := menu._shop
			sp._start_shift()
			sp._cust_slots[0].occupied = true
			sp._cust_slots[0].cust_id = "seahorse"
			sp._cust_slots[0].eating = false
			sp._cust_slots[0].orders.assign(["fries"])
			sp._cust_slots[0].patience = 28.0
			sp._cust_slots[1].occupied = true
			sp._cust_slots[1].cust_id = "jelly"
			sp._cust_slots[1].eating = false
			sp._cust_slots[1].orders.assign(["nuggets"])
			sp._cust_slots[1].patience = 32.0
			sp._cust_slots[2].occupied = true
			sp._cust_slots[2].cust_id = "turtle"
			sp._cust_slots[2].eating = false
			sp._cust_slots[2].orders.assign(["burger"])
			sp._cust_slots[2].patience = 42.0
			sp._refresh_ui()
			await get_tree().create_timer(0.55).timeout
			sp._on_craft_dish("fries")
			sp._on_craft_dish("nuggets")
			await get_tree().create_timer(1.55).timeout
			sp._cook_slots[0].progress = 0.68
			sp._trigger_crisp_hit("fryer")
			await get_tree().create_timer(0.65).timeout
			sp._cook_slots[1].progress = 0.68
			sp._trigger_crisp_hit("fryer")
			await get_tree().create_timer(0.60).timeout
			sp._serve_customer_slot(1)
			await get_tree().create_timer(0.95).timeout
			sp._serve_customer_slot(0)
			await get_tree().create_timer(0.60).timeout
			sp._on_craft_dish("burger")
			await get_tree().create_timer(1.55).timeout
			sp._cook_slots[0].progress = 0.70
			sp._trigger_crisp_hit("fryer")
			await get_tree().create_timer(0.75).timeout
			for ti in sp._tray.size():
				if sp._tray[ti].dish_id == "burger":
					sp._on_eat_tray_buff(ti)
					break
		"shop_button":
			Progress.ingredients = {"kelp": 15, "nori": 12, "seaweed": 12, "star_algae": 4}
			Progress.shop_fryer_lv = 2
			Progress.shop_decor_lv = 2
			Progress.shell_coins = 360
			menu.open_shop()
			AudioManager.stop_bgm(0.0)
			AudioManager.set_bus_volumes(0.0, 1.0)
			var sp := menu._shop
			sp._start_shift()
			sp._cust_slots[0].occupied = true
			sp._cust_slots[0].cust_id = "seahorse"
			sp._cust_slots[0].eating = false
			sp._cust_slots[0].orders.assign(["fries"])
			sp._cust_slots[0].patience = 28.0
			sp._cust_slots[1].occupied = true
			sp._cust_slots[1].cust_id = "jelly"
			sp._cust_slots[1].eating = false
			sp._cust_slots[1].orders.assign(["nuggets"])
			sp._cust_slots[1].patience = 32.0
			sp._cust_slots[2].occupied = true
			sp._cust_slots[2].cust_id = "blackwhale"
			sp._cust_slots[2].eating = false
			sp._cust_slots[2].orders.assign(["supreme"])
			sp._cust_slots[2].patience = 30.0
			sp._tray[0].dish_id = "supreme"
			sp._tray[0].crisp = true
			sp._refresh_ui()
			await get_tree().create_timer(1.20).timeout
			sp._serve_customer_slot(2)
			sp._cust_slots[2].eat_t = 5.5
		"shield":
			Progress.set_active_meal_buff("supreme")
			menu.visible = false
			GameState.start_run(GameState.Mode.HARD)
			AudioManager.stop_bgm(0.0)
			AudioManager.set_bus_volumes(0.0, 1.0)
			autopilot.enabled = true
			director._wave_timer = 999.0
			await get_tree().create_timer(0.85).timeout
			# 精确锁定下一个木桶(LOW)障碍，临时让位让大水泡护盾迎面撞碎破盾且不减速！
			for _w in 240:
				await get_tree().process_frame
				if player.bubble_shield <= 0:
					break
				var cols := terrain.sample(player.global_position.x + 24.0, 5)
				var low_ahead := false
				for col_d: Dictionary in cols:
					if int(col_d["hazard"]) == TerrainPatterns.LOW:
						low_ahead = true
						break
				if low_ahead and not player.is_dashing():
					autopilot.enabled = false
					Input.action_release("jump")
					break
			await get_tree().create_timer(0.70).timeout
			autopilot.enabled = true
