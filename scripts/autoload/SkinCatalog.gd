extends RefCounted
class_name SkinCatalog
## 成就与深海纪念画片配置表（单一数据源）。
##
## 局内始终采用经过精修打磨的默认深海女仆动作帧（res://sprites/run|jump|slide）；
## 6 张精抠高清立绘（sprites/skins/<id>/preview.png）保留为「成就图鉴」中的纪念画片。

const ARTWORKS := [
	{
		"id": "default",
		"name": "深海女仆",
		"desc": "经典蓝白女仆装，轻灵畅游深海的初始伙伴。",
		"preview": "res://sprites/skins/default/preview.png",
	},
	{
		"id": "cozy_knit",
		"name": "暖冬针织",
		"desc": "米白麻花毛衣搭配鲸鱼小挎包，温暖柔软的冬日私服。",
		"preview": "res://sprites/skins/cozy_knit/preview.png",
	},
	{
		"id": "snow_cloak",
		"name": "雪夜冰晶",
		"desc": "深蓝绒领雪花斗篷配毛绒耳罩，如深海星雪般静谧。",
		"preview": "res://sprites/skins/snow_cloak/preview.png",
	},
	{
		"id": "academy_plaid",
		"name": "英伦学院",
		"desc": "藏青格纹报童帽与奶油白衬衫背带裙，轻快俏皮。",
		"preview": "res://sprites/skins/academy_plaid/preview.png",
	},
	{
		"id": "santa_cloak",
		"name": "圣夜铃铛",
		"desc": "红白绒边圣诞披风与铃铛结，献给甩尾大师的礼装。",
		"preview": "res://sprites/skins/santa_cloak/preview.png",
	},
]

const ACHIEVEMENTS := [
	{
		"id": "ach_dive_300m",
		"name": "初潜突围",
		"desc": "正常模式单局跑满 300 m",
		"reward_art": "cozy_knit",
		"stat": "best_run_dist_m",
		"target": 300,
		"unit": "m",
	},
	{
		"id": "ach_nearmiss_20",
		"name": "贴脸舞者",
		"desc": "正常模式累计「擦身而过」20 次",
		"reward_art": "snow_cloak",
		"stat": "total_near_misses",
		"target": 20,
		"unit": "次",
	},
	{
		"id": "ach_dash_15",
		"name": "深海疾风",
		"desc": "正常模式累计发动「冲刺」15 次",
		"reward_art": "academy_plaid",
		"stat": "total_dashes",
		"target": 15,
		"unit": "次",
	},
	{
		"id": "ach_master_1000m_5dash",
		"name": "甩尾大师",
		"desc": "正常模式单局跑满 1000 m 且触发 5 次冲刺",
		"reward_art": "santa_cloak",
		"stat": "combo_1000m_5dash",
		"target": 1000,
		"sub_target": 5,
		"unit": "m",
	},
	{
		"id": "ach_easter_caught",
		"name": "美味大肥鱼",
		"desc": "首次在正常模式被黑鲸娘追上咬住",
		"reward_art": "",
		"stat": "caught_count",
		"target": 1,
		"unit": "次",
	},
	{
		"id": "ach_easter_chasm",
		"name": "深渊观光客",
		"desc": "正常模式累计坠入断崖深渊 10 次",
		"reward_art": "",
		"stat": "chasm_count",
		"target": 10,
		"unit": "次",
	},
	{
		"id": "ach_easter_wall",
		"name": "海底散步家",
		"desc": "首次在正常模式被后方死亡边界吞没",
		"reward_art": "",
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


static func get_achievement(ach_id: String) -> Dictionary:
	for a: Dictionary in ACHIEVEMENTS:
		if String(a["id"]) == ach_id:
			return a
	return {}
