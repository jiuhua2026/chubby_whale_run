extends RefCounted
class_name ShopCatalog
## 深海鲸堡小店菜谱、纯海洋顾客、厨具与店铺升级配置（单一数据源）。

const DISHES := [
	{
		"id": "burger",
		"name": "脆藻双层堡",
		"icon": "res://sprites/shop/dish_burger.png",
		"station": "fryer",
		"cost": {"kelp": 1, "seaweed": 1},
		"price": 18,
		"cook_sec": 3.1,
		"buff_id": "shield",
		"buff_name": "防撞护体",
		"buff_desc": "下局开局自带 1 层水泡护盾，抵消 1 次碰障减速",
	},
	{
		"id": "fries",
		"name": "海苔咔嚓长条",
		"icon": "res://sprites/shop/dish_fries.png",
		"station": "fryer",
		"cost": {"nori": 1},
		"price": 12,
		"cook_sec": 2.8,
		"buff_id": "power_dash",
		"buff_name": "冲刺增压",
		"buff_desc": "下局 Space 冲刺冲击波对一阶段黑鲸娘造成 2 格伤害",
	},
	{
		"id": "nuggets",
		"name": "海藻脆脆块",
		"icon": "res://sprites/shop/dish_nuggets.png",
		"station": "fryer",
		"cost": {"seaweed": 1},
		"price": 14,
		"cook_sec": 2.8,
		"buff_id": "fast_charge",
		"buff_name": "快充势能",
		"buff_desc": "下局擦身势能上限降为 2 格，更快攒满 Space 冲刺",
	},
	{
		"id": "wrap",
		"name": "双拼海带海草卷",
		"icon": "res://sprites/shop/dish_wrap.png",
		"station": "board",
		"cost": {"kelp": 1, "nori": 1, "seaweed": 1},
		"price": 28,
		"cook_sec": 3.1,
		"buff_id": "streamline",
		"buff_name": "流线身法",
		"buff_desc": "下局滑铲更轻快，碰障后的速度恢复更快",
	},
	{
		"id": "soda",
		"name": "星光藻皇特饮",
		"icon": "res://sprites/shop/dish_soda.png",
		"station": "soda",
		"cost": {"seaweed": 1, "star_algae": 1},
		"price": 52,
		"cook_sec": 3.3,
		"buff_id": "star_luck",
		"buff_name": "星光眷顾",
		"buff_desc": "下局二阶段星光藻掉率提至 22%，且跑酷得分 +20%",
	},
	{
		"id": "supreme",
		"name": "星光海藻至尊堡",
		"icon": "res://sprites/shop/dish_supreme.png",
		"station": "board",
		"cost": {"kelp": 1, "nori": 1, "seaweed": 1, "star_algae": 1},
		"price": 72,
		"cook_sec": 3.6,
		"buff_id": "supreme_surge",
		"buff_name": "王牌深潜",
		"buff_desc": "下局自带 1 层水泡护盾 + 冲刺时长延长至 1.35 秒",
	},
]

const STATIONS := {
	"fryer": {
		"name": "酥炸锅",
		"desc": "汉堡 / 长条 / 脆脆块",
		"tex_0": "res://sprites/shop/station_fryer_1.png",
		"tex_1": "res://sprites/shop/station_fryer_2.png",
	},
	"board": {
		"name": "组装板",
		"desc": "海草卷 / 至尊堡",
		"tex_0": "res://sprites/shop/station_board.png",
	},
	"soda": {
		"name": "气泡饮机",
		"desc": "星光藻皇特饮",
		"tex_0": "res://sprites/shop/station_soda.png",
	},
}

