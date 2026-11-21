extends Node
## AudioManager —— 全局音频管理、分轨总线（BGM / SFX）与双轨淡变 BGM 控制器。
##
## 特性：
##   · 独立总线：动态维护 Master → BGM（含水下低通滤波）与 SFX，互不干扰
##   · 双轨 BGM：A/B 双播放器无缝交叉淡入淡出（Crossfade），切曲零卡顿
##   · 水下滤波：暂停或死亡结算时平滑切入低通滤波 + 衰减，重开/恢复立即回亮
##   · SFX 池化：内置 12 个 AudioStreamPlayer，支持高频音效自然重叠与微音高抖动

const SFX_PATHS := {
	"jump": "res://audio/sfx/sfx_jump.wav",
	"heavy_land": "res://audio/sfx/sfx_heavy_land.ogg",
	"near_miss": "res://audio/sfx_near_miss.wav",
	"dash_ready": "res://audio/sfx_dash_ready.wav",
	"dash": "res://audio/sfx_dash.wav",
	"hit": "res://audio/sfx/sfx_hit.ogg",
	"fall": "res://audio/sfx/sfx_fall.ogg",
	"chase_warning": "res://audio/chase_warning.wav",
	"chase_heartbeat": "res://audio/chase_heartbeat.wav",
	"chase_bite": "res://audio/sfx/chase_bite.ogg",
	"ui_move": "res://audio/sfx/ui_move.wav",
	"ui_confirm": "res://audio/sfx/ui_confirm.wav",
	"intro_buildup": "res://audio/intro_buildup.wav",
	"intro_whoosh": "res://audio/intro_whoosh.wav",
	"intro_impact": "res://audio/intro_impact.wav",
}

const BGM_PATHS := {
	"menu": "res://audio/bgm/bgm_menu.mp3",
	"run": "res://audio/bgm/bgm_run.mp3",
	"chase": "res://audio/bgm/bgm_chase.ogg",
}

const BGM_BASE_DB := {
	"menu": -11.5,
	"run": -10.5,
	"chase": -10.5,
}

const BUS_BGM := "BGM"
const BUS_SFX := "SFX"
const POOL_SIZE := 12
const LPF_CLEAR_HZ := 20500.0
const SILENT_DB := -48.0

var _sfx_cache: Dictionary = {}
var _bgm_cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player_idx := 0

var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_active_is_a := true
var _bgm_key := ""
var _fade_tw: Tween
var _muffle_tw: Tween

var _bgm_bus_idx := -1
var _sfx_bus_idx := -1
var _bgm_lpf: AudioEffectLowPassFilter
var _bgm_user_linear := 0.8
var _sfx_user_linear := 0.8
var _bgm_duck_db := 0.0
var _bgm_muffled := false

var sfx_volume_db := 0.0
var sfx_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	_init_pool()
	_init_bgm_players()
	_preload_sfx()
	_preload_bgm()


func _exit_tree() -> void:
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = null
	if _muffle_tw != null and _muffle_tw.is_valid():
		_muffle_tw.kill()
	_muffle_tw = null
	stop_all()
	for p in _players:
		p.stop()
		p.stream = null
	if _bgm_a != null:
		_bgm_a.stop()
		_bgm_a.stream = null
		_bgm_a = null
	if _bgm_b != null:
		_bgm_b.stop()
		_bgm_b.stream = null
		_bgm_b = null
	_bgm_lpf = null
	if _sfx_bus_idx >= 0 and AudioServer.get_bus_index(BUS_SFX) >= 0:
		AudioServer.remove_bus(AudioServer.get_bus_index(BUS_SFX))
	if _bgm_bus_idx >= 0 and AudioServer.get_bus_index(BUS_BGM) >= 0:
		AudioServer.remove_bus(AudioServer.get_bus_index(BUS_BGM))
	_sfx_cache.clear()
	_bgm_cache.clear()


