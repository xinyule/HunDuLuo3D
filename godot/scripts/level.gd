class_name Level
extends Node3D

## 关卡 —— 线性走廊推进 + 分段触发刷怪（原作 8 关复原）
## 主题动态（日版独有）：丛林树冠摇动 / 瀑布流水 / 异形肉壁蠕动 / 基地灯带明暗 / 雪原吹雪

class GateSensor:
	extends RefCounted
	var alive := true
	var targetable := true
	var hp := 272 # 对标原版房核心 8 发（调平表 §5）
	var hit_x := 0.0
	var hit_y := 0.0
	var hit_z := 0.0
	var hit_r := 0.85
	var node: Node3D
	var on_open: Callable
	var on_score: Callable
	var projectiles
	var pos := Vector3.ZERO
	func on_hit(dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
		if not alive:
			return
		hp -= dmg
		if hp <= 0:
			alive = false
			targetable = false
			on_score.call(300)
			AudioSys.play("gate")
			projectiles.spawn_explosion_fx(pos + Vector3(0, 0, 0.8), 2.2, Color(0.4, 0.85, 1))
			on_open.call()

## 油桶目标：中弹打爆（hp 小），爆炸/连锁逻辑在 Level._detonate_barrel
class BarrelTarget:
	extends RefCounted
	var alive := true
	var targetable := true
	var hp := 10
	var hit_x := 0.0
	var hit_y := 0.0
	var hit_z := 0.0
	var hit_r := 0.62
	var pos := Vector3.ZERO
	var node: Node3D
	var col: Dictionary
	var on_boom: Callable
	func on_hit(dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
		if not alive:
			return
		hp -= dmg
		if hp <= 0 and on_boom.is_valid():
			on_boom.call(self)

## 树冠目标：打不坏，只触发落叶（挂在目标列表最末尾，不抢真目标的子弹）
class TreeTarget:
	extends RefCounted
	var alive := true
	var targetable := true
	var hit_x := 0.0
	var hit_y := 0.0
	var hit_z := 0.0
	var hit_r := 1.6
	var on_leaf: Callable
	func on_hit(_dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
		if on_leaf.is_valid():
			on_leaf.call()

var data: Dictionary
var level_index := 0
var width := 20.0
var length := 200.0
var colliders: Array = []
var enemies: Array = []
var sensors: Array = []
var barrels: Array = []
var gates: Array = []
var locks: Array = [] # 1.2.0 封锁点：{entry, exit, z, field, collider, members, active, cleared}
var flames: Array = []
var carts: Array = []
var crushers: Array = []
var rocks: Array = []
var eggs: Array = []
var boss: Boss
var boss_activated := false
var boss_z := 0.0
var boss_y := 0.0
var _barrier_wall: MeshInstance3D = null
var _barrier_col: Dictionary = {}
var _boss_blocker: Dictionary = {}
var terrace_top_y := 0.0
var pickups: PickupSystem
var time := 0.0

var _ctx: Dictionary
var _enemy_ctx: Dictionary
## 难度档：敌人更新 dt 倍率（间隔等效缩放，见 main.gd DIFF_DT 注释）；弹速在 projectiles 层缩放
var _enemy_dt_scale := 1.0
## 画质分档：草量倍率（建关时按 ctx 的 quality 定；贴图分辨率不动）
var _grass_scale := 1.0
var _quality := "high"
# ---- 环境互动（油桶连锁/落叶/雪地脚印/草让开）----
var _tree_targets: Array = []
var _pending_booms: Array = [] # {t, bt}：连锁引爆延迟队列
var _leaf_fx: Array = [] # {p, t}：一次性落叶粒子
var _player_ref = null # update_level 每帧刷新，供油桶爆炸等回调定位玩家
var _fp_geo: PlaneMesh = null
var _footprints: Array = [] # {mesh, mat, t}：雪地脚印环（上限 240 循环复用）
var _fp_next := 0
var _trackers: Dictionary = {} # 实例 id -> {lpos, acc, side}：脚印步距跟踪
var _grass_mm: MultiMesh = null
var _grass_base: Array = []
var _grass_bent: Dictionary = {}
var _grass_timer := 0.0

var _spawn_points: Array = [] # 开放版：敌人世界坐标（开局全量预置）
var _pads: Array = [] # 地形平整垫：营地/Boss 场/出生点（{x,z,r,h}，h 在建地形时定）
var _terr_amp := 0.0
var _terr_seed := 0.0
var _terr_river := false
var _terr_ramp := 0.0
var _terr_rim := 1.0
var _relief: Array = [] # 数据驱动地形起伏（1.1.0 第二线）：[x, z, 半径, 高度] 高斯土丘（正=高地/负=低洼）
var _falcon_queue: Array = []
var _checkpoints: Array = []
var _cp_index := 0
var _rock_timer := 2.5
var _sun: DirectionalLight3D
var _sway: Array = []
var _scroll_mats: Array = []
var _pulse: Array = []
var _blink_mats: Array = []
var _snow: GPUParticles3D
var _bridge_mesh: MeshInstance3D
var _bridge_z := 0.0
var _bridge_collapsed := false

func setup(p_data: Dictionary, p_index: int, ctx: Dictionary) -> void:
	data = p_data
	level_index = p_index
	_ctx = ctx
	_enemy_dt_scale = {"easy": 0.8, "normal": 1.0, "hard": 1.25}.get(String(ctx.get("difficulty", "normal")), 1.0)
	_quality = String(ctx.get("quality", "high"))
	_grass_scale = {"low": 0.45, "mid": 0.75, "high": 1.0}.get(_quality, 1.0)
	width = float(data["width"])
	length = float(data["length"])
	pickups = PickupSystem.new()
	add_child(pickups)
	pickups.setup({"on_pickup": ctx["on_pickup"], "on_score": ctx["on_score"]})
	_enemy_ctx = {"projectiles": ctx["projectiles"], "on_score": ctx["on_score"], "level": self}
	# 地形参数（开放版）
	var terr: Dictionary = data.get("terrain", {})
	_terr_amp = float(terr.get("amp", 0.0))
	_terr_seed = float(terr.get("seed", 1.0))
	_terr_river = bool(terr.get("river", false))
	_terr_ramp = float(terr.get("ramp", 0.0))
	_terr_rim = float(terr.get("rim", 1.0))
	_relief = data.get("relief", [])
	# 刷怪表 [dist,类型,xoff] → 世界坐标：按 dist 聚成营地，成员散布在营地周围；
	# 每个营地登记一块地形平整垫，敌人开局就站在世界里（不再走到跟前才出现）
	var raw: Array = []
	for s in data["spawns"]:
		raw.append({"dist": float(s[0]), "type": String(s[1]), "x": float(s[2]) * 3.0})
	if data.has("mid_tank"):
		raw.append({"dist": float(data["mid_tank"]), "type": "tank", "x": 0.0})
	raw.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 + level_index * 131
	var i0 := 0
	while i0 < raw.size():
		var j0 := i0
		var cx := 0.0
		var cz := 0.0
		while j0 < raw.size() and float(raw[j0]["dist"]) - float(raw[i0]["dist"]) <= 16.0:
			cx += float(raw[j0]["x"])
			cz += 26.0 - float(raw[j0]["dist"])
			j0 += 1
		var n := j0 - i0
		cx /= n
		cz /= n
		_pads.append({"x": cx, "z": cz, "r": 9.0 + float(n) * 1.7, "h": 0.0})
		for k in range(i0, j0):
			var ang := rng.randf() * TAU
			var rad := rng.randf_range(1.5, 4.5 + float(n))
			# 营地散布落点钳制在玩家可达范围内（1.1.0：不许有敌人站在玩家永远走不到的地方）
			var sp_lim: float = playable_half_width() - 1.5
			_spawn_points.append({"type": String(raw[k]["type"]), "x": clampf(cx + cos(ang) * rad, -sp_lim, sp_lim), "z": cz + sin(ang) * rad * 0.7})
		i0 = j0
	_pads.append({"x": 0.0, "z": 26.0, "r": 11.0, "h": 0.0}) # 出生点
	_pads.append({"x": 0.0, "z": -length + 10.0, "r": 30.0, "h": 0.0}) # Boss 竞技场
	# 内容批：哨塔哨所/瀑布山洞各登记一块平整垫（地形在建筑下压平，建筑基座读 terrain_h）
	if data.has("outpost"):
		var o: Dictionary = data["outpost"]
		_pads.append({"x": (float(o["tx"]) + float(o["hx"])) / 2.0, "z": (float(o["tz"]) + float(o["hz"])) / 2.0, "r": 11.0, "h": 0.0})
	if data.has("cave"):
		var cv: Dictionary = data["cave"]
		_pads.append({"x": float(cv["x"]), "z": float(cv["z"]), "r": 7.0, "h": 0.0})
	var letters: Array = data.get("letters", ["S"])
	var fi := 0
	for d in data.get("falcons", []):
		_falcon_queue.append({"dist": float(d), "letter": letters[fi % letters.size()], "done": false})
		fi += 1
	_checkpoints.append({"x": 0.0, "y": 0.0, "z": 26.0, "dist": -1.0})
	for gd in data.get("gates", []):
		_checkpoints.append({"x": 0.0, "y": 0.0, "z": 26.0 - float(gd) - 4.0, "dist": float(gd) + 4.0})
	_checkpoints.append({"x": 0.0, "y": 0.0, "z": 26.0 - (length - 44.0), "dist": length - 44.0})
	_prepare_build_stages()
	if not bool(ctx.get("staged", false)):
		# 默认同步建完（探针/工具的旧语义不变）；ctx 带 staged 时只备阶段，由 main 逐帧驱动（加载界面）
		while not build_done:
			run_next_build_stage()

func player_dist(player) -> float:
	return 26.0 - player.global_position.z

## 河流中心线（丛林关）：随 x 蜿蜒，河床/水面/水兵位置都以它为准
func river_center_z(x: float) -> float:
	return -44.0 + 9.0 * sin(x * 0.018 + 1.3)

func _hash2(ix: float, iz: float) -> float:
	var s := sin(ix * 127.1 + iz * 311.7 + _terr_seed * 74.7) * 43758.5453
	return s - floorf(s)

## 值噪声（双倍频）：决定丘陵起伏，同一坐标永远同一高度
func _vnoise(x: float, z: float) -> float:
	var ix := floorf(x)
	var iz := floorf(z)
	var fx := x - ix
	var fz := z - iz
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sz := fz * fz * (3.0 - 2.0 * fz)
	var a := _hash2(ix, iz)
	var b := _hash2(ix + 1.0, iz)
	var c := _hash2(ix, iz + 1.0)
	var d := _hash2(ix + 1.0, iz + 1.0)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sz)

## 无垫地形：丘陵 + 边缘山脊 + 瀑布爬升 + 河道下切
func _base_height(x: float, z: float) -> float:
	var h := 0.0
	if _terr_amp > 0.0:
		h += (_vnoise(x * 0.045, z * 0.045) - 0.5) * 2.0 * _terr_amp
		h += (_vnoise(x * 0.13 + 40.0, z * 0.13) - 0.5) * _terr_amp * 0.55
	# 边缘隆起成可见山体：看得见、爬得上半山，硬边界在山脊之外（不用隐形墙）
	# 山脊再叠两层值噪声调制（中频大起伏+细碎凸凹），免得光滑得像滑梯；
	# 调制随 e 渐入（山脚≈0），且只在本函数内生效——terrain_h 仍是高度唯一真源
	var ex := absf(x) - (width / 2.0 - 24.0)
	var ez := maxf(z - 26.0, (-length - 4.0) - z)
	var e := maxf(ex, ez)
	if e > 0.0 and _terr_rim > 0.0:
		var rim_h := e * e * 0.055 * _terr_rim
		var fade := clampf(e / 14.0, 0.0, 1.0)
		if fade > 0.0:
			var n1 := (_vnoise(x * 0.085 + 90.0, z * 0.085) - 0.5) * 2.0
			var n2 := (_vnoise(x * 0.23 + 190.0, z * 0.23) - 0.5) * 2.0
			rim_h *= 1.0 + fade * (n1 * 0.22 + n2 * 0.07)
		h += rim_h
	if _terr_ramp > 0.0:
		var t := clampf((26.0 - z - 30.0) / (length - 85.0), 0.0, 1.0)
		h += t * _terr_ramp
	# 数据驱动起伏（1.1.0 第二线）：高斯土丘/洼地，坡度按 h/r 压在缓坡内（玩家地形跟随可步行登顶）；
	# 营地平整垫在本函数之后抹平（terrain_h），丘顶营地自动成平顶台地、丘坡保持
	for rf in _relief:
		var rdx := x - float(rf[0])
		var rdz := z - float(rf[1])
		var rr := float(rf[2])
		var q := (rdx * rdx + rdz * rdz) / (rr * rr)
		if q < 4.0:
			h += float(rf[3]) * exp(-q * 1.7)
	if _terr_river:
		var d := absf(z - river_center_z(x))
		h = lerpf(-1.15, h, smoothstep(3.0, 9.5, d))
	return h

## 实际地形高度 = 无垫地形被营地/Boss 场/出生点平整垫抹平
func terrain_h(x: float, z: float) -> float:
	var h := _base_height(x, z)
	for p in _pads:
		var dx := x - float(p["x"])
		var dz := z - float(p["z"])
		var d := sqrt(dx * dx + dz * dz)
		var r_out := float(p["r"]) * 1.9
		if d < r_out:
			h = lerpf(float(p["h"]), h, smoothstep(float(p["r"]) * 0.65, r_out, d))
	return h

## 玩家横向可达半宽（玩家钳制、飞鹰巡逻、物品落点的共同口径，1.1.0 空气墙根因修复）：
## 室外关沿用山脊口径（width/2-14，落在山脊内侧）；室内关 rim=0 没有山脊，
## 以可见侧墙内面为界——基地侧墙在 ±(width/2+1.4)、厚 1.6，内面 = width/2+0.6，
## 墙本身带碰撞兜底，钳制只作保险。旧全局公式 width/2-14 用在室内关时，
## 会在墙前凭空挡出一条约 14m 宽的死区（人进不去、物品却能落进去）。
func playable_half_width() -> float:
	if _terr_rim <= 0.0:
		return width / 2.0 + 0.6
	return width / 2.0 - 14.0

## 坡度（梯度模长≈tan 坡角，中心差分采样 terrain_h）：植被摆放按它把关，陡坡不种
func _slope_grad(x: float, z: float) -> float:
	var e := 0.9
	var gx := (terrain_h(x + e, z) - terrain_h(x - e, z)) / (2.0 * e)
	var gz := (terrain_h(x, z + e) - terrain_h(x, z - e)) / (2.0 * e)
	return sqrt(gx * gx + gz * gz)

## 视线判定：地形或实体碰撞体挡住即无视线（双方开火都以它为准）
func has_los(a: Vector3, b: Vector3) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 2.5)
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		if terrain_h(p.x, p.z) > p.y + 0.3:
			return false
		for c in colliders:
			if c.get("disabled", false) or c.get("no_collide", false):
				continue
			var y0 := float(c.get("y0", 0.0))
			if p.y < y0 or p.y > y0 + float(c.get("h", 6.0)):
				continue
			if c["type"] == "box":
				if absf(p.x - float(c["x"])) <= float(c["w"]) / 2.0 and absf(p.z - float(c["z"])) <= float(c["d"]) / 2.0:
					return false
			elif c["type"] == "circle":
				var dx := p.x - float(c["x"])
				var dz := p.z - float(c["z"])
				var r := float(c["r"])
				if dx * dx + dz * dz <= r * r:
					return false
	return true

func get_support_y(x: float, z: float, from_y: float) -> float:
	var best := terrain_h(x, z)
	for c in colliders:
		if c.get("disabled", false) or c.get("no_collide", false):
			continue
		var top := float(c.get("y0", 0.0)) + float(c.get("h", 6.0))
		if top > from_y + 0.55 or top <= best:
			continue
		if c["type"] == "box":
			if absf(x - float(c["x"])) <= float(c["w"]) / 2.0 + 0.05 and absf(z - float(c["z"])) <= float(c["d"]) / 2.0 + 0.05:
				best = top
		elif c["type"] == "circle":
			var dx: float = x - float(c["x"])
			var dz: float = z - float(c["z"])
			var r := float(c["r"]) + 0.05
			if dx * dx + dz * dz <= r * r:
				best = top
	return best

# ---------------- 建造 ----------------
func _add_collider(c: Dictionary) -> Dictionary:
	colliders.append(c)
	return c

func _add_box(x: float, z: float, w: float, d: float, h: float, mat: Material, y0: float = 0.0, with_collider: bool = true) -> MeshInstance3D:
	var mi := Util.box(self, Vector3(w, h, d), mat, Vector3(x, y0 + h / 2.0, z))
	if with_collider:
		_add_collider({"type": "box", "x": x, "z": z, "w": w, "d": d, "h": h, "y0": y0})
	return mi

## 木质掩体（木箱）：碰撞带 wood 标签 + 血量——玩家子弹可穿透（伤害减半），
## 且能被打烂，打烂后碰撞失效、箱子消失；敌方光弹会被它挡住
func _add_crate(x: float, z: float, w: float, d: float, h: float, mat: Material) -> MeshInstance3D:
	var gy := terrain_h(x, z)
	var mi := Util.box(self, Vector3(w, h, d), mat, Vector3(x, gy + h / 2.0, z))
	var c := _add_collider({"type": "box", "x": x, "z": z, "w": w, "d": d, "h": h, "y0": gy})
	c["mat"] = "wood"
	c["hp"] = 40.0
	c["node"] = mi
	c["cover"] = true # 1.2.0：掩体登记——colliders 即掩体表，cover 标记供 NPC 躲掩体 AI 检索
	return mi

## 分阶段建造（1.1.0 体验项：加载过程显示）：旧 _build() 按原顺序切成 5 个阶段，
## 阶段间可让出整帧使加载界面真实刷新；同步模式（探针）仍一口气跑完，结果与旧版一致。
const BUILD_STAGE_NAMES := ["正在生成地形", "正在建造场景", "正在布置机关", "敌人正在集结", "正在完成部署"]
const _BUILD_STAGE_FUNCS := ["_stage_terrain", "_stage_theme", "_stage_mechanics", "_stage_enemies", "_stage_emblems"]
var _build_stage_idx := 0
var build_done := false

func _prepare_build_stages() -> void:
	_build_stage_idx = 0
	build_done = false

func build_stage_count() -> int:
	return _BUILD_STAGE_FUNCS.size()

func build_stage_index() -> int:
	return _build_stage_idx

func run_next_build_stage() -> void:
	if build_done:
		return
	call(String(_BUILD_STAGE_FUNCS[_build_stage_idx]))
	_build_stage_idx += 1
	if _build_stage_idx >= _BUILD_STAGE_FUNCS.size():
		build_done = true

func _stage_terrain() -> void:
	var env_data: Dictionary = data["env"]
	_setup_environment(env_data)
	_sun = DirectionalLight3D.new()
	_sun.light_energy = float(env_data.get("sun_energy", 1.05)) # 可选：逐关日光强弱（背景去重差异化，1.1.0）
	_sun.light_color = Color.html("#%06x" % int(env_data["sun_color"])) if env_data.has("sun_color") else Color(1, 0.97, 0.9)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 120.0 if _quality == "high" else 70.0
	_sun.shadow_enabled = _quality != "low" # 低档关阴影（画质分档）
	_sun.rotation_degrees = Vector3(-52, -28, 0)
	add_child(_sun)
	_build_ground_and_walls()

func _stage_theme() -> void:
	match String(data["theme"]):
		"jungle": _theme_jungle()
		"base", "base2": _theme_base()
		"waterfall": _theme_waterfall()
		"snow": _theme_snow()
		"energy": _theme_energy()
		"hangar": _theme_hangar()
		"alien": _theme_alien()

func _stage_mechanics() -> void:
	for gi in data.get("gates", []).size():
		_build_gate(float(data["gates"][gi]), gi)
	for i in data.get("flames", []).size():
		_build_flame(float(data["flames"][i]), i)
	for i in data.get("carts", []).size():
		_build_cart(float(data["carts"][i]), i)
	for i in data.get("crushers", []).size():
		_build_crusher(float(data["crushers"][i]), i)

func _stage_enemies() -> void:
	boss_z = -length + 10.0
	boss_y = get_support_y(0.0, boss_z, 999.0)
	boss = Boss.new()
	add_child(boss)
	boss.setup(String(data["boss"]), Vector3(0, boss_y, boss_z), {
		"projectiles": _ctx["projectiles"],
		"on_score": _ctx["on_score"],
		"on_defeated": _ctx["on_boss_defeated"],
		"on_core_exposed": _ctx.get("on_core_exposed", Callable()),
		"spawn_minion": func(t, x, z): return _spawn_enemy(t, x, z), # 1.2.0：带 return——最终 Boss 要拿增援引用做存活上限计数
	})
	# Boss 本体封路：全宽封锁到围界——打死前不能从侧翼绕到 Boss 垫侧面/背面输出（击败后在更新循环里解除）
	_boss_blocker = _add_collider({"type": "box", "x": 0.0, "z": boss_z, "w": width + 24.0, "d": 2.2, "h": 9.0, "y0": boss_y})
	# 开放版：敌人与飞鹰开局全量预置——从进关第一秒起就站在世界里
	for p in _spawn_points:
		_spawn_enemy(String(p["type"]), float(p["x"]), float(p["z"]))
	for f in _falcon_queue:
		f["done"] = true
		pickups.spawn_falcon(26.0 - float(f["dist"]), String(f["letter"]), minf(44.0, playable_half_width() - 2.0)) # 巡逻带：避开边缘山脊，且不飞出玩家可达范围（1.1.0）
	_build_locks()

## 1.2.0 封锁点建造（数据 data["locks"] = [[入口dist, 出口dist], ...]）：
## 出口处预置门框（边柱+顶梁，常显作预告）与能量墙（初始隐藏、无碰撞）；
## 成员＝出生 dist 落在 [entry, exit] 的预置敌人（建关时按 _home 分配、固定不变）
func _build_locks() -> void:
	for zi in data.get("locks", []).size():
		var pair: Array = data["locks"][zi]
		var entry := float(pair[0])
		var exitd := float(pair[1])
		var z := 26.0 - exitd
		var frame_m := Util.pbr(Color(0.22, 0.25, 0.28), "", 0.5, 0.6)
		# 门框必须跟地形走：1.2.0 地形起伏 ×2 后坡面可达 5~9m，绝对高度的顶梁会被埋进
		# 坡面变成永久横墙堵死路线（routes 实测 lane 45 卡在梁前）——顶梁只作视觉、
		# 高度按中心地形抬升且不带碰撞；边柱按各自落点地形落座
		var ground_c := terrain_h(0.0, z)
		_add_box(-(width / 2.0 - 1.0), z, 2, 1, 6, frame_m, terrain_h(-(width / 2.0 - 1.0), z) - 0.3)
		_add_box(width / 2.0 - 1.0, z, 2, 1, 6, frame_m, terrain_h(width / 2.0 - 1.0, z) - 0.3)
		_add_box(0, z, width, 1, 1, frame_m, ground_c + 5.0, false)
		var field := MeshInstance3D.new()
		var fp := PlaneMesh.new()
		fp.size = Vector2(width - 4.0, 5.0)
		fp.orientation = PlaneMesh.FACE_Z
		field.mesh = fp
		field.material_override = Util.flat(Color(0.2, 0.8, 1, 0.38))
		field.position = Vector3(0, ground_c + 2.5, z)
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		field.visible = false
		add_child(field)
		# 场碰撞加高（y0=-2、h=14）：覆盖高坡地形上玩家的身体窗口，坡下也不留缝
		var collider := _add_collider({"type": "box", "x": 0.0, "z": z, "w": width + 3.2, "d": 0.9, "h": 14.0, "y0": -2.0})
		collider["disabled"] = true
		var members: Array = []
		for e in enemies:
			var ed: float = 26.0 - e._home.z
			if ed >= entry and ed <= exitd:
				members.append(e)
		locks.append({"entry": entry, "exit": exitd, "z": z, "field": field, "collider": collider, "members": members, "active": false, "cleared": false})

## 封锁箭头目标：任一活跃封锁区只剩 ≤2 名成员时，返回最近残敌位置（main 边缘箭头调用）；否则 ZERO
func lock_arrow_target(ppos: Vector3) -> Vector3:
	var best := 1.0e18
	var tgt := Vector3.ZERO
	for lk in locks:
		if not bool(lk["active"]) or bool(lk["cleared"]):
			continue
		var alive_n := 0
		var near := Vector3.ZERO
		var nd := 1.0e18
		for e in lk["members"]:
			if is_instance_valid(e) and e.alive:
				alive_n += 1
				var d: float = ppos.distance_squared_to(e.global_position)
				if d < nd:
					nd = d
					near = e.global_position
		if alive_n > 0 and alive_n <= 2 and nd < best:
			best = nd
			tgt = near + Vector3(0, 1.6, 0)
	return tgt
func _stage_emblems() -> void:
	# 内容批：隐藏鹰徽（每关 3 枚）——此时主题摆件/建筑碰撞都已就位，y 取支撑面（塔顶/屋内地面都对）
	if data.has("emblems"):
		var es: Array = data["emblems"]
		for ei in es.size():
			# 鹰徽落点防御性钳制：永远摆在玩家走得到的地方（1.1.0；现行数据均在界内、位置不变）
			var ex := clampf(float(es[ei][0]), -(playable_half_width() - 1.0), playable_half_width() - 1.0)
			var ez := float(es[ei][1])
			if not pickups.is_emblem_collected(level_index, ei):
				pickups.spawn_emblem(Vector3(ex, get_support_y(ex, ez, 999.0) + 1.0, ez), level_index, ei)

const TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D tex_flat : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_flat_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint_flat : source_color;
uniform vec4 tint_rock : source_color;
uniform float wet_band = 0.0;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = wpos.xz / 6.0;
	float steep = smoothstep(0.18, 0.42, 1.0 - wnormal.y);
	vec3 flat_c = texture(tex_flat, uv).rgb * tint_flat.rgb;
	// 岩石三平面采样（尺度 /3 比平地更密）：近垂直壁面不再被 xz 投影拉成竖条滑梯纹
	vec3 rock_c = vec3(0.0);
	if (steep > 0.002) {
		vec3 bw = pow(abs(wnormal), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		rock_c = (texture(tex_rock, wpos.zy / 3.0).rgb * bw.x
			+ texture(tex_rock, wpos.xz / 3.0).rgb * bw.y
			+ texture(tex_rock, wpos.xy / 3.0).rgb * bw.z) * tint_rock.rgb;
	}
	vec3 col = mix(flat_c, rock_c, steep);
	float det = texture(tex_detail, wpos.xz / 0.8).r;
	col *= 0.82 + det * 0.36;
	if (wet_band > 0.5) {
		float wet = smoothstep(0.35, -0.3, wpos.y);
		col = mix(col, col * vec3(0.45, 0.42, 0.4), wet * 0.75);
	}
	ALBEDO = col;
	NORMAL_MAP = mix(texture(tex_flat_n, uv).rgb, texture(tex_rock_n, uv).rgb, steep);
	NORMAL_MAP_DEPTH = mix(1.0, 1.7, steep);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
"""

## 地形材质：坡度混合贴图（平地主题面 / 陡坡自动岩石）+ 近景细节 + 河岸湿痕
func _terrain_material(tint: Color, ground_tex: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex_flat", load("res://assets/tex/%s_diff.jpg" % ground_tex))
	m.set_shader_parameter("tex_flat_n", load("res://assets/tex/%s_nor.jpg" % ground_tex))
	m.set_shader_parameter("tex_rock", load("res://assets/tex/rock_diff.jpg"))
	m.set_shader_parameter("tex_rock_n", load("res://assets/tex/rock_nor.jpg"))
	m.set_shader_parameter("tex_detail", load("res://assets/tex/weave_diff.jpg"))
	m.set_shader_parameter("tint_flat", tint)
	m.set_shader_parameter("tint_rock", Color(0.82, 0.79, 0.72))
	m.set_shader_parameter("wet_band", 1.0 if _terr_river else 0.0)
	return m

## 天空 HDRI（Poly Haven CC0，4K 原图降采样 2K）：按关映射；
## 室外关（sky != none）背景露天空，室内关只借天空做环境光/反射、背景仍走纯色
const LEVEL_HDRI := ["jungle_day", "base_sunny", "waterfall_cloudy", "base_sunny", "snow_overcast", "energy_dusk", "base_sunny", "nest_night"]

func _setup_environment(env_data: Dictionary) -> void:
	var we: WorldEnvironment = _ctx["world_env"]
	var env := we.environment
	var sky_name := String(env_data["sky"])
	var hdri_name: String = LEVEL_HDRI[clampi(level_index, 0, LEVEL_HDRI.size() - 1)]
	var sky_res := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/%s.hdr" % hdri_name)
	sky_res.sky_material = pm
	env.sky = sky_res
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55 if hdri_name == "nest_night" else 0.42 # 夜空图本身暗，环境光略提
	if sky_name == "none":
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.html("#%06x" % int(env_data["bg"]))
	else:
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = float(env_data.get("sky_energy", 0.85)) # 可选：逐关天空亮度（背景去重差异化，1.1.0）
	env.fog_enabled = true
	env.fog_light_color = Color.html("#%06x" % int(env_data["fog"]))
	env.fog_density = float(env_data["fog_density"])
	env.fog_sun_scatter = 0.25

func _build_ground_and_walls() -> void:
	# 先定各地形垫的高度（以该点无垫地形为基准），再生成整张地形网格
	for p in _pads:
		p["h"] = _base_height(float(p["x"]), float(p["z"]))
	var env_data: Dictionary = data["env"]
	# 色调（2026-11-12 换 Poly Haven 写实贴图后整体回到近中性，只留轻微氛围染色，免得真实贴图被乘暗乘绿）
	var ground_tints := {"jungle": Color(0.88, 0.9, 0.82), "rock": Color(0.95, 0.94, 0.9), "snow": Color(1, 1, 1), "concrete": Color(0.92, 0.93, 0.95), "rust": Color(0.66, 0.58, 0.5), "alien": Color(0.82, 0.64, 0.7)}
	var gtint: Color = ground_tints.get(String(env_data["ground"]), Color(0.85, 0.85, 0.85))
	var ground_mat := _terrain_material(gtint, String(env_data["ground"]))
	var x0 := -(width / 2.0 + 34.0)
	var x1 := width / 2.0 + 34.0
	var z1 := 42.0
	var z0 := -length - 32.0
	var step := 3.0
	var cols := int((x1 - x0) / step) + 1
	var rows := int((z1 - z0) / step) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for r in rows:
		for c in cols:
			var x := x0 + float(c) * step
			var z := z1 - float(r) * step
			verts.append(Vector3(x, terrain_h(x, z), z))
			var e := 1.5
			var nx := terrain_h(x - e, z) - terrain_h(x + e, z)
			var nz := terrain_h(x, z - e) - terrain_h(x, z + e)
			normals.append(Vector3(nx / (2.0 * e), 1.0, nz / (2.0 * e)).normalized())
			uvs.append(Vector2(x / 6.0, z / 6.0))
	for r in range(rows - 1):
		for c in range(cols - 1):
			var a := r * cols + c
			var b := a + 1
			var d2 := a + cols
			var e2 := d2 + 1
			indices.append_array([a, d2, b, b, d2, e2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground := MeshInstance3D.new()
	ground.mesh = am
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

func _scatter(rand: RandomNumberGenerator, count: int, maker: Callable) -> void:
	for i in count:
		var dist := 24.0 + rand.randf() * (length - 55.0)
		var x := (1.0 if rand.randf() > 0.5 else -1.0) * (3.5 + rand.randf() * (width / 2.0 - 17.0))
		maker.call(x, 26.0 - dist, rand)

var _leaf_mat: Material = null
var _leaf_mat_snow: Material = null
var _leaf_card_mesh: PlaneMesh = null

static var _fern_scene: PackedScene = null
static var _quiver_scene: PackedScene = null

func _leaf_material(snow: bool) -> Material:
	if snow and _leaf_mat_snow:
		return _leaf_mat_snow
	if not snow and _leaf_mat:
		return _leaf_mat
	var m := StandardMaterial3D.new()
	# 用 _bleed 版贴图：透明区 RGB 已用叶色外溢填满，远距离 mip 混合不再被近黑像素拖成黑饼；
	# 剪切阈值同步下调（原贴图全图平均 alpha≈0.32，0.35 会在远处把整卡剪得只剩暗芯）
	m.albedo_texture = load("res://assets/tex/foliage_cluster_snow_bleed.png" if snow else "res://assets/tex/foliage_cluster_bleed.png")
	m.texture_filter = 5 # 各向异性过滤
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	if snow:
		_leaf_mat_snow = m
	else:
		_leaf_mat = m
	return m

func _tree(x: float, z: float, rand: RandomNumberGenerator, snow: bool, s: float = 1.0) -> void:
	# 坡度门槛：>≈32° 的陡坡（含边缘山体壁面）不种树——墙排/散布的存量摆位一并被过滤
	if _slope_grad(x, z) > 0.62:
		return
	var gy := terrain_h(x, z)
	var root := Node3D.new()
	root.position = Vector3(x, gy, z)
	root.scale = Vector3.ONE * s
	add_child(root)
	Util.cyl(root, 0.22, 0.36, 3.4, Util.pbr(Color(1, 1, 1), "bark", 0.95, 0.0, Vector2(1, 2)), Vector3(0, 1.7, 0), 8)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 3.3, 0)
	root.add_child(pivot)
	if _leaf_card_mesh == null:
		_leaf_card_mesh = PlaneMesh.new()
		_leaf_card_mesh.size = Vector2(2.0, 1.6)
	var mat := _leaf_material(snow)
	# 球芯给体积（叶团贴图裹球），外层叶团卡破轮廓——不再是光滑绿球、也不是单叶贴纸
	for off in [Vector3(0, 1.35, 0), Vector3(0.75, 0.8, 0.3), Vector3(-0.7, 0.9, -0.3)]:
		var core := Util.sph(pivot, 1.25, mat, off, 12, 9)
		core.scale = Vector3(1.15, 0.88, 1.15)
	for c in [[0.0, 1.5, 0.0, 2.1], [1.25, 0.85, 0.45, 1.6], [-1.2, 0.95, -0.45, 1.6], [0.4, 0.8, 1.2, 1.5], [-0.45, 0.85, -1.2, 1.5]]:
		var card := MeshInstance3D.new()
		card.mesh = _leaf_card_mesh
		card.material_override = mat
		card.position = Vector3(c[0], c[1], c[2])
		card.scale = Vector3.ONE * float(c[3])
		card.rotation.y = rand.randf() * TAU
		pivot.add_child(card)
	var top := MeshInstance3D.new()
	top.mesh = _leaf_card_mesh
	top.material_override = mat
	top.position = Vector3(0, 2.3, 0)
	top.scale = Vector3.ONE * 1.9
	top.rotation.x = -PI / 2.0
	pivot.add_child(top)
	_sway.append({"pivot": pivot, "phase": rand.randf() * TAU})
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.5 * s, "h": 3.0 * s, "y0": gy})
	var tt := TreeTarget.new()
	tt.hit_x = x
	tt.hit_y = gy + 4.4 * s
	tt.hit_z = z
	tt.hit_r = 1.6 * s
	var crown := Vector3(x, gy + 4.4 * s, z)
	tt.on_leaf = func() -> void: _leaf_burst(crown, snow)
	_tree_targets.append(tt)

## 树冠中弹：一次性落叶爆发（4 路并发上限，粒子播完自动回收）
func _leaf_burst(pos: Vector3, snow: bool) -> void:
	if _leaf_fx.size() >= 4:
		return
	var p := GPUParticles3D.new()
	p.amount = 14
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, -1.6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.9, 0.95) if snow else Color(0.35, 0.55, 0.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_leaf_fx.append({"p": p, "t": 0.0})

## 草地毯：MultiMesh 一次绘制成千上万株草丛（十字卡+叶团贴图），避开河道/营地垫/陡坡
func _grass_field(count: int, snow: bool, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var base := 0
	for rot in [0.0, PI / 2.0]:
		var c := cos(rot)
		var s := sin(rot)
		var corners := [Vector2(-0.48, 0.0), Vector2(0.48, 0.0), Vector2(0.48, 0.9), Vector2(-0.48, 0.9)]
		# 每张卡正反绕序各一份 + 材质单面剔除：双面材质会把背面法线翻成朝下，
		# 只吃到 HDRI 下半球的近黑环境光 → 背向卡片纯黑（远看一团团黑饼）；双绕序让可见面恒为正面
		for flip in [0, 1]:
			for k in 4:
				var lx: float = corners[k].x
				verts.append(Vector3(lx * c, corners[k].y, lx * s))
				norms.append(Vector3.UP)
				# UV 只取叶团实心区（原图叶团仅占中心约六成）：单卡 alpha 密度↑，远看不塌成暗点
				var uu: float = (corners[k].x + 0.48) / 0.96
				var vv: float = corners[k].y / 0.9
				uvs.append(Vector2(0.13 + uu * 0.74, 0.10 + vv * 0.80))
			if flip == 0:
				idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			else:
				idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			base += 4
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var transforms: Array = []
	var guard := 0
	while transforms.size() < count and guard < count * 40:
		guard += 1
		var x := rng.randf_range(-(width / 2.0 - 15.0), width / 2.0 - 15.0)
		var z := rng.randf_range(-length + 14.0, 22.0)
		if _terr_river and absf(z - river_center_z(x)) < 7.0:
			continue
		var on_pad := false
		for p in _pads:
			var dx := x - float(p["x"])
			var dz := z - float(p["z"])
			var pr := float(p["r"]) * 0.75
			if dx * dx + dz * dz < pr * pr:
				on_pad = true
				break
		if on_pad:
			continue
		var y := terrain_h(x, z)
		if absf(terrain_h(x + 1.2, z) - y) + absf(terrain_h(x, z + 1.2) - y) > 1.1:
			continue
		var sc := rng.randf_range(0.6, 1.3) # UV 裁进实心区后叶团显得更满，缩放略收回
		transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, y - 0.03, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	_grass_mm = mm # 供「穿草让开」逐株回写
	_grass_base = transforms
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.material_override = _grass_field_mat(snow)
	mmi.custom_aabb = AABB(Vector3(-width / 2.0 - 20.0, -6.0, -length - 30.0), Vector3(width + 40.0, 46.0, length + 90.0))
	add_child(mmi)

func _fern(x: float, z: float, rand: RandomNumberGenerator) -> void:
	if _slope_grad(x, z) > 0.95:
		return
	if _fern_scene == null:
		_fern_scene = load("res://assets/veg/fern_02.glb")
	var f := _fern_scene.instantiate() as Node3D
	f.position = Vector3(x, get_support_y(x, z, 999.0), z)
	f.rotation.y = rand.randf() * TAU
	f.scale = Vector3.ONE * rand.randf_range(1.1, 1.9)
	add_child(f)

var _grass_mat_c: Material = null
var _gfield_mat: Material = null
var _gfield_mat_snow: Material = null

## 草原地毯专用材质：贴图已经过色彩校正（内容批 B 线 grass_grade.py）——旧版在叶团图上
## 再增亮 ×1.55 均值达 (98,113,37)，在 HDRI 天空 IBL 下整团荧光发白；现 grass=(54,79,27)、
## cluster=(65,82,28) 深橄榄绿，与地面贴图同调。重跑校正前须先从备份还原原图（见 内容B进度.md）
func _grass_field_mat(snow: bool) -> Material:
	if snow and _gfield_mat_snow:
		return _gfield_mat_snow
	if not snow and _gfield_mat:
		return _gfield_mat
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/tex/foliage_grass_snow_bleed.png" if snow else "res://assets/tex/foliage_grass_bleed.png")
	m.texture_filter = 5 # 各向异性过滤
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.2
	# 不设 CULL_DISABLED：网格已双绕序，单面剔除保证可见面恒为正面（见 _grass_field 注释）
	m.roughness = 1.0
	if snow:
		_gfield_mat_snow = m
	else:
		_gfield_mat = m
	return m

func _grass_mat() -> Material:
	if _grass_mat_c == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/tex/foliage_cluster_bleed.png")
		m.texture_filter = 5 # 各向异性过滤
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.2
		# 不设 CULL_DISABLED：单株草网格已双绕序（见 _shrub_mesh）
		m.roughness = 1.0
		_grass_mat_c = m
	return _grass_mat_c

## 草丛：叶团贴图十字卡，挂进 _sway 随风摆
func _grass(x: float, z: float, rand: RandomNumberGenerator) -> void:
	if _slope_grad(x, z) > 0.95:
		return
	var pivot := Node3D.new()
	pivot.position = Vector3(x, get_support_y(x, z, 999.0), z)
	add_child(pivot)
	var h := rand.randf_range(0.55, 0.95)
	# 与草原同款双绕序十字网格（原 PlaneMesh+双面材质有同样的背面纯黑问题）
	var card := MeshInstance3D.new()
	card.mesh = _shrub_mesh()
	card.material_override = _grass_mat()
	card.scale = Vector3(1.0, h / 0.9, 1.0)
	card.rotation.y = rand.randf_range(-0.3, 0.3)
	pivot.add_child(card)
	_sway.append({"pivot": pivot, "phase": rand.randf() * TAU})

var _shrub_mesh_c: ArrayMesh = null

## 单株草十字网格：宽 0.85 高 0.9、双绕序、全幅 UV（与改前 PlaneMesh 观感对齐）
func _shrub_mesh() -> ArrayMesh:
	if _shrub_mesh_c:
		return _shrub_mesh_c
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var base := 0
	for rot in [0.0, PI / 2.0]:
		var c := cos(rot)
		var s := sin(rot)
		var corners := [Vector2(-0.425, 0.0), Vector2(0.425, 0.0), Vector2(0.425, 0.9), Vector2(-0.425, 0.9)]
		for flip in [0, 1]:
			for k in 4:
				var lx: float = corners[k].x
				verts.append(Vector3(lx * c, corners[k].y, lx * s))
				norms.append(Vector3.UP)
				uvs.append(Vector2((corners[k].x + 0.425) / 0.85, corners[k].y / 0.9))
			if flip == 0:
				idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			else:
				idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			base += 4
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_shrub_mesh_c = ArrayMesh.new()
	_shrub_mesh_c.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _shrub_mesh_c

## 环境漂浮微粒（丛林光尘/瀑布水雾）：软点贴图 + 广告牌四边形
func _add_motes(count: int, tint: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 10.0
	p.preprocess = 10.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width / 2.0 + 4.0, 2.6, length / 2.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.12, 0.03, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var qm := StandardMaterial3D.new()
	qm.albedo_texture = load("res://assets/tex/mote.png")
	qm.albedo_color = tint
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qm
	p.draw_pass_1 = quad
	p.position = Vector3(0, 2.4, 26.0 - length / 2.0)
	p.visibility_aabb = AABB(Vector3(-40, -6, -length - 20), Vector3(80, 16, length + 40))
	add_child(p)

## 实体岩体簇：2-3 块带体积的岩石贴图球岩叠放，每块各配与视觉对齐的碰撞。
## （退役原 rock_face_01 崖壁扫描面片：单面无厚度、放大后像纸片，且碰撞只在基座，
##   用户实测「山不是 3D 的、子弹穿山」——2026-11-12 三修）
## 内容批：噪声岩石网格——单位球经 3D 值噪声径向扰动，告别压扁光球；4 个种子变体缓存轮换
var _rock_variants: Array = []

func _hash3(ix: int, iy: int, iz: int, seed_v: float) -> float:
	var s := sin(float(ix) * 127.1 + float(iy) * 269.5 + float(iz) * 311.7 + seed_v * 74.7) * 43758.5453
	return s - floorf(s)

func _n3(p: Vector3, seed_v: float) -> float:
	var ix := int(floor(p.x))
	var iy := int(floor(p.y))
	var iz := int(floor(p.z))
	var fx := p.x - float(ix)
	var fy := p.y - float(iy)
	var fz := p.z - float(iz)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var c000 := _hash3(ix, iy, iz, seed_v)
	var c100 := _hash3(ix + 1, iy, iz, seed_v)
	var c010 := _hash3(ix, iy + 1, iz, seed_v)
	var c110 := _hash3(ix + 1, iy + 1, iz, seed_v)
	var c001 := _hash3(ix, iy, iz + 1, seed_v)
	var c101 := _hash3(ix + 1, iy, iz + 1, seed_v)
	var c011 := _hash3(ix, iy + 1, iz + 1, seed_v)
	var c111 := _hash3(ix + 1, iy + 1, iz + 1, seed_v)
	return lerpf(lerpf(lerpf(c000, c100, ux), lerpf(c010, c110, ux), uy), lerpf(lerpf(c001, c101, ux), lerpf(c011, c111, ux), uy), uz)

func _noisy_rock_mesh(seed_v: float) -> ArrayMesh:
	var rings := 10 # 纬线（不含两极点行，极点单独成顶点）
	var segs := 14
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(0, 1, 0))
	uvs.append(Vector2(0.5, 0.0))
	for ri in rings:
		var phi := PI * float(ri + 1) / float(rings + 1)
		for si in segs:
			var theta := TAU * float(si) / float(segs)
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var disp := 1.0 + (_n3(dir * 1.9, seed_v) - 0.5) * 0.52 + (_n3(dir * 4.3, seed_v * 1.7) - 0.5) * 0.2
			verts.append(dir * disp)
			uvs.append(Vector2(float(si) / float(segs), float(ri + 1) / float(rings + 1)))
	var bot := verts.size()
	verts.append(Vector3(0, -1, 0))
	uvs.append(Vector2(0.5, 1.0))
	# 极点扇
	for si in segs:
		var a := 1 + si
		var b := 1 + (si + 1) % segs
		idx.append_array([0, b, a])
		var la := 1 + (rings - 1) * segs + si
		var lb := 1 + (rings - 1) * segs + (si + 1) % segs
		idx.append_array([bot, la, lb])
	for ri in rings - 1:
		for si in segs:
			var a := 1 + ri * segs + si
			var b := 1 + ri * segs + (si + 1) % segs
			var c := a + segs
			var dd := b + segs
			idx.append_array([a, b, c, b, dd, c])
	# 平滑法线：面法线累加后归一（经度索引回绕 → 无接缝法线）
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		var fn := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		norms[ia] += fn
		norms[ib] += fn
		norms[ic] += fn
	for vi in norms.size():
		norms[vi] = norms[vi].normalized()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _rock_variant(rand: RandomNumberGenerator) -> ArrayMesh:
	if _rock_variants.is_empty():
		for sv in [3.1, 7.7, 12.3, 19.9]:
			_rock_variants.append(_noisy_rock_mesh(sv))
	return _rock_variants[rand.randi_range(0, _rock_variants.size() - 1)]

func _boulder(x: float, z: float, rand: RandomNumberGenerator) -> void:
	var base_y := get_support_y(x, z, 999.0)
	var n := rand.randi_range(2, 3)
	var main_s := rand.randf_range(1.3, 2.1)
	for i in n:
		var s := main_s * (1.0 if i == 0 else rand.randf_range(0.45, 0.65))
		var ox := 0.0 if i == 0 else rand.randf_range(-1.0, 1.0) * main_s * 0.7
		var oz := 0.0 if i == 0 else rand.randf_range(-1.0, 1.0) * main_s * 0.7
		var rock := MeshInstance3D.new()
		rock.mesh = _rock_variant(rand)
		rock.material_override = Util.pbr(Color(0.9, 0.87, 0.8), "rock", 0.95, 0.0, Vector2(2, 2))
		rock.position = Vector3(x + ox, base_y + s * 0.26, z + oz)
		rock.scale = Vector3(s * rand.randf_range(1.0, 1.35), s * rand.randf_range(0.6, 0.85), s * rand.randf_range(0.9, 1.2))
		rock.rotation.y = rand.randf() * TAU
		add_child(rock)
		var bc := _add_collider({"type": "circle", "x": x + ox, "z": z + oz, "r": s * 1.0, "h": s * 1.15, "y0": base_y})
		bc["cover"] = true # 1.2.0：岩石掩体登记（hard 全挡+挡视线，cover 标记供躲掩体 AI 检索）

func _quiver(x: float, z: float, rand: RandomNumberGenerator) -> void:
	if _slope_grad(x, z) > 0.62:
		return
	if _quiver_scene == null:
		_quiver_scene = load("res://assets/veg/quiver_tree_02.glb")
	var t := _quiver_scene.instantiate() as Node3D
	t.position = Vector3(x, terrain_h(x, z), z)
	t.rotation.y = rand.randf() * TAU
	t.scale = Vector3.ONE * rand.randf_range(0.8, 1.15)
	add_child(t)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.6, "h": 3.0, "y0": terrain_h(x, z)})

func _rock(x: float, z: float, rand: RandomNumberGenerator, scale_r: float = 0.9) -> void:
	var gy := terrain_h(x, z)
	var rock := MeshInstance3D.new()
	rock.mesh = _rock_variant(rand)
	rock.material_override = Util.pbr(Color(0.85, 0.82, 0.75), "rock", 0.95, 0.0, Vector2(1.5, 1.5))
	rock.position = Vector3(x, gy + scale_r * 0.36, z)
	rock.scale = Vector3(1.2, 0.75, 1.0) * scale_r
	rock.rotation.y = rand.randf() * TAU
	add_child(rock)
	var rc := _add_collider({"type": "circle", "x": x, "z": z, "r": scale_r * 0.8, "h": scale_r, "y0": gy})
	rc["cover"] = true # 1.2.0：岩石掩体登记（同 _boulder）

func _theme_jungle() -> void:
	var rand := Util.seeded(1101 + level_index * 77)
	var d := 6.0
	while d < length + 20.0:
		for s in [-1.0, 1.0]:
			if rand.randf() > 0.25:
				_tree(s * (width / 2.0 + 2.4 + rand.randf() * 3.0), 26.0 - d, rand, false, rand.randf_range(0.9, 1.6))
		d += 7.0
	_scatter(rand, 30, func(x, z, r): _add_crate(x, z, 1.1, 1.1, 1.1, Util.pbr(Color(1, 1, 1), "planks", 0.9, 0.0, Vector2.ONE)))
	_scatter(rand, 64, func(x, z, r): _rock(x, z, r))
	_scatter(rand, 24, func(x, z, r): _fern(x, z, r))
	_scatter(rand, 8, func(x, z, r): _boulder(x, z, r))
	_scatter(rand, 16, func(x, z, r): _grass(x, z, r))
	# 林地内部再散布大小树（大树成荫、小树点缀），全图铺草地毯
	_scatter(rand, 12, func(x, z, r): _tree(x, z, r, false, r.randf_range(0.55, 1.5)))
	_scatter(rand, 5, Callable(self, "_log"))
	_scatter(rand, 2, Callable(self, "_stele"))
	_grass_field(int(2600.0 * _grass_scale), false, 5150)
	_add_motes(42, Color(1, 0.95, 0.8, 0.8))
	# 河（沿 river_center_z 蜿蜒的带状水面，与地形下切的河道对齐）+ 爆裂木桥（原作第1关标志）
	_bridge_z = river_center_z(0.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.32, 0.48, 0.88)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.12
	wm.metallic = 0.15
	wm.normal_texture = Util.tex_nor("jungle")
	wm.texture_repeat = 1 # TEXTURE_REPEAT_ENABLED
	wm.uv1_scale = Vector3(6, 2, 1)
	var wverts := PackedVector3Array()
	var wnorms := PackedVector3Array()
	var wuvs := PackedVector2Array()
	var widx := PackedInt32Array()
	var wsteps := 44
	for i in wsteps + 1:
		var x := -width / 2.0 - 16.0 + float(i) / float(wsteps) * (width + 32.0)
		var cz := river_center_z(x)
		wverts.append(Vector3(x, -0.5, cz - 5.75))
		wverts.append(Vector3(x, -0.5, cz + 5.75))
		wnorms.append(Vector3.UP)
		wnorms.append(Vector3.UP)
		wuvs.append(Vector2(x / 6.0, 0.0))
		wuvs.append(Vector2(x / 6.0, 1.9))
		if i < wsteps:
			var a := i * 2
			widx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var warr := []
	warr.resize(Mesh.ARRAY_MAX)
	warr[Mesh.ARRAY_VERTEX] = wverts
	warr[Mesh.ARRAY_NORMAL] = wnorms
	warr[Mesh.ARRAY_TEX_UV] = wuvs
	warr[Mesh.ARRAY_INDEX] = widx
	var wmesh := ArrayMesh.new()
	wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warr)
	var water := MeshInstance3D.new()
	water.mesh = wmesh
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	_scroll_mats.append({"mat": wm, "speed": 0.35})
	_bridge_mesh = _add_box(0, _bridge_z, 5.5, 13.5, 0.35, Util.pbr(Color(1, 1, 1), "planks", 0.9, 0.0, Vector2(2, 4)), -0.1)
	if data.has("outpost"):
		_build_outpost(false)

func _theme_base() -> void:
	var rand := Util.seeded(2202 + level_index * 77)
	# 1.2.0：仅第 2 关（theme=base）净高 ×4 做通天大厅——侧墙 9.0→36、天花板净高 8.6→34.4、灯带随之；
	# 第 4 关（theme=base2）同函数但维持原高。墙面贴图纵向重复同步放大，免得拉成糊墙。
	var tall := String(data["theme"]) == "base"
	var wall_h := 36.0 if tall else 9.0
	var ceil_y := 34.4 if tall else 8.6
	var strip_y := 34.0 if tall else 8.5
	var wall_mat := Util.pbr(Color(0.85, 0.88, 0.95), "metal", 0.5, 0.65, Vector2(6, 8.0) if tall else Vector2(6, 2.0))
	# 侧墙带真实碰撞（1.1.0 空气墙根因修复：旧版无碰撞、全靠玩家钳制挡人，钳制线又远在墙内）；
	# 起点前移补住出生点身后 z∈(26,42) 的墙列缺口。墙高 6.5→9.0（净高修复，见下天花板）
	var d := -16.0
	while d < length + 30.0:
		for s in [-1.0, 1.0]:
			_add_box(s * (width / 2.0 + 1.4), 26.0 - d - 7.5, 1.6, 15.0, wall_h, wall_mat)
		d += 15.0
	d = 14.0
	while d < length:
		# 天花板梁板：净高 6.2→8.6（1.1.0 用户反馈房间太低；与能量关 7m 立柱+通高、仓库通高对齐量级）
		_add_box(0, 26.0 - d, width + 2.0, 0.8, 0.5, Util.pbr(Color(0.13, 0.15, 0.18), "", 0.6, 0.5), ceil_y, false)
		var strip_m := Util.glow(Color(0.55, 0.8, 1.0), 1.8)
		var strip := Util.box(self, Vector3(width - 2.0, 0.08, 0.3), strip_m, Vector3(0, strip_y, 26.0 - d))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blink_mats.append({"mat": strip_m, "phase": d})
		if tall:
			# 大厅防黑：两侧墙面在 12m / 23m 高处各加一条纵向光带（与天花板灯带同节拍闪烁体系）
			for s in [-1.0, 1.0]:
				for wy in [12.0, 23.0]:
					var wm2 := Util.glow(Color(0.55, 0.8, 1.0), 1.5)
					var ws := Util.box(self, Vector3(0.18, 0.3, 13.0), wm2, Vector3(s * (width / 2.0 + 0.45), wy, 26.0 - d))
					ws.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_blink_mats.append({"mat": wm2, "phase": d + wy})
		d += 22.0
	_scatter(rand, 24, func(x, z, r): _add_box(x, z, 1.2, 1.2, 1.2, Util.pbr(Color(0.6, 0.65, 0.55), "metal", 0.6, 0.5)))
	_scatter(rand, 9, Callable(self, "_make_barrel"))
	# 两侧灯柱阵列：基地的纵深感靠它们一列排开
	var ld := 12.0
	var lside := 1.0
	while ld < length:
		_lamp(lside * (width / 2.0 - 3.2), 26.0 - ld, rand)
		lside = -lside
		ld += 17.0
	# 双墙根维修道（调平表 §3.2）：沿左右墙根各一条掩体带——木箱/油桶交替成列，
	# 与感应器交错偏置配套：走墙根线有掩体可依、但有巡逻/滚雷伏击（数据层营地），中央线最短但交叉火力全开。
	# 三条接近线长度差 <3%（同为全程纵深），只是风险结构不同；电网门全宽封锁不变，无任何绕门通道。
	var lane_x := width / 2.0 - 5.5
	var md := 16.0
	var mi := 0
	while md < length - 12.0:
		var near_gate := false
		for gd in data.get("gates", []):
			if absf(md - float(gd)) < 3.5:
				near_gate = true
		if not near_gate:
			for s in [-1.0, 1.0]:
				var jx: float = s * lane_x + rand.randf_range(-0.5, 0.5)
				var jz: float = 26.0 - md + rand.randf_range(-1.2, 1.2)
				if (mi + (0 if s < 0.0 else 1)) % 2 == 0:
					_add_crate(jx, jz, 1.15, 1.15, 1.15, Util.pbr(Color(1, 1, 1), "planks", 0.9, 0.0, Vector2.ONE))
				else:
					_make_barrel(jx, jz, rand)
		md += 13.0
		mi += 1
	# 夹层高点（1.1.0 第二线）：室内关没有地形起伏，用多层平台做可站人的高点（数据层 mezzanines 驱动）
	for mz_spec in data.get("mezzanines", []):
		_build_mezzanine(float(mz_spec[0]), float(mz_spec[1]), float(mz_spec[2]), float(mz_spec[3]), float(mz_spec[4]))

func _make_barrel(x: float, z: float, _r: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var node := Util.cyl(self, 0.42, 0.42, 1.15, Util.pbr(Color(0.9, 0.5, 0.35), "rust", 0.6, 0.5), Vector3(x, gy + 0.58, z), 12)
	var col := _add_collider({"type": "circle", "x": x, "z": z, "r": 0.5, "h": 1.15, "y0": gy})
	var bt := BarrelTarget.new()
	bt.pos = Vector3(x, gy + 0.58, z)
	bt.hit_x = x
	bt.hit_y = gy + 0.58
	bt.hit_z = z
	bt.node = node
	bt.col = col
	bt.on_boom = _detonate_barrel
	barrels.append(bt)

## 油桶爆炸：范围杀伤（敌 80 伤/3.4m、玩家 1 格/2.2m）+ 邻桶延迟 0.12 秒连锁引爆
func _detonate_barrel(bt) -> void:
	if not bt.alive:
		return
	bt.alive = false
	bt.targetable = false
	if bt.node != null and is_instance_valid(bt.node):
		bt.node.queue_free()
	bt.col["disabled"] = true
	_ctx["projectiles"].spawn_explosion_fx(bt.pos, 2.6)
	AudioSys.play("explosion", -4.0)
	for e in enemies:
		if e.alive and e.global_position.distance_to(bt.pos) < 3.4:
			e.on_hit(80, e.global_position + Vector3(0, 1.0, 0))
	if _player_ref != null and is_instance_valid(_player_ref) and _player_ref.alive:
		if _player_ref.global_position.distance_to(bt.pos) < 2.2:
			_player_ref.take_damage(1)
	for other in barrels:
		if other != bt and other.alive:
			var queued := false
			for pb in _pending_booms:
				if pb["bt"] == other:
					queued = true
					break
			if not queued and other.pos.distance_to(bt.pos) < 3.5:
				_pending_booms.append({"t": 0.12, "bt": other})

## 场景细道具（每关按主题铺，都有真实碰撞，不是贴纸）
func _log(x: float, z: float, rand: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var g := Node3D.new()
	g.position = Vector3(x, gy, z)
	g.rotation.y = rand.randf() * TAU
	add_child(g)
	var log := Util.cyl(g, 0.3, 0.34, 3.8, Util.pbr(Color(1, 1, 1), "bark", 0.95, 0.0, Vector2(2.5, 1)), Vector3(0, 0.32, 0), 10)
	log.rotation.z = PI / 2.0
	Util.cyl(g, 0.29, 0.29, 0.06, Util.pbr(Color(0.85, 0.72, 0.5), "", 0.9), Vector3(1.92, 0.32, 0), 10).rotation.z = PI / 2.0
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.55, "h": 0.7, "y0": gy})

func _stele(x: float, z: float, rand: RandomNumberGenerator) -> void:
	_add_box(x, z, 0.95, 0.3, 1.7, Util.pbr(Color(0.9, 0.88, 0.82), "rock", 0.95, 0.0, Vector2(1, 1.6)), terrain_h(x, z))

func _lamp(x: float, z: float, _r: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var pole_m := Util.pbr(Color(0.16, 0.17, 0.19), "", 0.5, 0.7)
	Util.cyl(self, 0.055, 0.085, 3.5, pole_m, Vector3(x, gy + 1.75, z), 8)
	var head := Util.box(self, Vector3(0.55, 0.13, 0.26), Util.glow(Color(1, 0.8, 0.45), 1.6), Vector3(x, gy + 3.55, z))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.16, "h": 3.5, "y0": gy})

func _ice_rock(x: float, z: float, rand: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var s := rand.randf_range(0.8, 1.7)
	var rock := MeshInstance3D.new()
	rock.mesh = _rock_variant(rand)
	rock.material_override = Util.pbr(Color(0.78, 0.88, 1.0), "rock", 0.55, 0.05, Vector2(1.5, 1.5))
	rock.position = Vector3(x, gy + s * 0.32, z)
	rock.scale = Vector3(1.25, 0.7, 1.0) * s
	rock.rotation.y = rand.randf() * TAU
	add_child(rock)
	var ic := _add_collider({"type": "circle", "x": x, "z": z, "r": s * 0.8, "h": s, "y0": gy})
	ic["cover"] = true # 1.2.0：冰岩掩体登记（同 _rock）

func _shelf(x: float, z: float, rand: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var rot90 := rand.randf() > 0.5
	var g := Node3D.new()
	g.position = Vector3(x, gy, z)
	g.rotation.y = PI / 2.0 if rot90 else 0.0
	add_child(g)
	var frame_m := Util.pbr(Color(0.3, 0.32, 0.36), "metal", 0.55, 0.6)
	for sx in [-1.1, 1.1]:
		Util.box(g, Vector3(0.09, 2.4, 0.55), frame_m, Vector3(sx, 1.2, 0))
	for lvl in [0.35, 1.15, 1.95]:
		Util.box(g, Vector3(2.3, 0.07, 0.55), frame_m, Vector3(0, lvl, 0))
		Util.box(g, Vector3(0.5, 0.42, 0.44), Util.pbr(Color(1, 1, 1), "planks", 0.9), Vector3(rand.randf_range(-0.8, 0.2), lvl + 0.25, 0))
		Util.box(g, Vector3(0.42, 0.36, 0.4), Util.pbr(Color(0.6, 0.63, 0.58), "metal", 0.6, 0.5), Vector3(rand.randf_range(0.3, 0.85), lvl + 0.22, 0))
	_add_collider({"type": "box", "x": x, "z": z, "w": 0.7 if rot90 else 2.4, "d": 2.4 if rot90 else 0.7, "h": 2.4, "y0": gy})

## 长货架单元（沿 z 长 7m）：仓库纵列专用，与 _shelf 同构（三层板+杂物箱），碰撞与视觉对齐
func _shelf_long(x: float, z: float, rand: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var g := Node3D.new()
	g.position = Vector3(x, gy, z)
	add_child(g)
	var frame_m := Util.pbr(Color(0.3, 0.32, 0.36), "metal", 0.55, 0.6)
	for pz in [-3.4, 3.4]:
		Util.box(g, Vector3(0.55, 2.4, 0.09), frame_m, Vector3(0, 1.2, pz))
	for lvl in [0.35, 1.15, 1.95]:
		Util.box(g, Vector3(0.55, 0.07, 7.0), frame_m, Vector3(0, lvl, 0))
		Util.box(g, Vector3(0.44, 0.42, rand.randf_range(0.8, 1.6)), Util.pbr(Color(1, 1, 1), "planks", 0.9), Vector3(0, lvl + 0.25, rand.randf_range(-2.6, 0.5)))
		Util.box(g, Vector3(0.4, 0.36, rand.randf_range(0.7, 1.2)), Util.pbr(Color(0.6, 0.63, 0.58), "metal", 0.6, 0.5), Vector3(0, lvl + 0.22, rand.randf_range(0.9, 2.7)))
	_add_collider({"type": "box", "x": x, "z": z, "w": 0.7, "d": 7.2, "h": 2.4, "y0": gy})

func _theme_waterfall() -> void:
	var rand := Util.seeded(3303)
	var d := 0.0
	while d < length + 24.0:
		for s in [-1.0, 1.0]:
			_rock(s * (width / 2.0 + 2.8), 26.0 - d, rand, 2.6)
		d += 12.0
	# 开放版：台阶箱阵列退役——整面山坡由地形爬升（ramp）承担，沿坡做三段贴地水帘（山溪瀑布）+ 坡脚水潭
	terrace_top_y = _terr_ramp
	# 内容批：水帘换程序生成的条纹 alpha 贴图 + 受光材质（原为 UNSHADED 纯蓝板）；
	# 双层错速滚动做纵深，帘脚与潭面各铺泡沫盘，潭面独立慢滚材质
	var fall_tex: Texture2D = load("res://assets/tex/waterfall_alpha.png")
	var foam_tex: Texture2D = load("res://assets/tex/foam_disc.png")
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = fall_tex
	fm.albedo_color = Color(0.85, 0.94, 1.0, 1.0)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.roughness = 0.18
	fm.normal_texture = Util.tex_nor("jungle")
	fm.texture_repeat = 1 # TEXTURE_REPEAT_ENABLED
	fm.uv1_scale = Vector3(2, 2, 1)
	var fm2 := StandardMaterial3D.new()
	fm2.albedo_texture = fall_tex
	fm2.albedo_color = Color(0.9, 0.97, 1.0, 0.62)
	fm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm2.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm2.roughness = 0.18
	fm2.texture_repeat = 1
	fm2.uv1_scale = Vector3(3, 3, 1)
	fm2.uv1_offset = Vector3(0.37, 0.43, 0)
	var foam_m := StandardMaterial3D.new()
	foam_m.albedo_texture = foam_tex
	foam_m.albedo_color = Color(1, 1, 1, 0.85)
	foam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	foam_m.roughness = 0.6
	foam_m.texture_repeat = 1
	for i in 3:
		var z_c := -64.0 - float(i) * 17.0
		var base_y := terrain_h(-26.0, z_c)
		for layer in 2:
			var sheet := MeshInstance3D.new()
			var sp := PlaneMesh.new()
			sp.size = Vector2(9, 14)
			sheet.mesh = sp
			sheet.material_override = fm if layer == 0 else fm2
			sheet.rotation.x = -0.10 # 顺坡微倾（水往低处流的方向）
			sheet.position = Vector3(-26.0 - 0.7 * float(layer), base_y + 0.3 + 0.4 * float(layer), z_c)
			sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(sheet)
		var foam := MeshInstance3D.new()
		var fp := PlaneMesh.new()
		fp.size = Vector2(8.5, 3.4)
		foam.mesh = fp
		foam.material_override = foam_m
		foam.rotation.x = -0.10
		foam.position = Vector3(-26.0, terrain_h(-26.0, z_c + 6.0) + 0.3, z_c + 6.0)
		foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(foam)
	_scroll_mats.append({"mat": fm, "speed": 1.6})
	_scroll_mats.append({"mat": fm2, "speed": 2.4})
	var pool_m := StandardMaterial3D.new()
	pool_m.albedo_color = Color(0.16, 0.38, 0.62, 0.78)
	pool_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_m.roughness = 0.08
	pool_m.normal_texture = Util.tex_nor("jungle")
	pool_m.texture_repeat = 1
	pool_m.uv1_scale = Vector3(3, 2, 1)
	var pool := MeshInstance3D.new()
	var pp := PlaneMesh.new()
	pp.size = Vector2(15.0, 11.0)
	pool.mesh = pp
	pool.material_override = pool_m
	pool.position = Vector3(-26.0, terrain_h(-26.0, -38.0) + 0.14, -38.0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	_scroll_mats.append({"mat": pool_m, "speed": 0.3})
	var pfoam := MeshInstance3D.new()
	var pfp := PlaneMesh.new()
	pfp.size = Vector2(11.0, 7.5)
	pfoam.mesh = pfp
	pfoam.material_override = foam_m
	pfoam.position = Vector3(-26.0, terrain_h(-26.0, -38.0) + 0.22, -38.0)
	pfoam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pfoam)
	# 潭边一圈噪声岩石收边，压掉潭面的矩形轮廓
	var prand := Util.seeded(7171)
	for pa in 6:
		var ang := TAU * float(pa) / 6.0 + 0.35
		_rock(-26.0 + cos(ang) * 7.6, -38.0 + sin(ang) * 5.6, prand, prand.randf_range(1.0, 1.6))
	if data.has("cave"):
		_build_cave()
	_scatter(rand, 20, func(x, z, r): _add_crate(x, z, 1.1, 1.1, 1.0, Util.pbr(Color(1, 1, 1), "planks", 0.9)))
	_scatter(rand, 20, func(x, z, r): _rock(x, z, r))
	_scatter(rand, 10, func(x, z, r): _grass(x, z, r))
	_scatter(rand, 3, Callable(self, "_log"))
	# 坡面分三股（调平表 §3.3）：ramp 本是全宽均匀爬升、走哪都一样，用摆件切出三条读得出差别的线——
	# 西股·水帘线（x≈-26）：贴三段水帘，落石加密（更新循环里偏置）+ 石像火力，最险，长度与主线相同、以风险补；
	# 中股·主坡：基准线（营地主体所在）；东股·绕脊线（x≈+28）：岩体/倒木掩体成列，最长（绕脊 ≈+8%）、最稳。
	var bd := 34.0
	var bi := 0
	while bd < length - 18.0:
		var bz := 26.0 - bd
		if bi % 2 == 0:
			_boulder(28.0 + rand.randf_range(-2.5, 2.5), bz, rand)
		else:
			_log(27.0 + rand.randf_range(-2.0, 2.0), bz, rand)
		_rock(-37.0 + rand.randf_range(-1.5, 1.5), bz - 6.0, rand, 1.6)
		bd += 15.0
		bi += 1
	_grass_field(int(1500.0 * _grass_scale), false, 5152)
	_add_motes(30, Color(0.85, 0.95, 1, 0.7))

func _theme_snow() -> void:
	var rand := Util.seeded(4404)
	var d := 4.0
	while d < length + 20.0:
		for s in [-1.0, 1.0]:
			if rand.randf() > 0.3:
				_tree(s * (width / 2.0 + 2.5 + rand.randf() * 3.0), 26.0 - d, rand, true, rand.randf_range(0.9, 1.5))
		d += 8.0
	_scatter(rand, 12, Callable(self, "_make_snowbank"))
	_scatter(rand, 9, func(x, z, r): _tree(x, z, r, true, r.randf_range(0.55, 1.3)))
	_scatter(rand, 48, Callable(self, "_ice_rock"))
	_grass_field(int(1300.0 * _grass_scale), true, 5151)
	_snow_extras(rand)
	if data.has("outpost"):
		_build_outpost(true)

func _make_snowbank(x: float, z: float, _r: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var bank := Util.sph(self, 1.5, Util.pbr(Color(1, 1, 1), "snow", 0.9, 0.0, Vector2(2, 2)), Vector3(x, gy - 0.5, z), 10, 7)
	bank.scale = Vector3(1.3, 0.75, 1.0)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 1.5, "h": 1.1, "y0": gy})

func _snow_extras(rand: RandomNumberGenerator) -> void:
	_scatter(rand, 15, func(x, z, r): _add_crate(x, z, 1.15, 1.15, 1.15, Util.pbr(Color(1, 1, 1), "planks", 0.9)))
	# 吹雪（日版独有动态）
	_snow = GPUParticles3D.new()
	_snow.amount = 420
	_snow.lifetime = 7.0
	_snow.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(width / 2.0 + 8.0, 2.0, 45.0)
	pm.direction = Vector3(0.25, -1, 0.1)
	pm.spread = 12.0
	pm.gravity = Vector3(0, -1.6, 0)
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.6
	_snow.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.13)
	quad.material = Util.flat(Color(1, 1, 1, 0.85))
	_snow.draw_pass_1 = quad
	add_child(_snow)

func _theme_energy() -> void:
	var rand := Util.seeded(5505)
	var d := 8.0
	while d < length + 16.0:
		for s in [-1.0, 1.0]:
			Util.cyl(self, 0.55, 0.72, 7.0, Util.pbr(Color(0.9, 0.65, 0.4), "rust", 0.7, 0.5, Vector2(1, 3)), Vector3(s * (width / 2.0 + 1.8), 3.5, 26.0 - d), 12)
		d += 13.0
	d = 16.0
	while d < length:
		var strip := MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = Vector2(width - 4.0, 0.5)
		strip.mesh = sp
		var sm := Util.glow(Color(1, 0.45, 0.1), 1.6)
		strip.material_override = sm
		strip.position = Vector3(0, 0.02, 26.0 - d)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
		_blink_mats.append({"mat": sm, "phase": d * 0.4})
		d += 18.0
	_scatter(rand, 16, func(x, z, r): _add_box(x, z, 1.2, 1.2, 1.3, Util.pbr(Color(0.8, 0.6, 0.4), "rust", 0.75, 0.4)))
	_scatter(rand, 5, Callable(self, "_make_barrel"))
	d = 20.0
	while d < length:
		_quiver((1.0 if int(d) % 52 < 26 else -1.0) * (width / 2.0 + 4.5), 26.0 - d, rand)
		d += 26.0
	_scatter(rand, 12, func(x, z, r): _boulder(x, z, r))
	_scatter(rand, 24, func(x, z, r): _rock(x, z, r))

func _theme_hangar() -> void:
	var rand := Util.seeded(6606)
	var cont_mats := [
		Util.pbr(Color(0.75, 0.62, 0.35), "corrugated", 0.6, 0.55, Vector2(3, 1.5)),
		Util.pbr(Color(0.45, 0.55, 0.62), "corrugated", 0.6, 0.55, Vector2(3, 1.5)),
		Util.pbr(Color(0.6, 0.4, 0.3), "corrugated", 0.6, 0.55, Vector2(3, 1.5)),
	]
	var d := 6.0
	var ci := 0
	while d < length + 20.0:
		for s in [-1.0, 1.0]:
			_add_box(s * (width / 2.0 + 2.4), 26.0 - d - 4.0, 3.4, 7.5, 3.1, cont_mats[ci % cont_mats.size()], 0.0, false)
			ci += 1
		d += 16.0
	_scatter(rand, 25, func(x, z, r): _add_crate(x, z, 1.25, 1.25, 1.25, Util.pbr(Color(1, 1, 1), "planks", 0.9)))
	_scatter(rand, 16, func(x, z, r): _rock(x, z, r))
	# 货架改两排纵列切三巷（调平表 §3.7）：x=±14 两列长货架（每 ~31m 留一个换巷口，两列错开），
	# 切出左/中/右三条货架巷——中巷最直但压顶机+矿车双险，侧巷掩体多、有伏击（数据层营地），三巷等长
	for row_i in 2:
		var sx := -14.0 if row_i == 0 else 14.0
		var sd := 30.0
		var sn := 0
		while sd < length - 24.0:
			if sn % 4 != (2 if row_i == 0 else 3):
				_shelf_long(sx + rand.randf_range(-0.4, 0.4), 26.0 - sd, rand)
			sd += 7.8
			sn += 1
	_scatter(rand, 5, Callable(self, "_make_barrel"))
	for cd in data.get("carts", []):
		var rail := MeshInstance3D.new()
		var rp := PlaneMesh.new()
		rp.size = Vector2(width + 6.0, 1.6)
		rail.mesh = rp
		rail.material_override = Util.pbr(Color(0.16, 0.16, 0.16), "", 0.5, 0.6)
		rail.position = Vector3(0, 0.015, 26.0 - float(cd))
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rail)

func _theme_alien() -> void:
	var rand := Util.seeded(7707)
	var d := 5.0
	while d < length + 16.0:
		for s in [-1.0, 1.0]:
			var blob := Util.sph(self, 1.9 + rand.randf() * 1.2, Util.pbr(Color(0.75, 0.5, 0.62), "alien", 0.5, 0.0, Vector2(2, 2)), Vector3(s * (width / 2.0 + 2.2), 1.2, 26.0 - d), 12, 9)
			blob.scale = Vector3(1, 1.25, 1)
			_pulse.append({"mesh": blob, "phase": rand.randf() * TAU, "base": blob.scale})
		d += 9.0
	d = 20.0
	while d < length - 10.0:
		var arch := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = width / 2.0 + 0.2
		tm.outer_radius = width / 2.0 + 0.75
		tm.rings = 16
		tm.ring_segments = 8
		arch.mesh = tm
		arch.material_override = Util.pbr(Color(0.62, 0.3, 0.45), "alien", 0.55, 0.0, Vector2(4, 1))
		arch.rotation.x = PI / 2.0
		arch.position = Vector3(0, 0.2, 26.0 - d)
		add_child(arch)
		d += 26.0
	# 妖卵 Eggron：靠近孵化把妖虫
	_scatter(rand, 9, Callable(self, "_make_egg"))
	_scatter(rand, 24, func(x, z, r): _rock(x, z, r))
	# 两翼各补 1 簇卵（调平表 §3.8）：堵掉「侧翼全程免费」，绕行也要付孢子压力
	_make_egg(-30.0, 26.0 - length * 0.45, rand)
	_make_egg(-27.0, 26.0 - length * 0.48, rand)
	_make_egg(30.0, 26.0 - length * 0.58, rand)
	_make_egg(27.0, 26.0 - length * 0.61, rand)

func _make_egg(x: float, z: float, _r: RandomNumberGenerator) -> void:
	var gy := terrain_h(x, z)
	var egg := Util.sph(self, 0.8, Util.pbr(Color(0.85, 0.55, 0.65), "alien", 0.45, 0.0, Vector2(1.5, 1.5)), Vector3(x, gy + 0.55, z), 10, 8)
	egg.scale = Vector3(1, 1.25, 1)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.8, "h": 1.2, "y0": gy})
	eggs.append({"mesh": egg, "x": x, "z": z, "hatched": false})

# ---------------- 机关 ----------------
## 内容批：哨塔 + 可进入哨所（第 1/5 关营地）。木构塔身、实体台阶可攀登、塔顶狙击位；
## 两关都无电网门且塔距 Boss 场上百米，登顶只能射击、不能跳关。哨所内有补给 + 鹰徽。
func _build_outpost(snow: bool) -> void:
	var o: Dictionary = data["outpost"]
	var tx := float(o["tx"])
	var tz := float(o["tz"])
	var hx := float(o["hx"])
	var hz := float(o["hz"])
	var wood := Util.pbr(Color(0.92, 0.82, 0.68) if not snow else Color(0.88, 0.82, 0.72), "planks", 0.9, 0.0, Vector2.ONE)
	var darkwood := Util.pbr(Color(0.55, 0.43, 0.3), "planks", 0.95, 0.0, Vector2.ONE)
	var post_m := Util.pbr(Color(0.9, 0.85, 0.8), "bark", 0.95, 0.0, Vector2(1, 2))
	var base := terrain_h(tx, tz)
	# ---- 哨塔：四腿 + 两层横梁环 ----
	for sx in [-1.45, 1.45]:
		for sz in [-1.45, 1.45]:
			Util.cyl(self, 0.17, 0.21, 5.4, post_m, Vector3(tx + sx, base + 2.7, tz + sz), 8)
			_add_collider({"type": "circle", "x": tx + sx, "z": tz + sz, "r": 0.3, "h": 5.4, "y0": base})
	for lvl in [1.6, 3.4]:
		_add_box(tx, tz - 1.45, 3.2, 0.14, 0.22, darkwood, base + lvl, false)
		_add_box(tx, tz + 1.45, 3.2, 0.14, 0.22, darkwood, base + lvl, false)
		_add_box(tx - 1.45, tz, 0.14, 3.2, 0.22, darkwood, base + lvl, false)
		_add_box(tx + 1.45, tz, 0.14, 3.2, 0.22, darkwood, base + lvl, false)
	# 平台（顶面 base+5.2）
	_add_box(tx, tz, 3.7, 3.7, 0.35, wood, base + 4.85)
	var pt := base + 5.2
	# 台阶：南侧直梯式实体踏步（每级升 0.52，在支撑衔接上限内）+ 双弦梁托底
	for i in 10:
		var top_y := base + 0.52 * float(i + 1)
		var sz := tz + 2.26 + float(9 - i) * 0.78
		_add_box(tx, sz, 1.5, 0.84, 0.3, wood, top_y - 0.3)
	for sx in [-0.68, 0.68]:
		var stringer := Util.box(self, Vector3(0.16, 0.42, 9.4), darkwood, Vector3(tx + sx, base + 2.45, tz + 5.7))
		stringer.rotation.x = 0.585 # 坡度 atan(5.2/7.8)，南端低、北端抵平台
		stringer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 栏杆（南侧留出台阶口 1.5m）
	_add_box(tx, tz - 1.79, 3.7, 0.12, 0.85, darkwood, pt)
	_add_box(tx - 1.79, tz, 0.12, 3.7, 0.85, darkwood, pt)
	_add_box(tx + 1.79, tz, 0.12, 3.7, 0.85, darkwood, pt)
	_add_box(tx - 1.3, tz + 1.79, 1.1, 0.12, 0.85, darkwood, pt)
	_add_box(tx + 1.3, tz + 1.79, 1.1, 0.12, 0.85, darkwood, pt)
	# 顶棚（无碰撞：不作支撑面）
	for sx in [-1.55, 1.55]:
		for sz in [-1.55, 1.55]:
			Util.cyl(self, 0.07, 0.07, 2.1, post_m, Vector3(tx + sx, pt + 1.05, tz + sz), 6)
	_add_box(tx, tz, 4.4, 4.4, 0.16, darkwood, pt + 2.1, false)
	if snow:
		_add_box(tx, tz, 4.5, 4.5, 0.1, Util.pbr(Color(0.95, 0.97, 1.0), "", 0.9), pt + 2.26, false)
	# ---- 哨所小屋：木墙围合、西墙留门洞（朝塔） ----
	var floor_y := terrain_h(hx, hz)
	_add_box(hx, hz - 1.9, 4.6, 0.18, 2.6, wood, floor_y)
	_add_box(hx, hz + 1.9, 4.6, 0.18, 2.6, wood, floor_y)
	_add_box(hx + 2.3, hz, 0.18, 3.95, 2.6, wood, floor_y)
	_add_box(hx - 2.3, hz - 1.32, 0.18, 1.15, 2.6, wood, floor_y)
	_add_box(hx - 2.3, hz + 1.32, 0.18, 1.15, 2.6, wood, floor_y)
	_add_box(hx - 2.3, hz, 0.18, 3.95, 0.55, wood, floor_y + 2.05)
	_add_box(hx, hz, 5.3, 4.5, 0.18, darkwood, floor_y + 2.6, false)
	if snow:
		_add_box(hx, hz, 5.4, 4.6, 0.12, Util.pbr(Color(0.95, 0.97, 1.0), "", 0.9), floor_y + 2.78, false)
	# 屋内：木箱 + 暖光灯 + 补给（鹰徽由 data.emblems 布在屋心）
	_add_crate(hx + 1.55, hz + 1.15, 1.0, 1.0, 1.0, wood)
	_add_crate(hx + 1.5, hz - 1.2, 0.8, 0.8, 0.8, wood)
	var lamp_head := Util.sph(self, 0.13, Util.glow(Color(1, 0.72, 0.35), 2.0), Vector3(hx - 1.9, floor_y + 2.0, hz), 8, 6)
	lamp_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pickups.spawn_heal(hx + 0.9, hz - 0.9, floor_y)

## 内容批：瀑布山洞支线（第 3 关）——洞口藏在中段水帘（x=-26、z=-81）西沿之后；
## 岩壁围出洞室，进出同口、汇回主坡，死胡同型支线（只加长度、不成捷径）。
func _build_cave() -> void:
	var cv: Dictionary = data["cave"]
	var cx := float(cv["x"])
	var cz := float(cv["z"])
	var floor_y := terrain_h(cx, cz)
	var rock_m := Util.pbr(Color(0.85, 0.82, 0.75), "rock", 0.95, 0.0, Vector2(2, 2))
	var dark_m := Util.pbr(Color(0.42, 0.4, 0.38), "rock", 1.0, 0.0, Vector2(2, 2))
	var rand := Util.seeded(8181)
	# 三面岩墙（带碰撞，压暗读作崖影）+ 顶板（无碰撞：免支撑面误取屋顶）
	_add_box(cx - 4.4, cz, 1.6, 10.4, 5.0, dark_m, floor_y - 0.4)
	_add_box(cx, cz - 4.9, 10.4, 1.6, 5.0, dark_m, floor_y - 0.4)
	_add_box(cx, cz + 4.9, 10.4, 1.6, 5.0, dark_m, floor_y - 0.4)
	_add_box(cx - 0.4, cz, 11.2, 11.2, 1.8, rock_m, floor_y + 3.3, false)
	# 顶板上压两块噪声巨石破掉平板轮廓（纯视觉：屋顶本就不可站立）
	var cap1 := MeshInstance3D.new()
	cap1.mesh = _rock_variant(rand)
	cap1.material_override = rock_m
	cap1.position = Vector3(cx + 2.0, floor_y + 5.15, cz - 1.6)
	cap1.scale = Vector3(2.7, 1.5, 2.3)
	cap1.rotation.y = 0.7
	add_child(cap1)
	var cap2 := MeshInstance3D.new()
	cap2.mesh = _rock_variant(rand)
	cap2.material_override = rock_m
	cap2.position = Vector3(cx - 2.6, floor_y + 5.0, cz + 2.2)
	cap2.scale = Vector3(2.0, 1.2, 1.8)
	cap2.rotation.y = 2.4
	add_child(cap2)
	# 东口：两块噪声巨石夹出约 3.8m 门洞 + 门楣压顶（带碰撞，只留下方通行）
	_rock(cx + 4.3, cz - 3.9, rand, 2.1)
	_rock(cx + 4.3, cz + 3.9, rand, 2.1)
	_add_box(cx + 4.4, cz, 1.4, 10.4, 1.8, dark_m, floor_y + 3.2)
	# 门楣下倒垂石笋（视觉小件）
	for dz in [-1.6, 0.0, 1.6]:
		var spike := Util.cyl(self, 0.02, 0.3, 1.15, dark_m, Vector3(cx + 4.1, floor_y + 2.6, cz + dz), 7)
		spike.rotation.x = PI
	# 洞内：木箱 + 暖光 + 补给（鹰徽由 data.emblems 布在洞内西侧）
	_add_crate(cx - 2.6, cz + 2.8, 1.0, 1.0, 1.0, Util.pbr(Color(1, 1, 1), "planks", 0.9))
	var lamp_head := Util.sph(self, 0.13, Util.glow(Color(1, 0.72, 0.35), 2.0), Vector3(cx - 3.6, floor_y + 2.3, cz - 3.8), 8, 6)
	lamp_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pickups.spawn_heal(cx + 1.6, cz + 2.6, floor_y)

## 夹层平台（1.1.0 第二线：室内基地关的高点）——钢板平台 + 四角立柱 + 实心台阶（每级 0.5m，
## 在玩家 0.55m 支撑衔接上限内，步行可达）+ 三面栏杆（南面留台阶口）；板下净空 2.65m 可通行
## （碰撞规则有头部净空豁免，不会把平台下走廊堵死）；平台顶直刷狙击+步枪守卫（偏置避开中心鹰徽位）
func _build_mezzanine(mx: float, mz: float, mw: float, md: float, top: float) -> void:
	var slab_m := Util.pbr(Color(0.34, 0.38, 0.44), "metal", 0.55, 0.6, Vector2(3, 2))
	var dark_m := Util.pbr(Color(0.16, 0.17, 0.19), "", 0.5, 0.7)
	_add_box(mx, mz, mw, md, 0.35, slab_m, top - 0.35)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx: float = mx + sx * (mw / 2.0 - 0.6)
			var cz: float = mz + sz * (md / 2.0 - 0.6)
			Util.cyl(self, 0.16, 0.21, top - 0.35, dark_m, Vector3(cx, (top - 0.35) / 2.0, cz), 8)
			_add_collider({"type": "circle", "x": cx, "z": cz, "r": 0.3, "h": top - 0.35, "y0": 0.0})
	var steps := int(round(top / 0.5))
	for i in steps:
		var sty := 0.5 * float(i + 1)
		var stz := mz + md / 2.0 + float(steps - 1 - i) * 0.85 + 0.42
		_add_box(mx, stz, 3.4, 0.85, sty, slab_m)
	# 栏杆：北/东/西三面带碰撞（防走出平台），南面是台阶口不设
	_add_box(mx, mz - md / 2.0 + 0.06, mw, 0.12, 0.85, dark_m, top)
	_add_box(mx - mw / 2.0 + 0.06, mz, 0.12, md, 0.85, dark_m, top)
	_add_box(mx + mw / 2.0 - 0.06, mz, 0.12, md, 0.85, dark_m, top)
	# 平台口发光条（视觉提示：这里能上去）
	var strip := Util.box(self, Vector3(3.4, 0.06, 0.18), Util.glow(Color(1, 0.8, 0.45), 1.6), Vector3(mx, top + 0.03, mz + md / 2.0 - 0.1))
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn_enemy("sniper", mx + 4.0, mz - 1.0)
	_spawn_enemy("rifleman", mx - 4.0, mz + 1.5)

## 场景音效本地播放器（4A 合并接线，素材来自 4C 线 gen_bgm_sfx.py）：位置衰减走
## AudioStreamPlayer3D，不占 AudioSys 固定名单；loop=true 时给 wav 设整段循环（同 AudioSys BGM 口径）
func _make_sfx3d(wav: String, parent_node: Node, local_pos: Vector3, loop: bool = false) -> AudioStreamPlayer3D:
	var pl := AudioStreamPlayer3D.new()
	var p := "res://assets/audio/%s.wav" % wav
	if ResourceLoader.exists(p):
		var s: AudioStream = load(p)
		if loop and s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_data().size() / 2) # 16bit 单声道：字节数/2 = 帧数
		pl.stream = s
	pl.bus = "Master"
	pl.unit_size = 3.0
	pl.max_distance = 70.0
	pl.position = local_pos
	parent_node.add_child(pl)
	return pl

func _build_gate(dist: float, gi: int = 0) -> void:
	var z := 26.0 - dist
	var frame_m := Util.pbr(Color(0.22, 0.25, 0.28), "", 0.5, 0.6)
	_add_box(-(width / 2.0 - 1.0), z, 2, 1, 6, frame_m)
	_add_box(width / 2.0 - 1.0, z, 2, 1, 6, frame_m)
	_add_box(0, z, width, 1, 1, frame_m, 5.0)
	# 感应器交错偏置（调平表 §3.2）：奇偶门轮流贴左右墙根维修道，逼出之字路线；
	# 电网本身仍全宽封锁，不存在绕过门的通道（长度铁律红线）
	var sensor_x := 0.0
	if String(data["theme"]).begins_with("base"):
		sensor_x = (1.0 if gi % 2 == 0 else -1.0) * (width / 2.0 - 14.0)
	var field := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(width - 4.0, 5.0)
	fp.orientation = PlaneMesh.FACE_Z
	field.mesh = fp
	field.material_override = Util.flat(Color(0.2, 0.8, 1, 0.38))
	field.position = Vector3(0, 2.5, z)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	# 电场碰撞必须盖到侧墙：玩家可达半宽放宽后（1.1.0），旧宽 width-3.4 会在门柱(±47)与墙面(±48.6)
	# 之间留出可逐帧挤过的 0.6m 缝——绕门红线，碰撞宽改到 width+3.2 与门柱/墙体搭接
	var collider := _add_collider({"type": "box", "x": 0.0, "z": z, "w": width + 3.2, "d": 0.9, "h": 5.2, "y0": 0.0})
	var sensor := GateSensor.new()
	sensor.pos = Vector3(sensor_x, 3.1, z)
	sensor.hit_x = sensor_x
	sensor.hit_y = 3.1
	sensor.hit_z = z + 0.8
	sensor.projectiles = _ctx["projectiles"]
	var sg := Node3D.new()
	sg.position = Vector3(sensor_x, 3.1, z + 0.8)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.72
	ring.mesh = tm
	ring.material_override = Util.pbr(Color(0.55, 0.55, 0.58), "", 0.35, 0.9)
	sg.add_child(ring)
	Util.sph(sg, 0.42, Util.glow(Color(1, 0.13, 0.13), 3.0), Vector3.ZERO, 12, 9)
	add_child(sg)
	sensor.node = sg
	# 电网电流声：门未开时循环播放（3D 位置衰减），感应器被打掉开门即停
	var zap := _make_sfx3d("gate_zap", self, Vector3(0, 2.5, z), true)
	zap.play()
	var gate := {"dist": dist, "z": z, "field": field, "collider": collider, "sensor": sensor, "open": false}
	sensor.on_open = func():
		collider["disabled"] = true
		field.visible = false
		sg.visible = false
		zap.stop()
		gate["open"] = true
		pickups.spawn_letter(2.5, 3.4, z - 3.5, "+")
	sensor.on_score = _ctx["on_score"]
	sensors.append(sensor)
	gates.append(gate)

func _build_flame(dist: float, i: int) -> void:
	var z := 26.0 - dist
	# 三点成排留缝交替（调平表 §3.6）：每组 3 个喷口（x=-26/0/+26）只留一条安全缝，
	# 缝位随组序轮换（左→中→右），形成真正的三选一节奏门；旧单点喷口对 82m 宽平地毫无分割作用
	var gap := i % 3
	for j in 3:
		if j == gap:
			continue
		_build_one_flame([-26.0, 0.0, 26.0][j], z, float(i) * 1.3 + float(j) * 0.35)

func _build_one_flame(x: float, z: float, phase: float) -> void:
	var gy := terrain_h(x, z)
	Util.cyl(self, 0.55, 0.7, 0.5, Util.pbr(Color(0.5, 0.3, 0.12), "rust", 0.7, 0.5), Vector3(x, gy + 0.25, z), 12)
	var flame := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.85
	cm.height = 4.4
	cm.radial_segments = 10
	flame.mesh = cm
	flame.material_override = Util.glow(Color(1, 0.42, 0.1), 2.2, 0.85)
	flame.position = Vector3(x, gy + 2.4, z)
	flame.visible = false
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	var warn := Util.sph(self, 0.3, Util.glow(Color(1, 0.8, 0.2), 2.0, 0.0), Vector3(x, gy + 0.8, z), 8, 6)
	warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sfx := _make_sfx3d("flame_whoosh", self, Vector3(x, gy + 1.0, z))
	flames.append({"x": x, "z": z, "flame": flame, "warn": warn, "period": 3.4, "phase": phase, "erupting": false, "sfx": sfx})

func _build_cart(dist: float, i: int) -> void:
	var z := 26.0 - dist
	var g := Node3D.new()
	var body_m := Util.pbr(Color(0.5, 0.5, 0.55), "metal", 0.5, 0.7)
	Util.box(g, Vector3(3.2, 1.3, 1.9), body_m, Vector3(0, 0.95, 0))
	var spike_m := Util.pbr(Color(0.75, 0.75, 0.8), "", 0.3, 0.9)
	for s in [-1.0, 1.0]:
		for k in [-1, 0, 1]:
			var spike := Util.cyl(g, 0.01, 0.16, 0.8, spike_m, Vector3(s * 1.95, 0.95, float(k) * 0.55), 6)
			spike.rotation.z = -s * PI / 2.0
	for wx in [-1.1, 1.1]:
		for wz in [-0.7, 0.7]:
			var wheel := Util.cyl(g, 0.3, 0.3, 0.15, Util.pbr(Color(0.1, 0.1, 0.1), "", 0.6, 0.4), Vector3(wx, 0.3, wz), 10)
			wheel.rotation.x = PI / 2.0
	var gy := terrain_h(0.0, z)
	g.position = Vector3(0, gy, z)
	add_child(g)
	var collider := _add_collider({"type": "box", "x": 0.0, "z": z, "w": 3.4, "d": 2.0, "h": 1.7, "y0": gy})
	var csfx := _make_sfx3d("cart_clank", g, Vector3(0, 1.0, 0)) # 挂车体上随车移动
	carts.append({"group": g, "collider": collider, "z": z, "phase": float(i) * 2.1, "speed": 0.55 + float(i) * 0.12, "hit_cd": 0.0, "sfx": csfx})

func _build_crusher(dist: float, i: int) -> void:
	var z := 26.0 - dist
	var g := Node3D.new()
	var steel := Util.pbr(Color(0.6, 0.35, 0.15), "rust", 0.6, 0.5)
	var dark := Util.pbr(Color(0.2, 0.18, 0.16), "", 0.6, 0.5)
	for px in [-2.9, 2.9]:
		Util.box(g, Vector3(0.6, 6.4, 0.6), dark, Vector3(px, 3.2, 0))
	Util.box(g, Vector3(6.4, 0.7, 3.2), dark, Vector3(0, 6.4, 0))
	var press := Node3D.new()
	Util.box(press, Vector3(5.2, 1.15, 3.0), steel, Vector3.ZERO)
	for k in range(-2, 3):
		var tooth := Util.cyl(press, 0.01, 0.18, 0.5, dark, Vector3(float(k) * 1.1, -0.8, 0), 5)
		tooth.rotation.x = PI
	press.position.y = 5.6
	g.add_child(press)
	var gy := terrain_h(0.0, z)
	g.position = Vector3(0, gy, z)
	add_child(g)
	var psfx := _make_sfx3d("crusher_slam", g, Vector3(0, 0.8, 0))
	crushers.append({"group": g, "press": press, "z": z, "y": gy, "period": 4.4, "phase": float(i) * 1.5, "state": "up", "sfx": psfx})

# ---------------- 生成/目标 ----------------
func _spawn_enemy(type: String, x: float, z: float) -> Enemy:
	if type == "akbar" and _terr_river:
		z = river_center_z(x) # 突击水兵就泡在河道里
	var y := get_support_y(x, z, 999.0)
	if type == "akbar" and _terr_river:
		y = -0.55 # 站位取水面（模型自带下潜偏移）
	if type == "sniper":
		var plat := _add_box(x, z, 1.9, 1.9, 2.2, Util.pbr(Color(0.8, 0.76, 0.66), "rock", 0.9, 0.0, Vector2.ONE), y)
		plat.position.y = y + 1.1
		y += 2.2
	var e := Enemy.new()
	add_child(e)
	e.setup(type, Vector3(x, y, z), _enemy_ctx, _ctx["soldier_scenes"])
	# 每敌人独立 ctx 副本：on_score 绑定敌人自身——新版 _die() 在 on_hit 内同步计分
	# （不经更新循环），只有这样才能把类型/位置经 on_kill 通知 main 做飘分/连杀；
	# projectiles/level 等其余键与共享 ctx 保持同一引用，不影响行为
	var ectx: Dictionary = _enemy_ctx.duplicate()
	var base_score: Callable = _enemy_ctx["on_score"]
	ectx["on_score"] = func(pts: int) -> void:
		base_score.call(pts)
		if _ctx.has("on_kill"):
			_ctx["on_kill"].call(pts, type, e.global_position)
	e._ctx = ectx
	enemies.append(e)
	return e

func spawn_minion(type: String, x: float, z: float) -> void:
	_spawn_enemy(type, x, z)

## 雪地脚印：移动体每走 0.35m 落一印（左右交替），上限 240 枚环复用、12 秒渐消（仅雪原）
func _track_footprints(o: Object, dt: float) -> void:
	var pos: Vector3 = (o as Node3D).global_position
	var id := o.get_instance_id()
	if not _trackers.has(id):
		_trackers[id] = {"lpos": pos, "acc": 0.0, "side": 1.0}
		return
	var tr: Dictionary = _trackers[id]
	var lp: Vector3 = tr["lpos"]
	var d := Vector2(pos.x - lp.x, pos.z - lp.z).length()
	tr["lpos"] = pos
	tr["acc"] = float(tr["acc"]) + d
	if float(tr["acc"]) >= 0.35 and d > 0.001:
		tr["acc"] = 0.0
		tr["side"] = -float(tr["side"])
		_drop_footprint(pos, atan2(pos.x - lp.x, pos.z - lp.z), float(tr["side"]))

func _drop_footprint(pos: Vector3, yaw: float, side: float) -> void:
	if _fp_geo == null:
		_fp_geo = PlaneMesh.new()
		_fp_geo.size = Vector2(0.16, 0.34)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var px := pos.x + right.x * 0.14 * side
	var pz := pos.z + right.z * 0.14 * side
	var e: Dictionary
	if _footprints.size() >= 240:
		e = _footprints[_fp_next]
		_fp_next = (_fp_next + 1) % 240
	else:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _fp_geo
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.62, 0.7, 0.85, 0.5)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = m
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		e = {"mesh": mesh, "mat": m, "t": 0.0}
		_footprints.append(e)
	e["t"] = 0.0
	(e["mat"] as StandardMaterial3D).albedo_color.a = 0.5
	var mi := e["mesh"] as MeshInstance3D
	mi.visible = true
	mi.global_position = Vector3(px, terrain_h(px, pz) + 0.02, pz)
	mi.rotation = Vector3(0, yaw, 0)

## 穿草让开：每 0.12 秒扫描，玩家 1.1m 内的草株外倾+下沉避让，离开后恢复基变换
func _update_grass_bend(ppos: Vector3) -> void:
	if _grass_mm == null:
		return
	var still: Dictionary = {}
	for i in _grass_base.size():
		var xf: Transform3D = _grass_base[i]
		var dx := xf.origin.x - ppos.x
		var dz := xf.origin.z - ppos.z
		if dx * dx + dz * dz < 1.21:
			still[i] = true
			if not _grass_bent.has(i):
				var away := Vector3(dx, 0, dz)
				if away.length() < 0.05:
					away = Vector3(0, 0, 1)
				away = away.normalized()
				var bent := xf
				bent.basis = Basis(away, 0.5) * xf.basis
				bent.origin.y = xf.origin.y - 0.22
				_grass_mm.set_instance_transform(i, bent)
				_grass_bent[i] = true
	for i in _grass_bent.keys():
		if not still.has(i):
			_grass_mm.set_instance_transform(i, _grass_base[i])
			_grass_bent.erase(i)

func get_targets() -> Array:
	var out: Array = []
	for e in enemies:
		if e.alive:
			out.append(e)
	if boss:
		for p in boss.targets:
			if p.alive:
				out.append(p)
	for s in sensors:
		if s.alive:
			out.append(s)
	var f = pickups.get_falcon_target()
	if f:
		out.append(f)
	for b in barrels:
		if b.alive:
			out.append(b)
	out.append_array(_tree_targets) # 树冠垫底：子弹按序首中，真目标永远优先
	return out

var boss_active: bool:
	get:
		return boss_activated and boss != null and boss.alive
var boss_fraction: float:
	get:
		return boss.hp_fraction if boss else 0.0

# ---------------- 更新 ----------------
func update_level(dt: float, player, camera_pos: Vector3) -> void:
	time += dt
	_player_ref = player
	# ---- 环境互动：连锁引爆队列 / 落叶回收 / 雪地脚印 / 草让开 ----
	for i in range(_pending_booms.size() - 1, -1, -1):
		var pb: Dictionary = _pending_booms[i]
		pb["t"] = float(pb["t"]) - dt
		if float(pb["t"]) <= 0.0:
			_pending_booms.remove_at(i)
			_detonate_barrel(pb["bt"])
	for i in range(_leaf_fx.size() - 1, -1, -1):
		_leaf_fx[i]["t"] = float(_leaf_fx[i]["t"]) + dt
		if float(_leaf_fx[i]["t"]) > 1.2:
			(_leaf_fx[i]["p"] as Node).queue_free()
			_leaf_fx.remove_at(i)
	if String(data["theme"]) == "snow":
		_track_footprints(player, dt)
		for e in enemies:
			if e.alive and ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar"].has(String(e.type)):
				_track_footprints(e, dt)
		for fp in _footprints:
			fp["t"] = float(fp["t"]) + dt
			var left := 12.0 - float(fp["t"])
			if left <= 0.0:
				(fp["mesh"] as MeshInstance3D).visible = false
			elif left < 3.0:
				(fp["mat"] as StandardMaterial3D).albedo_color.a = 0.5 * left / 3.0
	_grass_timer -= dt
	if _grass_timer <= 0.0:
		_grass_timer = 0.12
		_update_grass_bend(player.global_position)
	var dist := player_dist(player)
	# 环境动画
	for s in _sway:
		(s["pivot"] as Node3D).rotation.z = sin(time * 1.4 + float(s["phase"])) * 0.045
		(s["pivot"] as Node3D).rotation.x = cos(time * 1.1 + float(s["phase"])) * 0.03
	for sm in _scroll_mats:
		var m: StandardMaterial3D = sm["mat"]
		m.uv1_offset.y -= dt * float(sm["speed"])
	for p in _pulse:
		var sc: Vector3 = p["base"]
		var k := 1.0 + sin(time * 2.2 + float(p["phase"])) * 0.05
		(p["mesh"] as MeshInstance3D).scale = sc * k
	for b in _blink_mats:
		(b["mat"] as StandardMaterial3D).emission_energy_multiplier = 1.5 + sin(time * 4.0 + float(b["phase"])) * 0.7
	if _snow:
		_snow.global_position = Vector3(player.global_position.x, 13.0, player.global_position.z - 25.0)
	if _sun:
		_sun.global_position = player.global_position + Vector3(14, 30, 10)
	# 检查点（敌人与飞鹰已在建关时全量预置，这里不再有触发刷怪）
	while _cp_index < _checkpoints.size() - 1:
		var cp: Dictionary = _checkpoints[_cp_index + 1]
		if dist >= float(cp["dist"]):
			_cp_index += 1
			var cy := get_support_y(float(cp["x"]), float(cp["z"]), 999.0)
			_ctx["on_checkpoint"].call(Vector3(float(cp["x"]), cy, float(cp["z"])))
		else:
			break
	# 敌人
	for i in range(enemies.size() - 1, -1, -1):
		var gone: bool = enemies[i].update_enemy(dt * _enemy_dt_scale, player, camera_pos)
		# 图鉴遭遇：敌人首次进入警觉即登记（击杀遭遇走 on_kill）
		if not gone and enemies[i]._alert and not enemies[i].has_meta("feat_seen"):
			enemies[i].set_meta("feat_seen", true)
			if _ctx.has("on_encounter"):
				_ctx["on_encounter"].call(String(enemies[i].type))
		if gone:
			enemies[i].destroy_enemy()
			enemies.remove_at(i)
	# Boss 触发：开放版按三维距离——玩家进入竞技场 38 米内（或越过旧推进线）落闸封场，
	# U 形能量墙（后墙+两侧墙）围住竞技场垫，发生器立柱撑起墙面，不是凭空红板
	# 触发须等玩家本人越过落闸线（z < boss_z+26）：触发球半径 38 > 落闸偏移 27，
	# 不加这道门，玩家沿中线会在闸外 11m 触发 Boss、被落闸封在场外（子弹/本人都进不去=软锁，探针实测）
	if not boss_activated and player.global_position.z < boss_z + 26.0 and (dist >= length - 8.0 or player.global_position.distance_to(Vector3(0, boss_y, boss_z)) < 38.0):
		boss_activated = true
		var barrier_z := boss_z + 27.0
		var bm := Util.flat(Color(1, 0.2, 0.27, 0.16))
		bm.emission_enabled = true
		bm.emission = Color(1, 0.15, 0.2)
		bm.emission_energy_multiplier = 0.7
		var wall := MeshInstance3D.new()
		var wp := PlaneMesh.new()
		wp.size = Vector2(width + 24.0, 6.0) # 落闸全宽到围界，侧翼不再留绕行口（调平表 §3.8 附带发现）
		wp.orientation = PlaneMesh.FACE_Z
		wall.mesh = wp
		wall.material_override = bm
		wall.position = Vector3(0, boss_y + 3.0, barrier_z)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wall)
		_barrier_wall = wall
		for sx in [-(width / 2.0 - 13.0), width / 2.0 - 13.0]:
			var side := MeshInstance3D.new()
			var sp := PlaneMesh.new()
			sp.size = Vector2(29.0, 6.0)
			sp.orientation = PlaneMesh.FACE_Z
			side.mesh = sp
			side.material_override = bm
			side.rotation.y = PI / 2.0
			side.position = Vector3(sx, boss_y + 3.0, barrier_z - 14.5)
			side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(side)
			_add_collider({"type": "box", "x": sx, "z": barrier_z - 14.5, "w": 0.7, "d": 29.0, "h": 8.0, "y0": boss_y})
		for px in [-(width / 2.0 - 13.4), width / 2.0 - 13.4]:
			Util.cyl(self, 0.32, 0.42, 6.4, Util.pbr(Color(0.2, 0.21, 0.24), "metal", 0.5, 0.6), Vector3(px, boss_y + 3.2, barrier_z), 10)
			Util.sph(self, 0.3, Util.glow(Color(1, 0.2, 0.15), 2.2), Vector3(px, boss_y + 6.6, barrier_z), 10, 8)
		_barrier_col = _add_collider({"type": "box", "x": 0.0, "z": barrier_z, "w": width + 24.0, "d": 0.7, "h": 8.0, "y0": boss_y})
		boss.activate()
		_ctx["on_boss_activated"].call(boss)
		_ctx["on_checkpoint"].call(Vector3(0, get_support_y(0.0, barrier_z - 4.0, 999.0), barrier_z - 4.0))
		pickups.spawn_heal(3.0, barrier_z - 6.0, get_support_y(3.0, barrier_z - 6.0, 999.0))
	if boss:
		boss.update_boss(dt, player)
	# 竞技场屏障：呼吸脉动；Boss 击败后撤场并解除封路
	if _barrier_wall:
		if boss and not boss.alive:
			_barrier_wall.queue_free()
			_barrier_wall = null
			_barrier_col["disabled"] = true
			_boss_blocker["disabled"] = true
		else:
			(_barrier_wall.material_override as StandardMaterial3D).albedo_color.a = 0.13 + sin(time * 5.0) * 0.045
	# 电网脉动
	for g in gates:
		if g["sensor"].alive:
			(g["field"] as MeshInstance3D).material_override.albedo_color.a = 0.3 + sin(time * 7.0) * 0.12
	# 1.2.0 封锁点：玩家进区且区内有活敌→出口升墙+全员警戒接敌；肃清→落墙（永不重锁）
	for lk in locks:
		if bool(lk["cleared"]):
			continue
		var lf := lk["field"] as MeshInstance3D
		if bool(lk["active"]):
			lf.material_override.albedo_color.a = 0.3 + sin(time * 7.0) * 0.12
			var any_alive := false
			for e in lk["members"]:
				if is_instance_valid(e) and e.alive:
					any_alive = true
					break
			if not any_alive:
				lk["cleared"] = true
				lk["active"] = false
				lk["collider"]["disabled"] = true
				lf.visible = false
				if _ctx.has("on_lock_msg"):
					_ctx["on_lock_msg"].call("封锁解除")
		elif dist >= float(lk["entry"]) and dist < float(lk["exit"]) + 30.0:
			var any_alive2 := false
			for e in lk["members"]:
				if is_instance_valid(e) and e.alive:
					any_alive2 = true
					break
			if any_alive2:
				lk["active"] = true
				lk["collider"]["disabled"] = false
				lf.visible = true
				for e in lk["members"]:
					if is_instance_valid(e) and e.alive:
						e._alert = true
						e._last_seen = player.global_position
						e._seen_age = 0.0
				if _ctx.has("on_lock_msg"):
					_ctx["on_lock_msg"].call("肃清本区敌人解除封锁")
			else:
				lk["cleared"] = true # 进区前已被远处打光：静默通过，不升墙
	# 火焰喷口
	for f in flames:
		var t := fmod(time + float(f["phase"]), float(f["period"]))
		var erupting := t > 1.3 and t < 2.5
		var was_erupting := bool(f["erupting"])
		f["erupting"] = erupting
		var wm: StandardMaterial3D = (f["warn"] as MeshInstance3D).material_override
		wm.albedo_color.a = 0.85 if (t > 0.8 and t <= 1.3) else 0.0
		(f["flame"] as MeshInstance3D).visible = erupting
		if erupting and not was_erupting:
			(f["sfx"] as AudioStreamPlayer3D).play() # 喷发上升沿呼啸一次（时长对齐 1.2s 喷发窗）
		if erupting and player.alive:
			var dx: float = player.global_position.x - float(f["x"])
			var dz: float = player.global_position.z - float(f["z"])
			var gy := get_support_y(float(f["x"]), float(f["z"]), 999.0)
			if dx * dx + dz * dz < 1.7 and player.global_position.y < gy + 3.4:
				player.take_damage(1)
	# 矿车
	for c in carts:
		var cx := sin(time * float(c["speed"]) + float(c["phase"])) * (width / 2.0 - 3.4)
		(c["group"] as Node3D).position.x = cx
		c["collider"]["x"] = cx
		if float(c["hit_cd"]) > 0.0:
			c["hit_cd"] = float(c["hit_cd"]) - dt
		if player.alive and float(c["hit_cd"]) <= 0.0:
			var dx: float = player.global_position.x - cx
			var dz: float = player.global_position.z - float(c["z"])
			if absf(dx) < 2.2 and absf(dz) < 1.9 and player.global_position.y < float(c["collider"].get("y0", 0.0)) + 1.9:
				c["hit_cd"] = 1.0
				if player.take_damage(1):
					(c["sfx"] as AudioStreamPlayer3D).play() # 矿车撞中玩家的金属撞击
					player.global_position.z += 2.6
	# 瀑布落石
	if String(data["theme"]) == "waterfall" and player.alive:
		_rock_timer -= dt
		if _rock_timer <= 0.0 and dist > 20.0 and dist < length - 45.0:
			_rock_timer = randf_range(2.2, 3.6)
			var rz: float = player.global_position.z - 26.0
			# 落石偏置西股水帘线（调平表 §3.3）：55% 落在水帘带，把「西线最险」做实
			var rx := randf_range(-width / 2.0 + 3.0, width / 2.0 - 3.0)
			if randf() < 0.55:
				rx = randf_range(-width / 2.0 + 3.0, -12.0)
			var rm := Util.sph(self, 0.55, Util.pbr(Color(0.85, 0.8, 0.7), "rock", 0.95), Vector3(rx, 0, rz), 7, 5)
			rocks.append({"mesh": rm, "speed": 8.5, "t": 0.0})
	for i in range(rocks.size() - 1, -1, -1):
		var r: Dictionary = rocks[i]
		r["t"] = float(r["t"]) + dt
		var rm: MeshInstance3D = r["mesh"]
		rm.position.z += float(r["speed"]) * dt
		rm.position.y = get_support_y(rm.position.x, rm.position.z, rm.position.y + 2.0) + 0.5
		rm.rotation.x -= dt * 6.0
		var dx: float = player.global_position.x - rm.position.x
		var dz: float = player.global_position.z - rm.position.z
		var kill := false
		if player.alive and dx * dx + dz * dz < 1.15 and absf(player.global_position.y - rm.position.y) < 1.6:
			player.take_damage(1)
			kill = true
		if kill or float(r["t"]) > 7.0 or rm.position.z > player.global_position.z + 14.0:
			rm.queue_free()
			rocks.remove_at(i)
	# 断桥
	if _bridge_mesh and not _bridge_collapsed and player.global_position.z < _bridge_z - 8.0:
		_bridge_collapsed = true
		_ctx["projectiles"].spawn_explosion_fx(Vector3(0, 0.6, _bridge_z), 2.4, Color(0.42, 0.69, 1))
	if _bridge_mesh and _bridge_collapsed and _bridge_mesh.position.y > -1.4:
		_bridge_mesh.position.y -= dt * 1.8
		_bridge_mesh.rotation.x += dt * 0.25
	# 压顶机
	for c in crushers:
		var t := fmod(time + float(c["phase"]), float(c["period"]))
		var y := 5.6
		if t < 1.7:
			y = 5.6
			c["state"] = "up"
		elif t < 2.1:
			y = 5.6 + sin(time * 40.0) * 0.05
			c["state"] = "warn"
		elif t < 2.32:
			y = 5.6 - (t - 2.1) / 0.22 * 4.45
			if c["state"] != "slam" and t > 2.26:
				c["state"] = "slam"
				(c["sfx"] as AudioStreamPlayer3D).play() # 压顶机落底砸响（每周期一次，3D 衰减）
				if player.alive:
					var dx: float = player.global_position.x
					var dz: float = player.global_position.z - float(c["z"])
					if absf(dx) < 2.9 and absf(dz) < 1.9 and player.global_position.y < float(c["y"]) + 1.3:
						player.take_damage(1)
				_ctx["projectiles"].spawn_explosion_fx(Vector3(0, float(c["y"]) + 0.3, float(c["z"])), 1.6, Color(0.8, 0.6, 0.4))
		elif t < 3.0:
			y = 1.15
			c["state"] = "hold"
		else:
			y = 1.15 + (t - 3.0) / (float(c["period"]) - 3.0) * 4.45
			c["state"] = "rise"
		(c["press"] as Node3D).position.y = y
	# 妖卵孵化
	for e in eggs:
		if not e["hatched"]:
			var dx: float = player.global_position.x - float(e["x"])
			var dz: float = player.global_position.z - float(e["z"])
			if dx * dx + dz * dz < 49.0:
				e["hatched"] = true
				(e["mesh"] as MeshInstance3D).visible = false
				_spawn_enemy("spore", float(e["x"]), float(e["z"]))
				AudioSys.play("pickup", -8.0, 0.7)
	pickups.update_pickups(dt, player, self)

func destroy_level() -> void:
	queue_free()