const CUSTOMERS := [
	{
		"id": "seahorse",
		"name": "打工小海马",
		"wait_tex": "res://sprites/shop/cust_seahorse_wait.png",
		"eat_tex": "res://sprites/shop/cust_seahorse_eat.png",
		"slot": "window",
		"seat_slot": 0,
		"seat_pos": Vector2(98, 258),
		"seat_size": Vector2(130, 130),
		"preferred": ["fries", "wrap", "nuggets"],
		"patience": 28.0,
		"tip_mult": 1.0,
		"lines_wait": ["赶着回珊瑚工位，来份快餐带走！", "脆一点，最好带金脆光泽~"],
		"lines_eat": ["太香啦！噗噜噜回工位咯~", "满分脆度！明天继续冲！"],
	},
	{
		"id": "turtle",
		"name": "海龟爷爷",
		"wait_tex": "res://sprites/shop/cust_turtle_wait.png",
		"eat_tex": "res://sprites/shop/cust_turtle_eat.png",
		"slot": "booth",
		"seat_slot": 1,
		"seat_pos": Vector2(742, 290),
		"seat_size": Vector2(144, 144),
		"preferred": ["burger", "wrap"],
		"patience": 42.0,
		"tip_mult": 1.10,
		"lines_wait": ["不急不急，小店主慢慢做就好~", "老伴让我也尝尝鲸堡招牌菜。"],
		"lines_eat": ["嗯~ 外酥里嫩，牙口真享福！", "慢火好味道，给小店点个赞！"],
	},
	{
		"id": "jelly",
		"name": "水母姐妹",
		"wait_tex": "res://sprites/shop/cust_jelly_wait.png",
		"eat_tex": "res://sprites/shop/cust_jelly_eat.png",
		"slot": "booth",
		"seat_slot": 1,
		"seat_pos": Vector2(742, 272),
		"seat_size": Vector2(142, 142),
		"preferred": ["nuggets", "soda", "fries"],
		"patience": 32.0,
		"tip_mult": 1.15,
		"lines_wait": ["想要能两个人分着吃的香脆小吃~", "飘呀飘~ 这边好香呀！"],
		"lines_eat": ["发光啦！！Biu~✨", "姐妹干杯！这口脆得像星星！"],
	},
	{
		"id": "shark",
		"name": "锤头鲨大叔",
		"wait_tex": "res://sprites/shop/cust_shark_wait.png",
		"eat_tex": "res://sprites/shop/cust_shark_eat.png",
		"slot": "booth",
		"seat_slot": 2,
		"seat_pos": Vector2(1012, 290),
		"seat_size": Vector2(156, 156),
		"preferred": ["burger", "soda", "supreme", "fries"],
		"patience": 34.0,
		"tip_mult": 1.35,
		"lines_wait": ["刚巡海锻炼完，挑你们硬菜上！", "别看我凶，其实超爱吃酥炸海藻！"],
		"lines_eat": ["呜哇！！墨镜都要感动飞啦！！", "太顶了！下次带整队朋友来！"],
	},
	{
		"id": "blackwhale",
		"name": "乔装黑鲸娘",
		"wait_tex": "res://sprites/shop/cust_blackwhale_wait.png",
		"eat_tex": "res://sprites/shop/cust_blackwhale_eat.png",
		"slot": "booth",
		"seat_slot": 2,
		"seat_pos": Vector2(1016, 304),
		"seat_size": Vector2(142, 142),
		"preferred": ["fries", "supreme", "burger"],
		"patience": 30.0,
		"tip_mult": 2.0,
		"lines_wait": ["……只是顺路视察对手的伙食水准。", "别盯着我尾巴，快上菜就是了！"],
		"lines_wait_crew": ["（盯）穿这身红白制服还挺人模鱼样的嘛…", "哼，别以为戴个遮阳帽我就吃你这一套！"],
		"lines_eat": ["（嚼嚼）…勉强算、算是全深海第二好吃吧！", "这双倍贝壳币是封口费，不准告诉别人我来过！"],
	},
]

const UPGRADES := [
	{
		"id": "fryer",
		"name": "厨房炸锅升级",
		"max_lv": 2,
		"costs": [60, 140],
		"descs": [
			"升至双联恒温炸锅：可同时烹饪 2 份油炸菜，金脆完美区大幅拓宽",
			"升至大师金脆双锅：金脆区扩至半程超好拍中，全金脆菜品售价再 +15%",
		],
	},
	{
		"id": "decor",
		"name": "店面珊瑚装潢",
		"max_lv": 2,
		"costs": [50, 120],
		"descs": [
			"暖光珊瑚雅座：全菜品小费 +15%，锤头鲨稀客更快常驻光顾",
			"金牌霓虹鲸堡：全菜品小费 +30%，顾客耐心 +20%，黑鲸娘高频微服私访",
		],
	},
	{
		"id": "cooler",
		"name": "深海鲸尾兜扩容",
		"max_lv": 3,
		"costs": [45, 85, 140],
		"descs": [
			"跑酷常规植物格 9 → 11 格（总计 12 格含星光藻）",
			"跑酷常规植物格 11 → 13 格（总计 14 格含星光藻）",
			"跑酷常规植物格 13 → 15 格（总计 16 格满配保鲜）",
		],
	},
]


static func get_dish(dish_id: String) -> Dictionary:
	for d: Dictionary in DISHES:
		if String(d["id"]) == dish_id:
			return d
	return {}


static func get_customer(cust_id: String) -> Dictionary:
	for c: Dictionary in CUSTOMERS:
		if String(c["id"]) == cust_id:
			return c
	return CUSTOMERS[0]


static func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	var order := [
		["kelp", "带"],
		["nori", "菜"],
		["seaweed", "藻"],
		["star_algae", "星"],
	]
	for pair in order:
		var k := String(pair[0])
		var cnt := int(cost.get(k, 0))
		if cnt > 0:
			parts.append("%s%d" % [String(pair[1]), cnt])
	return " ".join(parts)