func ensure_buses() -> void:
	_bgm_bus_idx = AudioServer.get_bus_index(BUS_BGM)
	if _bgm_bus_idx < 0:
		_bgm_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bgm_bus_idx)
		AudioServer.set_bus_name(_bgm_bus_idx, BUS_BGM)
		AudioServer.set_bus_send(_bgm_bus_idx, "Master")

	if _bgm_lpf == null:
		for i in AudioServer.get_bus_effect_count(_bgm_bus_idx):
			var fx := AudioServer.get_bus_effect(_bgm_bus_idx, i)
			if fx is AudioEffectLowPassFilter:
				_bgm_lpf = fx as AudioEffectLowPassFilter
				break
		if _bgm_lpf == null:
			_bgm_lpf = AudioEffectLowPassFilter.new()
			_bgm_lpf.cutoff_hz = LPF_CLEAR_HZ
			_bgm_lpf.resonance = 0.55
			AudioServer.add_bus_effect(_bgm_bus_idx, _bgm_lpf, 0)
		AudioServer.set_bus_effect_enabled(_bgm_bus_idx, 0, false)

	_sfx_bus_idx = AudioServer.get_bus_index(BUS_SFX)
	if _sfx_bus_idx < 0:
		_sfx_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_sfx_bus_idx)
		AudioServer.set_bus_name(_sfx_bus_idx, BUS_SFX)
		AudioServer.set_bus_send(_sfx_bus_idx, "Master")


func set_bus_volumes(bgm_linear: float, sfx_linear: float) -> void:
	ensure_buses()
	_bgm_user_linear = clampf(bgm_linear, 0.0, 1.0)
	_sfx_user_linear = clampf(sfx_linear, 0.0, 1.0)
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, false)
		AudioServer.set_bus_volume_db(master_idx, 0.0)
	_apply_bgm_bus_gain()
	if _sfx_bus_idx >= 0:
		AudioServer.set_bus_mute(_sfx_bus_idx, _sfx_user_linear <= 0.005)
		AudioServer.set_bus_volume_db(_sfx_bus_idx, linear_to_db(maxf(_sfx_user_linear, 0.005)))


func _apply_bgm_bus_gain() -> void:
	if _bgm_bus_idx < 0:
		return
	AudioServer.set_bus_mute(_bgm_bus_idx, _bgm_user_linear <= 0.005)
	var user_db := linear_to_db(maxf(_bgm_user_linear, 0.005))
	AudioServer.set_bus_volume_db(_bgm_bus_idx, user_db + _bgm_duck_db)


func _init_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer_%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)


func _init_bgm_players() -> void:
	_bgm_a = AudioStreamPlayer.new()
	_bgm_a.name = "BgmPlayerA"
	_bgm_a.bus = BUS_BGM
	_bgm_a.volume_db = SILENT_DB
	add_child(_bgm_a)

	_bgm_b = AudioStreamPlayer.new()
	_bgm_b.name = "BgmPlayerB"
	_bgm_b.bus = BUS_BGM
	_bgm_b.volume_db = SILENT_DB
	add_child(_bgm_b)


func _preload_sfx() -> void:
	for key: String in SFX_PATHS:
		var path: String = SFX_PATHS[key]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				if stream is AudioStreamMP3:
					(stream as AudioStreamMP3).loop = false
				elif stream is AudioStreamOggVorbis:
					(stream as AudioStreamOggVorbis).loop = false
				_sfx_cache[key] = stream
		else:
			push_warning("[AudioManager] 未找到音效资源: %s" % path)


func _preload_bgm() -> void:
	for key: String in BGM_PATHS:
		var path: String = BGM_PATHS[key]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				if stream is AudioStreamMP3:
					(stream as AudioStreamMP3).loop = true
				elif stream is AudioStreamOggVorbis:
					(stream as AudioStreamOggVorbis).loop = true
				_bgm_cache[key] = stream
		else:
			push_warning("[AudioManager] 未找到音乐资源: %s" % path)


