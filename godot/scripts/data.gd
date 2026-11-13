class_name Data
extends RefCounted

## 全局数据层 —— 关卡/敌人/Boss/武器全部数据化（与原作解析文档的名册对应）
## 关卡：玩家从 z=26 向 -Z 推进；spawns=[推进米数, 类型, 横向偏移]

## 版本号单一出处：主菜单显示它，每次发版只改这一处
const VERSION := "1.0.0"

const PLAYER := {
	"height": 1.7, "prone_height": 0.55, "radius": 0.38,
	"walk_speed": 7.5, "run_speed": 11.5, "prone_speed": 3.2,
	"jump_velocity": 7.4, "gravity": 19.0,
	"max_cells": 3, "start_lives": 3, "extend_score": 10000,
	"hit_invuln": 0.9, "respawn_invuln": 1.5,
}

const CAMERA := {
	"distance": 5.2, "aim_distance": 3.2, "shoulder": 0.9, "height": 0.55,
	"target_height": 1.45, "target_height_prone": 0.5,
	"pitch_min": -0.6, "pitch_max": 1.05, "smooth": 9.0, "collision_pad": 0.35,
}

const WEAPONS := {
	"N": {"name": "步枪", "letter": "N", "damage": 34, "fire_rate": 0.16, "bullet_speed": 95.0, "pellets": 1, "spread": 0.006, "color": Color(1, 0.88, 0.54), "pierce": false, "wave": false},
	"M": {"name": "机枪", "letter": "M", "damage": 30, "fire_rate": 0.075, "bullet_speed": 95.0, "pellets": 1, "spread": 0.012, "color": Color(0.48, 0.78, 1), "pierce": false, "wave": false},
	"F": {"name": "火球枪", "letter": "F", "damage": 55, "fire_rate": 0.22, "bullet_speed": 55.0, "pellets": 1, "spread": 0.0, "color": Color(1, 0.48, 0.2), "pierce": true, "wave": true},
	"L": {"name": "激光枪", "letter": "L", "damage": 46, "fire_rate": 0.13, "bullet_speed": 240.0, "pellets": 1, "spread": 0.0, "color": Color(1, 0.3, 0.43), "pierce": true, "wave": false},
	"S": {"name": "散射枪", "letter": "S", "damage": 26, "fire_rate": 0.24, "bullet_speed": 85.0, "pellets": 5, "spread": 0.16, "color": Color(0.66, 1, 0.48), "pierce": false, "wave": false},
}
const RAPID_FACTOR := 0.62

## 敌人名册（原作官方名）：rifleman=Ledder突枪射击兵 runner=Greeder红衣突击兵
## mortar=榴弹兵 garth=装甲机动步兵 langel=装甲猎步兵 akbar=突击水兵
## roller=Daru电光自走弹 spore=Bugger把妖虫 tank=Dogra重装甲扫讨车 statue=喷火石像
const ENEMIES := {
	"rifleman": {"hp": 30, "speed": 0.0, "radius": 0.5, "score": 100, "fire_interval": 1.7, "orb_speed": 17.0, "range": 46.0},
	"runner": {"hp": 30, "speed": 5.0, "radius": 0.5, "score": 150, "melee_range": 1.7, "melee_cooldown": 0.9},
	"sniper": {"hp": 30, "speed": 0.0, "radius": 0.5, "score": 300, "fire_interval": 2.4, "orb_speed": 27.0, "range": 60.0},
	"mortar": {"hp": 30, "speed": 0.0, "radius": 0.55, "score": 250, "fire_interval": 3.1, "orb_speed": 0.0, "range": 52.0},
	"garth": {"hp": 30, "speed": 0.0, "radius": 0.55, "score": 300, "fire_interval": 2.0, "orb_speed": 19.0, "range": 46.0},
	"langel": {"hp": 30, "speed": 0.0, "radius": 0.55, "score": 250, "fire_interval": 1.9, "orb_speed": 20.0, "range": 48.0},
	"akbar": {"hp": 30, "speed": 0.0, "radius": 0.5, "score": 200, "fire_interval": 2.2, "orb_speed": 18.0, "range": 40.0},
	"bomber": {"hp": 30, "speed": 0.0, "radius": 0.55, "score": 200, "fire_interval": 2.9, "orb_speed": 0.0, "range": 36.0},
	"shield": {"hp": 30, "speed": 2.2, "radius": 0.55, "score": 250, "fire_interval": 3.0, "orb_speed": 17.0, "range": 40.0},
	"statue": {"hp": 272, "speed": 0.0, "radius": 0.8, "score": 250, "fire_interval": 3.0, "orb_speed": 0.0, "range": 50.0},
	"turret": {"hp": 272, "speed": 0.0, "radius": 0.85, "score": 200, "fire_interval": 0.42, "burst": 3, "burst_pause": 1.5, "orb_speed": 18.0, "range": 44.0},
	"roller": {"hp": 170, "speed": 6.0, "radius": 0.45, "score": 100, "explode_range": 1.9},
	"spore": {"hp": 68, "speed": 4.6, "radius": 0.42, "score": 150, "melee_range": 1.5, "melee_cooldown": 0.8},
	"tank": {"hp": 340, "speed": 2.2, "radius": 1.9, "score": 1500, "fire_interval": 1.1, "orb_speed": 19.0, "range": 46.0},
}

