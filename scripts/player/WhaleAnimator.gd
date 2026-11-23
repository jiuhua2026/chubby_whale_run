extends RefCounted
class_name WhaleAnimator
## 加载 sprites/ 下已切好的帧序列与 JSON 锚点数据，并驱动播放。
##
## 锚点的用法（这是整条流水线的落点）：
##   每个 JSON 里每帧带 anchorX / anchorY，表示「角色参考点」在该帧图像内的位置
##   （X = 头部水平中心，Y = 该行带的地面线）。
##   把 Sprite2D.offset 设成 (w/2 - anchorX, h/2 - anchorY) 之后，
##   角色的参考点就精确落在节点原点上。于是：
##     player.global_position = 脚底中心在屏幕上的位置
##   引擎只需要控制一个点，不用管每帧图不一样大、不同动作比例不同。

const BASE := "res://sprites"
const ACTIONS := ["run", "jump", "slide"]

var clips := {}          ## action -> Array[{"tex":Texture2D,"ax":float,"ay":float,"h":float}]
## action -> 该 clip 所有帧高的中位数。
## 「帧身高统一」靠它把每帧缩放到同样的显示高度（见 GameConfig.anim_uniform_height）。
var clip_h_med := {}
var loaded := false
var load_errors: Array[String] = []

var _sprite: Sprite2D
var _scale := 1.0
var _skin_id := "default"
var _action := ""
var _index := 0.0
var _time_acc := 0.0
## 当前实际播放帧率，供 F3 诊断用。
## 跑步动画的帧率是「速度 × 帧数 / run_cycle_px」算出来的，
## 手感和打滑问题基本都出在这个数上，所以要能随时看到它。
var last_fps := 0.0
## 吸附前的原始帧率。和 last_fps 一起显示成 `原始→吸附`，
## 这样才能看出吸附到底改了多少 —— 差值大说明 run_cycle_px 选得不好。
var last_fps_raw := 0.0


func setup(sprite: Sprite2D, char_scale: float, skin_id: String = "default") -> void:
	_sprite = sprite
	_scale = char_scale
	_skin_id = skin_id if SkinCatalog.is_skin_playable(skin_id) else "default"
	_sprite.scale = Vector2(_scale, _scale)
	load_all()


func set_skin(skin_id: String) -> void:
	var target := skin_id if SkinCatalog.is_skin_playable(skin_id) else "default"
	if target == _skin_id and loaded:
		return
	_skin_id = target
	load_all()
	if _action != "" and has_clip(_action):
		_index = 0.0
		_time_acc = 0.0
		_apply(0)


func load_all() -> void:
	clips.clear()
	clip_h_med.clear()
	load_errors.clear()
	var skin_base := SkinCatalog.get_artwork_sprite_dir(_skin_id)
	for a in ACTIONS:
		var dir_path := "%s/%s" % [skin_base, a]
		var json_path := "%s/%s.json" % [dir_path, a]
		if not FileAccess.file_exists(json_path) and skin_base != BASE:
			dir_path = "%s/%s" % [BASE, a]
			json_path = "%s/%s.json" % [dir_path, a]
		if not FileAccess.file_exists(json_path):
			load_errors.append("缺少 %s" % json_path)
			continue
		var f := FileAccess.open(json_path, FileAccess.READ)
		if f == null:
			load_errors.append("打不开 %s" % json_path)
			continue
		var meta: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(meta) != TYPE_DICTIONARY or not meta.has("frames"):
			load_errors.append("%s 解析失败" % json_path)
			continue
		var arr: Array = []
		var heights: Array[float] = []
		for fr in meta["frames"]:
			var png := "%s/%s" % [dir_path, fr["file"]]
			if not ResourceLoader.exists(png):
				load_errors.append("缺少帧图 %s" % png)
				continue
			var tex: Texture2D = load(png)
			var th := float(tex.get_height())
			heights.append(th)
			arr.append({
				"tex": tex,
				"ax": float(fr["anchorX"]),
				"ay": float(fr["anchorY"]),
				"h": th,
			})
		if arr.is_empty():
			load_errors.append("%s 没有可用帧" % json_path)
			continue
		clips[a] = arr
		clip_h_med[a] = _median(heights)
	loaded = load_errors.is_empty() and clips.size() == ACTIONS.size()
	for e in load_errors:
		push_warning("[WhaleAnimator] " + e)


## 中位数。用它而不是平均值，是因为这份素材里有明显的离群帧
## （例如第 8 帧高 137，邻居都在 127~133），平均值会被它带偏。
func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	@warning_ignore("integer_division")
	var m := s.size() / 2
	if s.size() % 2 == 1:
		return float(s[m])
	return (float(s[m - 1]) + float(s[m])) * 0.5


func has_clip(a: String) -> bool:
	return clips.has(a) and clips[a].size() > 0


func current_action() -> String:
	return _action


func current_index() -> int:
	return int(_index)


func frame_count(a: String) -> int:
	return clips[a].size() if has_clip(a) else 0


## 播放。loop_index 为 -1 表示自动循环；否则强制显示该帧（跳跃用）。
## fps_raw 只用于诊断显示（吸附前的原始值），不参与播放。
func play(a: String, delta: float, fps: float, loop_index: int = -1,
		fps_raw: float = -1.0) -> void:
	if not has_clip(a):
		return
	var clip: Array = clips[a]
	if a != _action:
		_action = a
		_index = 0.0
		_time_acc = 0.0

	if loop_index >= 0:
		_index = float(clampi(loop_index, 0, clip.size() - 1))
		last_fps = 0.0
		last_fps_raw = 0.0
	else:
		last_fps = fps
		last_fps_raw = fps if fps_raw < 0.0 else fps_raw
		_time_acc += delta * maxf(fps, 0.01)
		while _time_acc >= 1.0:
			_time_acc -= 1.0
			_index = fmod(_index + 1.0, float(clip.size()))

	_apply(clampi(int(_index), 0, clip.size() - 1))


func _apply(i: int) -> void:
	var clip: Array = clips[_action]
	var fr: Dictionary = clip[i]
	var tex: Texture2D = fr["tex"]
	_sprite.texture = tex
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	# 「帧身高统一」：把每帧缩放到同一显示高度，让头顶和脚底同时钉住。
	# 缩放围绕节点原点进行，而锚点恰好落在原点，所以锚点对齐不会被破坏；
	# 下面的 offset 是缩放前的局部像素单位，先算好即可。
	var sc := _scale
	if GameConfig.anim_uniform_height \
			and GameConfig.anim_uniform_height_actions.has(_action) \
			and clip_h_med.has(_action):
		var hm := float(clip_h_med[_action])
		if hm > 0.0 and h > 0.0:
			sc *= hm / h
	_sprite.scale = Vector2(sc, sc)
	# 让 (ax, ay) 这个点落在节点原点（也就是角色的锚点位置）。
	# 再叠加一个整体微调：AI 稿的个别帧总有偏差，逐帧对齐也修不干净，
	# 留一个整体位移的口子，用 ; ' 键热调。
	var lift := 0.0
	if GameConfig.anim_y_offset.has(_action):
		lift = float(GameConfig.anim_y_offset[_action])
	_sprite.offset = Vector2(w * 0.5 - float(fr["ax"]),
		h * 0.5 - float(fr["ay"]) - lift)
