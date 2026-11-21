extends Node
## 玩家设置：持久化到 `user://settings.cfg`，启动时自动应用。
##
## ## 只放"真的能生效"的开关
## 现在项目里能接到实际系统的只有三样：Master 总线音量、窗口显示模式、屏幕震动幅度。
## 分辨率列表 / 画质 / 语言这些**没有对应系统**，做了就是假开关 —— 比没有更伤"像个正常游戏"。
##
## ## 为什么不改 `GameConfig`
## `chase_shake_px` 等是 `const`，改了会污染"设计值"。这里只存**倍率**，
## 由 `Main` 在算震幅时乘上去 ⇒ 设计值永远是 1.0 的那一档。

const PATH := "user://settings.cfg"

## 音乐与音效音量 0~1（分别映射到 AudioServer 的 BGM / SFX 总线：0 ⇒ 静音，1 ⇒ 0dB）
var bgm_volume := 0.8
var sfx_volume := 0.8
## 屏幕震动倍率（0 / 0.5 / 1.0）
var shake_scale := 1.0
## 是否全屏
var fullscreen := false
## 开场动画是否已完整看过/跳过（仅首次启动自动播放）
var intro_seen := false
## 通过设置面板重温开场的累计次数（用于顺序轮播吐槽彩蛋，避免连续重样）
var intro_replay_count := 0
## 正常模式本地最高纪录
var best_distance_m := 0
var best_score := 0
## 自动化自检/抓帧时由 Main 关闭写盘，避免测试数据污染真实存档
var record_save_enabled := true


func _ready() -> void:
	load_cfg()
	apply_all()


func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return          # 第一次运行：用默认值
	var legacy := clampf(float(cf.get_value("audio", "volume", 0.8)), 0.0, 1.0)
	bgm_volume = clampf(float(cf.get_value("audio", "bgm_volume", legacy)), 0.0, 1.0)
	sfx_volume = clampf(float(cf.get_value("audio", "sfx_volume", legacy)), 0.0, 1.0)
	shake_scale = clampf(float(cf.get_value("video", "shake_scale", shake_scale)), 0.0, 1.0)
	fullscreen = bool(cf.get_value("video", "fullscreen", fullscreen))
	intro_seen = bool(cf.get_value("intro", "seen", intro_seen))
	intro_replay_count = maxi(0, int(cf.get_value("intro", "replay_count", intro_replay_count)))
	best_distance_m = maxi(0, int(cf.get_value("records", "best_distance_m", best_distance_m)))
	best_score = maxi(0, int(cf.get_value("records", "best_score", best_score)))


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "bgm_volume", bgm_volume)
	cf.set_value("audio", "sfx_volume", sfx_volume)
	cf.set_value("video", "shake_scale", shake_scale)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("intro", "seen", intro_seen)
	cf.set_value("intro", "replay_count", intro_replay_count)
	cf.set_value("records", "best_distance_m", best_distance_m)
	cf.set_value("records", "best_score", best_score)
	cf.save(PATH)


## 尝试刷新正常模式最高纪录，返回是否刷新距离/得分；自动化测试期间不写盘。
func update_records(dist_m: int, p_score: int) -> Dictionary:
	var new_dist := dist_m > best_distance_m
	var new_score := p_score > best_score
	if not record_save_enabled:
		return {"new_dist": false, "new_score": false}
	if new_dist:
		best_distance_m = dist_m
	if new_score:
		best_score = p_score
	if new_dist or new_score:
		save_cfg()
	return {"new_dist": new_dist, "new_score": new_score}


func apply_all() -> void:
	apply_volume()
	apply_display()


func apply_volume() -> void:
	# ⚠ 走**分轨总线音量**，拖动滑条时正在播放的 BGM/SFX 都会实时响应。
	AudioManager.set_bus_volumes(bgm_volume, sfx_volume)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return          # 自检/抓帧时没有真窗口，切模式会报错
	var want: int = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