## 播放指定 BGM，自动与上一首做平滑交叉淡入淡出。
func play_bgm(key: String, fade_sec: float = 0.7) -> void:
	if not _bgm_cache.has(key):
		return
	var cur := _bgm_a if _bgm_active_is_a else _bgm_b
	var target_db := float(BGM_BASE_DB.get(key, -10.0))

	if _bgm_key == key and cur.playing:
		if _fade_tw != null and _fade_tw.is_valid():
			_fade_tw.kill()
		if fade_sec <= 0.01:
			cur.volume_db = target_db
		else:
			_fade_tw = create_tween()
			_fade_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_fade_tw.tween_property(cur, "volume_db", target_db, fade_sec).set_trans(Tween.TRANS_SINE)
		return

	var next := _bgm_b if _bgm_active_is_a else _bgm_a
	_bgm_active_is_a = not _bgm_active_is_a
	_bgm_key = key

	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()

	# Godot 无头模式下 AudioDriverDummy 退出时不排空仍在播放的长流 AudioStreamPlaybackMP3，仅更新状态即止
	if DisplayServer.get_name() == "headless":
		next.volume_db = target_db
		return

	next.stream = _bgm_cache[key]
	if fade_sec <= 0.01:
		cur.stop()
		next.volume_db = target_db
		next.play()
		return

	next.volume_db = SILENT_DB
	next.play()
	_fade_tw = create_tween()
	_fade_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tw.set_parallel(true)
	_fade_tw.tween_property(next, "volume_db", target_db, fade_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if cur.playing:
		_fade_tw.tween_property(cur, "volume_db", SILENT_DB, fade_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_fade_tw.chain().tween_callback(cur.stop)


## 平滑淡出并停止当前 BGM。
func stop_bgm(fade_sec: float = 0.35) -> void:
	_bgm_key = ""
	if _fade_tw != null and _fade_tw.is_valid():
		_fade_tw.kill()
	if fade_sec <= 0.01:
		if _bgm_a != null:
			_bgm_a.stop()
		if _bgm_b != null:
			_bgm_b.stop()
		return
	_fade_tw = create_tween()
	_fade_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tw.set_parallel(true)
	if _bgm_a != null and _bgm_a.playing:
		_fade_tw.tween_property(_bgm_a, "volume_db", SILENT_DB, fade_sec).set_trans(Tween.TRANS_SINE)
	if _bgm_b != null and _bgm_b.playing:
		_fade_tw.tween_property(_bgm_b, "volume_db", SILENT_DB, fade_sec).set_trans(Tween.TRANS_SINE)
	_fade_tw.chain().tween_callback(func() -> void:
		if _bgm_a != null:
			_bgm_a.stop()
		if _bgm_b != null:
			_bgm_b.stop()
	)


## 开关 BGM 水下低通滤波与音量柔降（用于暂停与死亡结算）。
func set_bgm_muffled(on: bool, duck_db: float = -6.0, cutoff_hz: float = 620.0, fade_sec: float = 0.25) -> void:
	ensure_buses()
	_bgm_muffled = on
	if _muffle_tw != null and _muffle_tw.is_valid():
		_muffle_tw.kill()

	var target_duck := duck_db if on else 0.0
	var target_hz := clampf(cutoff_hz, 200.0, LPF_CLEAR_HZ) if on else LPF_CLEAR_HZ

	if fade_sec <= 0.01:
		_bgm_duck_db = target_duck
		_apply_bgm_bus_gain()
		if _bgm_lpf != null:
			_bgm_lpf.cutoff_hz = target_hz
			AudioServer.set_bus_effect_enabled(_bgm_bus_idx, 0, on)
		return

	if _bgm_lpf != null:
		AudioServer.set_bus_effect_enabled(_bgm_bus_idx, 0, true)

	_muffle_tw = create_tween()
	_muffle_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_muffle_tw.set_parallel(true)
	_muffle_tw.tween_method(_set_bgm_duck_db, _bgm_duck_db, target_duck, fade_sec).set_trans(Tween.TRANS_SINE)
	if _bgm_lpf != null:
		_muffle_tw.tween_property(_bgm_lpf, "cutoff_hz", target_hz, fade_sec).set_trans(Tween.TRANS_SINE)
	if not on:
		_muffle_tw.chain().tween_callback(func() -> void:
			if not _bgm_muffled and _bgm_bus_idx >= 0:
				AudioServer.set_bus_effect_enabled(_bgm_bus_idx, 0, false)
		)


func _set_bgm_duck_db(v: float) -> void:
	_bgm_duck_db = v
	_apply_bgm_bus_gain()


func current_bgm_key() -> String:
	return _bgm_key


func is_bgm_muffled() -> bool:
	return _bgm_muffled


## 播放指定名字的短音效。
func play_sfx(name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sfx_enabled:
		return
	if not _sfx_cache.has(name):
		return

	var stream: AudioStream = _sfx_cache[name]
	var player: AudioStreamPlayer = _get_available_player()
	player.stream = stream
	player.volume_db = sfx_volume_db + vol_db
	player.pitch_scale = clampf(pitch, 0.5, 2.0)
	player.play()


## 带微随机音高抖动的音效播放（消除机械连续感，例如跳跃、滑行水流）
func play_sfx_pitched(name: String, vol_db: float = 0.0, pitch_var: float = 0.06) -> void:
	var p := randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	play_sfx(name, vol_db, p)


func _get_available_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	var p := _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % POOL_SIZE
	return p


## 仅停止当前所有短音效，不打断正在播放/淡变的 BGM。
func stop_sfx() -> void:
	for p in _players:
		if p.playing:
			p.stop()


## 停止所有正在播放的声音（含短音效与 BGM，如播放开场大片或退出游戏时）。
func stop_all() -> void:
	stop_sfx()
	stop_bgm(0.0)