## 敌人图鉴（日版说明书名册；只写名字与外形，绝不写弱点/打法——用户红线）
const BESTIARY := {
	"rifleman": {"name": "Ledder 突枪射击兵", "desc": "黄色头盔、丛林迷彩，左臂佩猩红臂章，端着一支步枪。"},
	"runner": {"name": "Greeder 突击兵", "desc": "一身红衣红裤，头系红巾，脚步极快。"},
	"sniper": {"name": "狙击兵", "desc": "紫色衣装，伏在高处，枪身细长、带着瞄准镜。"},
	"mortar": {"name": "迫击炮兵", "desc": "橙色头盔，蹲在迫击炮位后，炮管高高扬起。"},
	"bomber": {"name": "掷弹兵", "desc": "通身重甲，脸上扣着一副防毒面具，手里总掂着一颗手雷。"},
	"shield": {"name": "盾牌兵", "desc": "高举一面厚重的钢铁大盾，盾面正中一颗铆钉圆头，缓步压上前来。"},
	"akbar": {"name": "Akbar 突击水兵", "desc": "只露出水面的头与枪口，水下身形一片模糊。"},
	"garth": {"name": "Gals 加尔斯", "desc": "重甲覆体，面甲下透着幽光，左臂佩猩红臂章。"},
	"langel": {"name": "Langell 兰格尔", "desc": "白色头盔与衣装，老兵模样，持枪姿态沉稳。"},
	"turret": {"name": "自动炮台", "desc": "钢铁基座上架着粗大的炮管，炮身覆盖装甲板。"},
	"roller": {"name": "Daru 电光自走弹", "desc": "圆滚滚的金属球体，表面电光滋滋作响。"},
	"spore": {"name": "Bugger 把妖虫", "desc": "从妖卵中孵出的飞行怪虫，翅膜透着暗绿。"},
	"statue": {"name": "石像守卫", "desc": "布满苔痕的巨大石像，眼窝深陷，面目狰狞。"},
	"tank": {"name": "Dogra 重装甲扫讨车", "desc": "厚重的装甲车体，炮塔低矮，履带宽阔。"},
}

const BOSSES := {
	"defenseWall": {"name": "防御壁", "score": 3000},
	"baseCore": {"name": "独炎眼·加尔马基尔马", "score": 4000},
	"gromaides": {"name": "阴兽魔神像·古罗马伊德斯", "score": 5000},
	"godomuga": {"name": "分幻鬼·戈多姆加", "score": 6000},
	"guldaf": {"name": "反重力飞碟·古尔达夫", "score": 7000},
	"gordea": {"name": "兜鬼巨神兵·戈尔迪亚", "score": 8000},
	"finalGate": {"name": "最终闸门", "score": 9000},
	"alienHeart": {"name": "天王创魔心·戈梅拉莫斯王", "score": 15000},
}

