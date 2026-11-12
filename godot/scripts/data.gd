class_name Data
extends RefCounted

## 全局数据层 —— 关卡/敌人/Boss/武器全部数据化（与原作解析文档的名册对应）
## 关卡：玩家从 z=26 向 -Z 推进；spawns=[推进米数, 类型, 横向偏移]

const PLAYER := {
	"height": 1.7, "prone_height": 0.55, "radius": 0.38,
	"walk_speed": 7.5, "run_speed": 11.5, "prone_speed": 3.2,
	"jump_velocity": 7.4, "gravity": 19.0,
	"max_cells": 3, "start_lives": 3, "extend_score": 10000,
	"hit_invuln": 0.9, "respawn_invuln": 2.5,
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
	"rifleman": {"hp": 70, "speed": 0.0, "radius": 0.5, "score": 100, "fire_interval": 1.7, "orb_speed": 17.0, "range": 46.0},
	"runner": {"hp": 45, "speed": 6.4, "radius": 0.5, "score": 150, "melee_range": 1.7, "melee_cooldown": 0.9},
	"sniper": {"hp": 45, "speed": 0.0, "radius": 0.5, "score": 300, "fire_interval": 2.4, "orb_speed": 27.0, "range": 60.0},
	"mortar": {"hp": 80, "speed": 0.0, "radius": 0.55, "score": 250, "fire_interval": 3.1, "orb_speed": 0.0, "range": 52.0},
	"garth": {"hp": 170, "speed": 0.0, "radius": 0.55, "score": 300, "fire_interval": 2.0, "orb_speed": 19.0, "range": 46.0},
	"langel": {"hp": 130, "speed": 0.0, "radius": 0.55, "score": 250, "fire_interval": 1.9, "orb_speed": 20.0, "range": 48.0},
	"akbar": {"hp": 60, "speed": 0.0, "radius": 0.5, "score": 200, "fire_interval": 2.2, "orb_speed": 18.0, "range": 40.0},
	"statue": {"hp": 110, "speed": 0.0, "radius": 0.8, "score": 250, "fire_interval": 3.0, "orb_speed": 0.0, "range": 50.0},
	"turret": {"hp": 120, "speed": 0.0, "radius": 0.85, "score": 200, "fire_interval": 0.42, "burst": 3, "burst_pause": 1.5, "orb_speed": 18.0, "range": 44.0},
	"roller": {"hp": 30, "speed": 7.5, "radius": 0.45, "score": 100, "explode_range": 1.9},
	"spore": {"hp": 35, "speed": 5.4, "radius": 0.42, "score": 150, "melee_range": 1.5, "melee_cooldown": 0.8},
	"tank": {"hp": 700, "speed": 2.2, "radius": 1.9, "score": 1500, "fire_interval": 1.1, "orb_speed": 19.0, "range": 46.0},
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
		"env": {"bg": 0x16281a, "ground": "jungle", "fog": 0x16281a, "fog_density": 0.012, "sky": "forest"},
		"width": 26, "length": 190,
		"spawns": [
			[30, "rifleman", -5], [38, "runner", 4], [52, "rifleman", 6], [60, "sniper", -8],
			[66, "akbar", -5], [74, "runner", -3], [74, "runner", 3], [76, "akbar", 5], [88, "turret", 7], [96, "rifleman", -6],
			[110, "mortar", 8], [118, "runner", 0], [126, "sniper", 7], [134, "turret", -7],
			[146, "rifleman", 5], [146, "rifleman", -5], [156, "runner", 2],
		],
		"falcons": [45, 105, 150], "letters": ["S", "R", "M"],
	},
	{
		"name": "第2关: 基地1", "theme": "base", "boss": "baseCore",
		"story": "潜入敌方基地。走廊被电网门封锁——打掉墙上的红色感应器核心，电网才会落下。深处有独炎眼守着。",
		"env": {"bg": 0x101018, "ground": "concrete", "fog": 0x101018, "fog_density": 0.014, "sky": "none"},
		"width": 18, "length": 200,
		"gates": [55, 100, 145],
		"spawns": [
			[24, "rifleman", -4], [32, "rifleman", 4], [44, "runner", 0],
			[66, "rifleman", 5], [74, "turret", -5], [84, "rifleman", -3], [90, "runner", 3],
			[112, "rifleman", -5], [112, "rifleman", 5], [124, "mortar", 4], [134, "runner", -2],
			[156, "turret", 5], [164, "rifleman", -5], [172, "runner", 0], [172, "runner", 4],
		],
		"falcons": [70, 130], "letters": ["M", "B"],
	},
	{
		"name": "第3关: 瀑布", "theme": "waterfall", "boss": "gromaides",
		"story": "沿瀑布岩壁向上攀爬！当心落石、掷弹兵和喷火石像，瀑布顶端有阴兽魔神像守着通往基地2的入口。",
		"env": {"bg": 0x14202e, "ground": "rock", "fog": 0x14202e, "fog_density": 0.016, "sky": "forest"},
		"width": 22, "length": 195, "terraces": true,
		"spawns": [
			[26, "rifleman", -5], [40, "sniper", 6], [54, "runner", 3], [66, "rifleman", -6],
			[80, "turret", 6], [92, "sniper", -7], [104, "runner", -2], [104, "runner", 4],
			[118, "statue", -6], [130, "rifleman", 5], [142, "statue", 6], [154, "sniper", 6],
			[162, "runner", 0], [170, "rifleman", -4],
		],
		"falcons": [60, 125], "letters": ["F", "S"],
	},
	{
		"name": "第4关: 基地2", "theme": "base2", "boss": "godomuga",
		"story": "第二座基地，防线更密：自走弹、装甲机动步兵加尔斯都来了。关底的分幻鬼会分裂幻影，真身只在四影对齐的一瞬现形！",
		"env": {"bg": 0x14101c, "ground": "concrete", "fog": 0x14101c, "fog_density": 0.015, "sky": "none"},
		"width": 18, "length": 210,
		"gates": [50, 92, 134, 172],
		"spawns": [
			[22, "rifleman", 4], [30, "roller", -3], [38, "rifleman", -5], [46, "runner", 2],
			[62, "turret", 5], [72, "mortar", -5], [82, "roller", 0], [86, "rifleman", 4],
			[104, "garth", -5], [112, "runner", -2], [112, "runner", 3], [122, "turret", -5],
			[146, "mortar", 5], [154, "roller", -3], [160, "garth", 5], [166, "sniper", -5],
			[182, "rifleman", 0], [186, "runner", 4],
		],
		"falcons": [66, 120, 168], "letters": ["L", "R", "S"],
	},
	{
		"name": "第5关: 雪原", "theme": "snow", "boss": "guldaf",
		"story": "冰天雪地。装甲猎步兵兰格尔混在防线中，重装甲扫讨车多古拉在中途巡逻。关底的反重力飞碟会投放孢子舱，打它的底部核心！",
		"env": {"bg": 0x1c2634, "ground": "snow", "fog": 0x1c2634, "fog_density": 0.02, "sky": "snow"},
		"width": 28, "length": 200,
		"mid_tank": 118,
		"spawns": [
			[26, "rifleman", -6], [36, "mortar", 8], [48, "runner", 3], [58, "sniper", -9],
			[70, "mortar", -8], [80, "langel", 6], [90, "roller", 0], [100, "langel", -5],
			[132, "mortar", 7], [142, "runner", -3], [142, "runner", 3], [152, "turret", -8],
			[162, "sniper", 8], [170, "rifleman", 0],
		],
		"falcons": [55, 105, 155], "letters": ["S", "B", "F"],
	},
	{
		"name": "第6关: 能量地带", "theme": "energy", "boss": "gordea",
		"story": "能量地带，火焰喷口按节拍封锁通道——看准节奏再通过。关底是投掷圆盘的兜鬼巨神兵戈尔迪亚！",
		"env": {"bg": 0x180c08, "ground": "rust", "fog": 0x180c08, "fog_density": 0.014, "sky": "none"},
		"width": 22, "length": 200,
		"flames": [62, 84, 108, 132, 154],
		"spawns": [
			[24, "rifleman", -5], [34, "runner", 4], [46, "turret", 6],
			[70, "rifleman", 5], [76, "runner", -3], [94, "mortar", -6], [100, "rifleman", 6],
			[118, "turret", -6], [126, "runner", 2], [142, "rifleman", -5], [148, "sniper", 6],
			[164, "rifleman", 4], [170, "runner", -2],
		],
		"falcons": [50, 115, 160], "letters": ["L", "S", "R"],
	},
	{
		"name": "第7关: 仓库", "theme": "hangar", "boss": "finalGate",
		"story": "红隼的仓库，尖刺矿车在轨道上往复冲撞，压顶机随时落下。打穿尽头的最终闸门，就能进入异形巢穴！",
		"env": {"bg": 0x12120e, "ground": "concrete", "fog": 0x12120e, "fog_density": 0.013, "sky": "none"},
		"width": 24, "length": 205,
		"carts": [70, 112, 150],
		"crushers": [88, 132, 172],
		"spawns": [
			[24, "turret", -7], [34, "rifleman", 5], [44, "runner", -3], [54, "turret", 7],
			[82, "rifleman", -6], [90, "mortar", 6], [98, "runner", 0],
			[124, "turret", -7], [132, "garth", 6], [140, "sniper", -6],
			[162, "rifleman", 5], [168, "runner", -4], [168, "runner", 4], [176, "turret", 0],
		],
		"falcons": [58, 120, 165], "letters": ["F", "B", "L"],
	},
	{
		"name": "第8关: 异形巢穴", "theme": "alien", "boss": "alienHeart",
		"story": "异形巢穴——整面墙都在蠕动，妖卵靠近就会孵出把妖虫。先斩守巢的天王鬼龙神，再打爆那颗天王创魔心，终结红隼！",
		"env": {"bg": 0x16040c, "ground": "alien", "fog": 0x16040c, "fog_density": 0.017, "sky": "none"},
		"width": 24, "length": 185,
		"spawns": [
			[24, "spore", -4], [30, "spore", 4], [42, "rifleman", -6], [52, "spore", 0],
			[64, "turret", 7], [76, "spore", -5], [76, "spore", 5], [88, "mortar", -7],
			[100, "spore", 2], [110, "sniper", 7], [120, "spore", -3], [120, "spore", 3],
			[132, "garth", 6], [142, "spore", 0],
		],
		"falcons": [48, 100, 140], "letters": ["S", "L", "B"],
	},
]

## 角色造型（原作复原）：bill 白背心蓝裤红头巾；lance 裸上身红裤长发红头巾
const CHARACTERS := {
	"bill": {"name": "比尔·雷泽", "sub": "Bill Rizer · 1P", "pants": Color(0.13, 0.27, 0.66), "top": Color(0.92, 0.92, 0.9), "bandana": Color(0.78, 0.1, 0.1), "hair": Color(0.23, 0.15, 0.08), "bare_chest": false, "long_hair": false},
	"lance": {"name": "兰斯·比恩", "sub": "Lance Bean · 2P", "pants": Color(0.66, 0.13, 0.13), "top": Color(0.83, 0.62, 0.44), "bandana": Color(0.78, 0.1, 0.1), "hair": Color(0.16, 0.12, 0.09), "bare_chest": true, "long_hair": true},
}
