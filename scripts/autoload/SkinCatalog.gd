extends RefCounted
class_name SkinCatalog
## 成就与深海纪念画片配置表（单一数据源）。
##
## 局内始终采用经过精修打磨的默认深海女仆动作帧（res://sprites/run|jump|slide）；
## 5 张精抠高清立绘（sprites/skins/<id>/preview.png）保留为「成就图鉴」中的纪念画片。

const ARTWORKS := [
	{
		"id": "default",
		"name": "深海女仆",
		"desc": "经典蓝白女仆装，轻灵畅游深海的初始伙伴。",
		"preview": "res://sprites/skins/default/preview.png",
		"avatar": "res://sprites/skins/default/avatar.png",
		"unlock_achievements": 0,
		"playable": true,
		"sprite_dir": "res://sprites",
	},
	{
		"id": "cozy_knit",
		"name": "暖冬针织",
		"desc": "米白麻花毛衣搭配鲸鱼小挎包，温暖柔软的冬日私服。",
		"preview": "res://sprites/skins/cozy_knit/preview.png",
		"avatar": "res://sprites/skins/cozy_knit/avatar.png",
		"unlock_achievements": 3,
		"playable": true,
		"sprite_dir": "res://sprites/skins/cozy_knit",
	},
	{
		"id": "snow_cloak",
		"name": "雪夜冰晶",
		"desc": "深蓝绒领雪花斗篷配毛绒耳罩，如深海星雪般静谧。",
		"preview": "res://sprites/skins/snow_cloak/preview.png",
		"avatar": "res://sprites/skins/snow_cloak/avatar.png",
		"unlock_achievements": 6,
		"playable": false,
	},
	{
		"id": "academy_plaid",
		"name": "英伦学院",
		"desc": "藏青格纹报童帽与奶油白衬衫背带裙，轻快俏皮。",
		"preview": "res://sprites/skins/academy_plaid/preview.png",
		"avatar": "res://sprites/skins/academy_plaid/avatar.png",
		"unlock_achievements": 10,
		"playable": false,
	},
	{
		"id": "burger_crew",
		"name": "鲸堡店员",
		"desc": "红白条纹制服与点餐耳麦，深海全勤打工人的荣耀。",
		"preview": "res://sprites/skins/burger_crew/preview.png",
		"avatar": "res://sprites/skins/burger_crew/avatar.png",
		"unlock_achievements": 15,
		"playable": false,
	},
	{
		"id": "santa_cloak",
		"name": "圣夜铃铛",
		"desc": "红白绒边圣诞披风与铃铛结，献给甩尾大师的礼装。",
		"preview": "res://sprites/skins/santa_cloak/preview.png",
		"avatar": "res://sprites/skins/santa_cloak/avatar.png",
		"unlock_achievements": 20,
		"playable": false,
	},
]