## env: bg/fog 为十六进制色；sky: forest/snow（天空盒）或 none（室内只用环境反射）
const LEVELS := [
	{
		"name": "第1关: 丛林", "theme": "jungle", "boss": "defenseWall",
		"story": "公元2633年，红隼占领加尔加群岛。比尔潜入丛林，穿过爆裂桥，摧毁关底的防御壁！河里有突击水兵出没，小心脚下。",
		"objs": [[0.0, "穿过丛林，打掉沿路的巡逻队"], [0.3, "渡河——小心水里的伏兵，木桥别久留"], [0.62, "清掉防御壁前的营地"], [0.85, "摧毁防御壁"]],
		"env": {"bg": 0x16281a, "ground": "jungle", "fog": 0x16281a, "fog_density": 0.0075, "sky": "forest"},
		"width": 130, "length": 250, "terrain": {"amp": 1.5, "seed": 11.0, "rim": 1.0, "river": true, "ramp": 0.0},
		"spawns": [
			[40, "rifleman", -5], [50, "runner", 4], [68, "rifleman", 6], [79, "sniper", -8],
			[87, "akbar", -5], [98, "runner", -3], [98, "runner", 3], [100, "akbar", 5], [116, "turret", 7], [126, "rifleman", -6],
			[145, "sniper", 8], [156, "runner", 0], [166, "sniper", 7], [176, "turret", -7],
			[192, "rifleman", 5], [192, "rifleman", -5], [205, "runner", 2],
			[135, "sniper", -10],
			[138, "rifleman", -10],
			[59, "akbar", 9],
		],
		"falcons": [58, 138, 198], "letters": ["S", "R", "M"],
		"outpost": {"tx": 9.5, "tz": -63.0, "hx": 17.5, "hz": -65.5},
		"emblems": [[9.5, -63.0], [17.5, -65.5], [-38.0, -52.0]],
	},
	{
		"name": "第2关: 基地1", "theme": "base", "boss": "baseCore",
		"story": "潜入敌方基地。走廊被电网门封锁——打掉墙上的红色感应器核心，电网才会落下。深处有独炎眼守着。",
		"objs": [[0.0, "潜入基地，打掉电网门的感应器"], [0.4, "穿过中段走廊，提防交叉火力"], [0.75, "深入核心区"], [0.9, "摧毁独炎眼"]],
		"env": {"bg": 0x101018, "ground": "concrete", "fog": 0x101018, "fog_density": 0.009, "sky": "none"},
		"width": 96, "length": 200, "terrain": {"amp": 0.0, "seed": 22.0, "rim": 0.0, "river": false, "ramp": 0.0},
		"gates": [32, 66, 100, 132, 164],
		"spawns": [
			[24, "rifleman", -4], [32, "rifleman", 4], [44, "runner", 0],
			[66, "rifleman", 5], [74, "turret", -5], [84, "rifleman", -3], [90, "runner", 3],
			[112, "rifleman", -5], [112, "rifleman", 5], [124, "mortar", 4], [134, "runner", -2],
			[156, "turret", 5], [164, "rifleman", -5], [172, "runner", 0], [172, "runner", 4],
			[140, "roller", -10],
			[176, "roller", 10],
			[58, "shield", 3], [96, "bomber", -4], [146, "bomber", 4], [150, "shield", -3],
		],
		"falcons": [70, 130], "letters": ["M", "B"],
		"emblems": [[42.5, -70.0], [-42.5, -108.0], [-20.0, -146.0]],
	},
	{
		"name": "第3关: 瀑布", "theme": "waterfall", "boss": "gromaides",
		"story": "沿瀑布岩壁向上攀爬！当心落石、掷弹兵和喷火石像，瀑布顶端有阴兽魔神像守着通往基地2的入口。",
		"objs": [[0.0, "沿河谷前进，清掉掷弹兵"], [0.35, "攀上瀑布岩壁——当心喷火石像"], [0.7, "登上崖顶平台"], [0.88, "摧毁魔神像"]],
		"env": {"bg": 0x14202e, "ground": "rock", "fog": 0x14202e, "fog_density": 0.010, "sky": "forest"},
		"width": 120, "length": 250, "terrain": {"amp": 1.1, "seed": 33.0, "rim": 1.0, "river": false, "ramp": 13.0},
		"spawns": [
			[34, "rifleman", -5], [51, "sniper", 6], [69, "runner", 3], [85, "rifleman", -6],
			[103, "turret", 6], [118, "sniper", -7], [133, "runner", -2], [133, "runner", 4],
			[151, "statue", -6], [166, "mortar", 5], [182, "statue", 6], [197, "sniper", 6],
			[208, "runner", 0], [218, "mortar", -4],
			[128, "bomber", -4], [200, "bomber", 5],
		],
		"falcons": [76, 160], "letters": ["F", "S"],
		"cave": {"x": -33.0, "z": -81.0},
		"emblems": [[-34.5, -83.0], [-30.0, -120.0], [30.0, -160.0]],
	},
	{
		"name": "第4关: 基地2", "theme": "base2", "boss": "godomuga",
		"story": "第二座基地，防线更密：自走弹、装甲机动步兵加尔斯都来了。关底的分幻鬼会分裂幻影，真假难辨！",
		"objs": [[0.0, "突入基地2，压制自走弹火力"], [0.4, "穿过重兵走廊"], [0.75, "逼近幻影之间"], [0.9, "击败分幻鬼"]],
		"env": {"bg": 0x14101c, "ground": "concrete", "fog": 0x14101c, "fog_density": 0.0095, "sky": "none"},
		"width": 96, "length": 296, "terrain": {"amp": 0.0, "seed": 44.0, "rim": 0.0, "river": false, "ramp": 0.0},
		"gates": [33, 66, 99, 132, 164, 197, 230, 263],
		"spawns": [
			[31, "rifleman", 4], [42, "roller", -3], [54, "rifleman", -5], [65, "runner", 2],
			[87, "turret", 5], [102, "mortar", -5], [115, "roller", 0], [122, "rifleman", 4],
			[146, "garth", -5], [158, "runner", -2], [158, "runner", 3], [172, "turret", -5],
			[206, "mortar", 5], [217, "roller", -3], [226, "garth", 5], [234, "sniper", -5],
			[257, "rifleman", 0], [262, "runner", 4],
			[110, "bomber", 3], [190, "bomber", -4], [240, "bomber", 0],
		],
		"falcons": [93, 169, 237], "letters": ["L", "R", "S"],
		"emblems": [[42.5, -90.0], [-42.5, -200.0], [18.0, -250.0]],
	},
	{
		"name": "第5关: 雪原", "theme": "snow", "boss": "guldaf",
		"story": "冰天雪地。装甲猎步兵兰格尔混在防线中，重装甲扫讨车多古拉在中途巡逻。关底的反重力飞碟会投放孢子舱——小心头顶！",
		"objs": [[0.0, "踏入雪原，拔掉前沿哨位"], [0.35, "击毁巡逻的装甲扫讨车"], [0.7, "穿过暴风雪带"], [0.88, "击落反重力飞碟"]],
		"env": {"bg": 0x1c2634, "ground": "snow", "fog": 0x1c2634, "fog_density": 0.012, "sky": "snow"},
		"width": 140, "length": 420, "terrain": {"amp": 2.0, "seed": 55.0, "rim": 1.0, "river": false, "ramp": 0.0},
		"mid_tank": 247,
		"spawns": [
			[54, "rifleman", -6], [76, "mortar", 8], [102, "runner", 3], [121, "sniper", -9],
			[147, "mortar", -8], [168, "langel", 6], [189, "roller", 0], [210, "langel", -5],
			[277, "mortar", 7], [299, "runner", -3], [299, "runner", 3], [318, "turret", -8],
			[340, "sniper", 8], [358, "rifleman", 0],
			[241, "mortar", -10],
			[246, "rifleman", -11],
			[196, "shield", -4], [286, "shield", 5],
		],
		"falcons": [115, 220, 325], "letters": ["S", "B", "F"],
		"outpost": {"tx": 18.5, "tz": -203.0, "hx": 26.0, "hz": -207.0},
		"emblems": [[26.0, -207.0], [18.5, -203.0], [48.0, -330.0]],
	},
	{
		"name": "第6关: 能量地带", "theme": "energy", "boss": "gordea",
		"story": "能量地带，火焰喷口按节拍封锁通道——看准节奏再通过。关底是投掷圆盘的兜鬼巨神兵戈尔迪亚！",
		"objs": [[0.0, "进入能量地带，看准火焰节拍前进"], [0.4, "穿过反应堆通道"], [0.75, "逼近巨神兵祭坛"], [0.9, "击败巨神兵"]],
		"env": {"bg": 0x180c08, "ground": "rust", "fog": 0x180c08, "fog_density": 0.009, "sky": "none"},
		"width": 110, "length": 300, "terrain": {"amp": 0.7, "seed": 66.0, "rim": 0.6, "river": false, "ramp": 0.0},
		"flames": [93, 126, 162, 198, 231],
		"spawns": [
			[37, "rifleman", -5], [51, "runner", 4], [69, "turret", 6],
			[104, "rifleman", 5], [114, "runner", -3], [141, "mortar", -6], [151, "rifleman", 6],
			[177, "turret", -6], [189, "runner", 2], [213, "rifleman", -5], [221, "sniper", 6],
			[247, "rifleman", 4], [255, "runner", -2],
			[155, "shield", 4], [238, "shield", -4],
		],
		"falcons": [74, 173, 240], "letters": ["L", "S", "R"],
		"emblems": [[-40.0, -120.0], [40.0, -200.0], [0.0, -250.0]],
	},
	{
		"name": "第7关: 仓库", "theme": "hangar", "boss": "finalGate",
		"story": "红隼的仓库，尖刺矿车在轨道上往复冲撞，压顶机随时落下。打穿尽头的最终闸门，就能进入异形巢穴！",
		"objs": [[0.0, "潜入仓库，避开尖刺矿车"], [0.4, "穿过货架区——当心压顶机"], [0.75, "打到尽头的闸门前"], [0.9, "摧毁最终闸门"]],
		"env": {"bg": 0x12120e, "ground": "concrete", "fog": 0x12120e, "fog_density": 0.0085, "sky": "none"},
		"width": 120, "length": 295, "terrain": {"amp": 0.5, "seed": 77.0, "rim": 0.6, "river": false, "ramp": 0.0},
		"carts": [100, 162, 216],
		"crushers": [127, 190, 248],
		"spawns": [
			[34, "turret", -7], [48, "rifleman", 5], [63, "runner", -3], [78, "turret", 7],
			[118, "rifleman", -6], [130, "mortar", 6], [142, "garth", 0],
			[178, "turret", -7], [190, "garth", 6], [201, "sniper", -6],
			[234, "rifleman", 5], [242, "runner", -4], [242, "runner", 4], [253, "turret", 0],
			[96, "bomber", -5], [214, "bomber", 5],
		],
		"falcons": [84, 172, 237], "letters": ["F", "B", "L"],
		"emblems": [[-24.0, -120.0], [24.0, -210.0], [0.0, -248.0]],
	},
	{
		"name": "第8关: 异形巢穴", "theme": "alien", "boss": "alienHeart",
		"story": "异形巢穴——整面墙都在蠕动，妖卵靠近就会孵出把妖虫。守巢的天王鬼龙神与那颗天王创魔心都在巢穴深处——终结红隼！",
		"objs": [[0.0, "踏入巢穴，别让妖卵孵化"], [0.4, "杀穿蠕动的巢道"], [0.72, "先斩守巢龙神"], [0.9, "打爆天王创魔心"]],
		"env": {"bg": 0x16040c, "ground": "alien", "fog": 0x16040c, "fog_density": 0.0105, "sky": "none"},
		"width": 120, "length": 181, "terrain": {"amp": 1.0, "seed": 88.0, "rim": 1.0, "river": false, "ramp": 0.0},
		"spawns": [
			[23, "spore", -4], [29, "spore", 4], [41, "spore", -6], [51, "spore", 0],
			[63, "turret", 7], [74, "spore", -5], [74, "spore", 5], [86, "spore", -7],
			[98, "spore", 2], [108, "spore", 7], [117, "spore", -3], [117, "spore", 3],
			[129, "spore", 6], [139, "spore", 0],
			[90, "spore", 10],
			[112, "spore", -10],
		],
		"falcons": [47, 98, 137], "letters": ["S", "L", "B"],
		"emblems": [[-33.0, -64.0], [33.0, -79.0], [-30.0, -120.0]],
	},
]

## 角色造型（原作复原）：bill 白背心蓝裤红头巾；lance 裸上身红裤长发红头巾
const CHARACTERS := {
	"bill": {"name": "比尔·雷泽", "sub": "Bill Rizer · 1P", "tint": Color(1, 1, 1), "pants": Color(0.13, 0.27, 0.66), "top": Color(0.92, 0.92, 0.9), "bandana": Color(0.78, 0.1, 0.1), "hair": Color(0.23, 0.15, 0.08), "bare_chest": false, "long_hair": false},
	"lance": {"name": "兰斯·比恩", "sub": "Lance Bean · 2P", "tint": Color(0.94, 0.78, 0.7), "pants": Color(0.66, 0.13, 0.13), "top": Color(0.83, 0.62, 0.44), "bandana": Color(0.78, 0.1, 0.1), "hair": Color(0.16, 0.12, 0.09), "bare_chest": true, "long_hair": true},
}