const ACHIEVEMENTS := [
	{
		"id": "ach_dive_300m",
		"name": "初潜突围",
		"desc": "正常模式单局跑满 300 m",
		"reward_art": "",
		"tag": "历程",
		"stat": "best_run_dist_m",
		"target": 300,
		"unit": "m",
	},
	{
		"id": "ach_dive_600m",
		"name": "深海长泳",
		"desc": "正常模式单局跑满 600 m",
		"reward_art": "",
		"tag": "历程",
		"stat": "best_run_dist_m",
		"target": 600,
		"unit": "m",
	},
	{
		"id": "ach_dive_1500m",
		"name": "无底深潜者",
		"desc": "正常模式单局跑满 1500 m",
		"reward_art": "",
		"tag": "历程",
		"stat": "best_run_dist_m",
		"target": 1500,
		"unit": "m",
	},
	{
		"id": "ach_nohit_500m",
		"name": "无伤游侠",
		"desc": "正常模式单局零撞障跑满 500 m",
		"reward_art": "",
		"tag": "技巧",
		"stat": "best_no_hit_dist_m",
		"target": 500,
		"unit": "m",
	},
	{
		"id": "ach_nearmiss_20",
		"name": "贴脸舞者",
		"desc": "正常模式累计「擦身而过」20 次",
		"reward_art": "",
		"tag": "技巧",
		"stat": "total_near_misses",
		"target": 20,
		"unit": "次",
	},
	{
		"id": "ach_nearmiss_run_10",
		"name": "刀尖圆舞曲",
		"desc": "正常模式单局内触发「擦身而过」10 次",
		"reward_art": "",
		"tag": "技巧",
		"stat": "best_run_near_misses",
		"target": 10,
		"unit": "次",
	},
	{
		"id": "ach_nearmiss_100",
		"name": "浪尖舞王",
		"desc": "正常模式累计「擦身而过」100 次",
		"reward_art": "",
		"tag": "技巧",
		"stat": "total_near_misses",
		"target": 100,
		"unit": "次",
	},
	{
		"id": "ach_dash_15",
		"name": "深海疾风",
		"desc": "正常模式累计发动「冲刺」15 次",
		"reward_art": "",
		"tag": "技巧",
		"stat": "total_dashes",
		"target": 15,
		"unit": "次",
	},
	{
		"id": "ach_dash_50",
		"name": "涡轮鲸娘",
		"desc": "正常模式累计发动「冲刺」50 次",
		"reward_art": "",
		"tag": "技巧",
		"stat": "total_dashes",
		"target": 50,
		"unit": "次",
	},
	{
		"id": "ach_dash_run_8",
		"name": "极限推进",
		"desc": "正常模式单局内发动「冲刺」8 次",
		"reward_art": "",
		"tag": "技巧",
		"stat": "best_run_dashes",
		"target": 8,
		"unit": "次",
	},
	{
		"id": "ach_master_1000m_5dash",
		"name": "甩尾大师",
		"desc": "正常模式单局跑满 1000 m 且触发 5 次冲刺",
		"reward_art": "",
		"tag": "技巧",
		"stat": "combo_1000m_5dash",
		"target": 1000,
		"sub_target": 5,
		"unit": "m",
	},
	{
		"id": "ach_chase_escape_1",
		"name": "鲸口逃生",
		"desc": "正常模式首次成功摆脱黑鲸娘追击",
		"reward_art": "",
		"tag": "追击",
		"stat": "total_chases_survived",
		"target": 1,
		"unit": "次",
	},
	{
		"id": "ach_chase_escape_5",
		"name": "追逐大师",
		"desc": "正常模式累计摆脱黑鲸娘追击 5 次",
		"reward_art": "",
		"tag": "追击",
		"stat": "total_chases_survived",
		"target": 5,
		"unit": "次",
	},
	{
		"id": "ach_runs_10",
		"name": "深海常客",
		"desc": "正常模式累计完成跑酷 10 局",
		"reward_art": "",
		"tag": "历程",
		"stat": "total_runs",
		"target": 10,
		"unit": "局",
	},
	{
		"id": "ach_runs_30",
		"name": "不倦旅鱼",
		"desc": "正常模式累计完成跑酷 30 局",
		"reward_art": "",
		"tag": "历程",
		"stat": "total_runs",
		"target": 30,
		"unit": "局",
	},
	{
		"id": "ach_total_5000m",
		"name": "全勤打工鱼",
		"desc": "正常模式累计奔跑 5000 m",
		"reward_art": "",
		"tag": "历程",
		"stat": "total_dist_m",
		"target": 5000,
		"unit": "m",
	},
	{
		"id": "ach_total_15000m",
		"name": "深海马拉松",
		"desc": "正常模式累计奔跑 15000 m",
		"reward_art": "",
		"tag": "历程",
		"stat": "total_dist_m",
		"target": 15000,
		"unit": "m",
	},
	{
		"id": "ach_easter_caught",
		"name": "美味大肥鱼",
		"desc": "首次在正常模式被黑鲸娘追上咬住",
		"reward_art": "",
		"tag": "彩蛋",
		"stat": "caught_count",
		"target": 1,
		"unit": "次",
	},
	{
		"id": "ach_easter_chasm",
		"name": "深渊观光客",
		"desc": "正常模式累计坠入断崖深渊 10 次",
		"reward_art": "",
		"tag": "彩蛋",
		"stat": "chasm_count",
		"target": 10,
		"unit": "次",
	},
	{
		"id": "ach_easter_wall",
		"name": "海底散步家",
		"desc": "首次在正常模式被后方死亡边界吞没",
		"reward_art": "",
		"tag": "彩蛋",
		"stat": "wall_count",
		"target": 1,
		"unit": "次",
	},
]


static func get_artwork(art_id: String) -> Dictionary:
	for a: Dictionary in ARTWORKS:
		if String(a["id"]) == art_id:
			return a
	return ARTWORKS[0]


static func get_skin_required_achievements(art_id: String) -> int:
	return int(get_artwork(art_id).get("unlock_achievements", 0))


static func is_skin_playable(art_id: String) -> bool:
	return bool(get_artwork(art_id).get("playable", false))


static func get_artwork_sprite_dir(art_id: String) -> String:
	var art := get_artwork(art_id)
	if not bool(art.get("playable", false)):
		return "res://sprites"
	return String(art.get("sprite_dir", "res://sprites"))


static func get_achievement(ach_id: String) -> Dictionary:
	for a: Dictionary in ACHIEVEMENTS:
		if String(a["id"]) == ach_id:
			return a
	return {}
