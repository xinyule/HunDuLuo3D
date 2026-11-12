class_name Level
extends Node3D

## 关卡 —— 线性走廊推进 + 分段触发刷怪（原作 8 关复原）
## 主题动态（日版独有）：丛林树冠摇动 / 瀑布流水 / 异形肉壁蠕动 / 基地灯带明暗 / 雪原吹雪

class GateSensor:
	extends RefCounted
	var alive := true
	var targetable := true
	var hp := 130
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

var data: Dictionary
var level_index := 0
var width := 20.0
var length := 200.0
var colliders: Array = []
var enemies: Array = []
var sensors: Array = []
var gates: Array = []
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
var _spawn_queue: Array = []
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
	width = float(data["width"])
	length = float(data["length"])
	pickups = PickupSystem.new()
	add_child(pickups)
	pickups.setup({"on_pickup": ctx["on_pickup"], "on_score": ctx["on_score"]})
	_enemy_ctx = {"projectiles": ctx["projectiles"], "on_score": ctx["on_score"]}
	for s in data["spawns"]:
		_spawn_queue.append({"dist": float(s[0]), "type": s[1], "x": float(s[2]), "done": false})
	if data.has("mid_tank"):
		_spawn_queue.append({"dist": float(data["mid_tank"]), "type": "tank", "x": 0.0, "done": false})
	_spawn_queue.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var letters: Array = data.get("letters", ["S"])
	var fi := 0
	for d in data.get("falcons", []):
		_falcon_queue.append({"dist": float(d), "letter": letters[fi % letters.size()], "done": false})
		fi += 1
	_checkpoints.append({"x": 0.0, "y": 0.0, "z": 26.0, "dist": -1.0})
	for gd in data.get("gates", []):
		_checkpoints.append({"x": 0.0, "y": 0.0, "z": 26.0 - float(gd) - 4.0, "dist": float(gd) + 4.0})
	_checkpoints.append({"x": 0.0, "y": 0.0, "z": 26.0 - (length - 44.0), "dist": length - 44.0})
	_build()

func player_dist(player) -> float:
	return 26.0 - player.global_position.z

func get_support_y(x: float, z: float, from_y: float) -> float:
	var best := 0.0
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

func _build() -> void:
	var env_data: Dictionary = data["env"]
	_setup_environment(env_data)
	_sun = DirectionalLight3D.new()
	_sun.light_energy = 1.05
	_sun.light_color = Color(1, 0.97, 0.9)
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 120.0
	_sun.rotation_degrees = Vector3(-52, -28, 0)
	add_child(_sun)
	_build_ground_and_walls()
	match String(data["theme"]):
		"jungle": _theme_jungle()
		"base", "base2": _theme_base()
		"waterfall": _theme_waterfall()
		"snow": _theme_snow()
		"energy": _theme_energy()
		"hangar": _theme_hangar()
		"alien": _theme_alien()
	for gd in data.get("gates", []):
		_build_gate(float(gd))
	for i in data.get("flames", []).size():
		_build_flame(float(data["flames"][i]), i)
	for i in data.get("carts", []).size():
		_build_cart(float(data["carts"][i]), i)
	for i in data.get("crushers", []).size():
		_build_crusher(float(data["crushers"][i]), i)
	boss_z = -length + 10.0
	boss_y = get_support_y(0.0, boss_z, 999.0)
	boss = Boss.new()
	add_child(boss)
	boss.setup(String(data["boss"]), Vector3(0, boss_y, boss_z), {
		"projectiles": _ctx["projectiles"],
		"on_score": _ctx["on_score"],
		"on_defeated": _ctx["on_boss_defeated"],
		"on_core_exposed": _ctx.get("on_core_exposed", Callable()),
		"spawn_minion": func(t, x, z): _spawn_enemy(t, x, z),
	})
	# Boss 本体封路：打死前不能绕过去（击败后在更新循环里解除）
	_boss_blocker = _add_collider({"type": "box", "x": 0.0, "z": boss_z, "w": width, "d": 2.2, "h": 9.0, "y0": boss_y})

func _setup_environment(env_data: Dictionary) -> void:
	var we: WorldEnvironment = _ctx["world_env"]
	var env := we.environment
	var sky_name := String(env_data["sky"])
	var hdri_name := "warehouse"
	if sky_name == "forest":
		hdri_name = "forest"
	elif sky_name == "snow":
		hdri_name = "snow"
	var sky_res := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/%s.hdr" % hdri_name)
	sky_res.sky_material = pm
	env.sky = sky_res
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	if sky_name == "none":
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.html("#%06x" % int(env_data["bg"]))
	else:
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color.html("#%06x" % int(env_data["fog"]))
	env.fog_density = float(env_data["fog_density"])
	env.fog_sun_scatter = 0.25

func _build_ground_and_walls() -> void:
	var env_data: Dictionary = data["env"]
	var center_z := 26.0 - length / 2.0
	var ground_tints := {"jungle": Color(0.55, 0.62, 0.42), "rock": Color(0.8, 0.78, 0.72), "snow": Color(1, 1, 1), "concrete": Color(0.72, 0.75, 0.8), "rust": Color(0.82, 0.7, 0.58), "alien": Color(0.85, 0.6, 0.7)}
	var gtint: Color = ground_tints.get(String(env_data["ground"]), Color(0.85, 0.85, 0.85))
	var ground_mat := Util.pbr(gtint, String(env_data["ground"]), 0.95, 0.0, Vector2((width + 46.0) / 6.0, (length + 90.0) / 6.0))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width + 46.0, length + 90.0)
	ground.mesh = plane
	ground.material_override = ground_mat
	ground.position = Vector3(0, -0.02, center_z)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	_add_collider({"type": "box", "x": -(width / 2.0 + 0.6), "z": center_z, "w": 1.2, "d": length + 60.0, "h": 30.0, "y0": 0.0})
	_add_collider({"type": "box", "x": width / 2.0 + 0.6, "z": center_z, "w": 1.2, "d": length + 60.0, "h": 30.0, "y0": 0.0})
	_add_collider({"type": "box", "x": 0.0, "z": 34.0, "w": width + 10.0, "d": 1.2, "h": 30.0, "y0": 0.0})
	_add_collider({"type": "box", "x": 0.0, "z": -length - 2.0, "w": width + 10.0, "d": 1.2, "h": 30.0, "y0": 0.0})

func _scatter(rand: RandomNumberGenerator, count: int, maker: Callable) -> void:
	for i in count:
		var dist := 24.0 + rand.randf() * (length - 55.0)
		var x := (1.0 if rand.randf() > 0.5 else -1.0) * (3.5 + rand.randf() * (width / 2.0 - 4.5))
		maker.call(x, 26.0 - dist, rand)

var _leaf_mat: Material = null
var _leaf_mat_snow: Material = null
var _leaf_card_mesh: PlaneMesh = null

static var _fern_scene: PackedScene = null
static var _rock_scene: PackedScene = null
static var _quiver_scene: PackedScene = null

func _leaf_material(snow: bool) -> Material:
	if snow and _leaf_mat_snow:
		return _leaf_mat_snow
	if not snow and _leaf_mat:
		return _leaf_mat
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/tex/foliage_cluster_snow.png" if snow else "res://assets/tex/foliage_cluster.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	if snow:
		_leaf_mat_snow = m
	else:
		_leaf_mat = m
	return m

func _tree(x: float, z: float, rand: RandomNumberGenerator, snow: bool) -> void:
	Util.cyl(self, 0.22, 0.36, 3.4, Util.pbr(Color(1, 1, 1), "bark", 0.95, 0.0, Vector2(1, 2)), Vector3(x, 1.7, z), 8)
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 3.3, z)
	add_child(pivot)
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
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.5, "h": 3.0, "y0": 0.0})

func _fern(x: float, z: float, rand: RandomNumberGenerator) -> void:
	if _fern_scene == null:
		_fern_scene = load("res://assets/veg/fern_02.glb")
	var f := _fern_scene.instantiate() as Node3D
	f.position = Vector3(x, get_support_y(x, z, 999.0), z)
	f.rotation.y = rand.randf() * TAU
	f.scale = Vector3.ONE * rand.randf_range(1.1, 1.9)
	add_child(f)

var _grass_mat_c: Material = null

func _grass_mat() -> Material:
	if _grass_mat_c == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/tex/foliage_cluster.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.35
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		_grass_mat_c = m
	return _grass_mat_c

## 草丛：叶团贴图十字卡，挂进 _sway 随风摆
func _grass(x: float, z: float, rand: RandomNumberGenerator) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, get_support_y(x, z, 999.0), z)
	add_child(pivot)
	var h := rand.randf_range(0.55, 0.95)
	for a in [0.0, PI / 2.0]:
		var card := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.85, h)
		card.mesh = pm
		card.material_override = _grass_mat()
		card.position.y = h / 2.0
		card.rotation.y = a + rand.randf_range(-0.3, 0.3)
		pivot.add_child(card)
	_sway.append({"pivot": pivot, "phase": rand.randf() * TAU})

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

func _rock_glb(x: float, z: float, rand: RandomNumberGenerator) -> void:
	if _rock_scene == null:
		_rock_scene = load("res://assets/veg/rock_face_01.glb")
	var r := _rock_scene.instantiate() as Node3D
	var sc := rand.randf_range(0.8, 1.7)
	r.position = Vector3(x, get_support_y(x, z, 999.0) - 0.25, z)
	r.rotation.y = rand.randf() * TAU
	r.scale = Vector3.ONE * sc
	add_child(r)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 1.0 * sc, "h": 1.2 * sc, "y0": 0.0})

func _quiver(x: float, z: float, rand: RandomNumberGenerator) -> void:
	if _quiver_scene == null:
		_quiver_scene = load("res://assets/veg/quiver_tree_02.glb")
	var t := _quiver_scene.instantiate() as Node3D
	t.position = Vector3(x, 0.0, z)
	t.rotation.y = rand.randf() * TAU
	t.scale = Vector3.ONE * rand.randf_range(0.8, 1.15)
	add_child(t)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.6, "h": 3.0, "y0": 0.0})

func _rock(x: float, z: float, rand: RandomNumberGenerator, scale_r: float = 0.9) -> void:
	var rock := Util.sph(self, scale_r, Util.pbr(Color(0.85, 0.82, 0.75), "rock", 0.95, 0.0, Vector2(1.5, 1.5)), Vector3(x, scale_r * 0.45, z), 8, 6)
	rock.scale = Vector3(1.2, 0.75, 1.0)
	rock.rotation.y = rand.randf() * TAU
	_add_collider({"type": "circle", "x": x, "z": z, "r": scale_r * 0.8, "h": scale_r, "y0": 0.0})

func _theme_jungle() -> void:
	var rand := Util.seeded(1101 + level_index * 77)
	var d := 6.0
	while d < length + 20.0:
		for s in [-1.0, 1.0]:
			if rand.randf() > 0.25:
				_tree(s * (width / 2.0 + 2.4 + rand.randf() * 3.0), 26.0 - d, rand, false)
		d += 7.0
	_scatter(rand, 12, func(x, z, r): _add_box(x, z, 1.1, 1.1, 1.1, Util.pbr(Color(1, 1, 1), "planks", 0.9, 0.0, Vector2.ONE)))
	_scatter(rand, 8, func(x, z, r): _rock(x, z, r))
	_scatter(rand, 14, func(x, z, r): _fern(x, z, r))
	_scatter(rand, 5, func(x, z, r): _rock_glb(x, z, r))
	_scatter(rand, 16, func(x, z, r): _grass(x, z, r))
	_add_motes(42, Color(1, 0.95, 0.8, 0.8))
	# 河 + 爆裂木桥（原作第1关标志）
	var river_z := 26.0 - 70.0
	_bridge_z = river_z
	var water := MeshInstance3D.new()
	var wp := PlaneMesh.new()
	wp.size = Vector2(width + 30.0, 11.0)
	water.mesh = wp
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.32, 0.48, 0.88)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.12
	wm.metallic = 0.15
	wm.normal_texture = Util.tex_nor("jungle")
	wm.texture_repeat = 1 # TEXTURE_REPEAT_ENABLED
	wm.uv1_scale = Vector3(6, 2, 1)
	water.material_override = wm
	water.position = Vector3(0, 0.03, river_z)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	_scroll_mats.append({"mat": wm, "speed": 0.35})
	_bridge_mesh = _add_box(0, river_z, 5.5, 12.5, 0.35, Util.pbr(Color(1, 1, 1), "planks", 0.9, 0.0, Vector2(2, 4)))

func _theme_base() -> void:
	var rand := Util.seeded(2202 + level_index * 77)
	var wall_mat := Util.pbr(Color(0.85, 0.88, 0.95), "metal", 0.5, 0.65, Vector2(6, 1.5))
	var d := 0.0
	while d < length + 30.0:
		for s in [-1.0, 1.0]:
			_add_box(s * (width / 2.0 + 1.4), 26.0 - d - 7.5, 1.6, 15.0, 6.5, wall_mat, 0.0, false)
		d += 15.0
	d = 14.0
	while d < length:
		_add_box(0, 26.0 - d, width + 2.0, 0.8, 0.5, Util.pbr(Color(0.13, 0.15, 0.18), "", 0.6, 0.5), 6.2, false)
		var strip_m := Util.glow(Color(0.55, 0.8, 1.0), 1.8)
		var strip := Util.box(self, Vector3(width - 2.0, 0.08, 0.3), strip_m, Vector3(0, 6.1, 26.0 - d))
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blink_mats.append({"mat": strip_m, "phase": d})
		d += 22.0
	_scatter(rand, 10, func(x, z, r): _add_box(x, z, 1.2, 1.2, 1.2, Util.pbr(Color(0.6, 0.65, 0.55), "metal", 0.6, 0.5)))
	_scatter(rand, 6, Callable(self, "_make_barrel"))

func _make_barrel(x: float, z: float, _r: RandomNumberGenerator) -> void:
	Util.cyl(self, 0.42, 0.42, 1.15, Util.pbr(Color(0.9, 0.5, 0.35), "rust", 0.6, 0.5), Vector3(x, 0.58, z), 12)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.5, "h": 1.15, "y0": 0.0})

func _theme_waterfall() -> void:
	var rand := Util.seeded(3303)
	var d := 0.0
	while d < length + 24.0:
		for s in [-1.0, 1.0]:
			_rock(s * (width / 2.0 + 2.8), 26.0 - d, rand, 2.6)
		d += 12.0
	var step_depth := 11.0
	var step_rise := 1.05
	var steps := int((length - 45.0) / step_depth)
	var step_mat := Util.pbr(Color(0.95, 0.92, 0.85), "rock", 0.95, 0.0, Vector2(4, 2))
	for i in steps:
		var top_h := float(i + 1) * step_rise
		var z_c := 26.0 - 28.0 - float(i) * step_depth - step_depth / 2.0
		_add_box(0, z_c, width, step_depth + 0.3, top_h, step_mat)
	terrace_top_y = float(steps) * step_rise
	var plat_start_z := 26.0 - 28.0 - float(steps) * step_depth
	var plat_depth := absf(-length - 2.0 - plat_start_z)
	_add_box(0, plat_start_z - plat_depth / 2.0, width, plat_depth, terrace_top_y, step_mat)
	# 瀑布水帘（贴图滚动）+ 顶端水潭
	var fall := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(9, 17)
	fp.orientation = PlaneMesh.FACE_Z
	fall.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.7, 1.0, 0.5)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.normal_texture = Util.tex_nor("jungle")
	fm.texture_repeat = 1 # TEXTURE_REPEAT_ENABLED
	fm.uv1_scale = Vector3(2, 3, 1)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fall.material_override = fm
	fall.position = Vector3(-width / 4.0, 8.5, -length + 4.0)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fall)
	_scroll_mats.append({"mat": fm, "speed": 1.4})
	var pool := MeshInstance3D.new()
	var pp := PlaneMesh.new()
	pp.size = Vector2(width + 20.0, 12.0)
	pool.mesh = pp
	pool.material_override = fm
	pool.position = Vector3(0, terrace_top_y + 0.03, -length + 12.0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	_scatter(rand, 8, func(x, z, r): _add_box(x, z, 1.1, 1.1, 1.0, Util.pbr(Color(1, 1, 1), "planks", 0.9)))
	_scatter(rand, 10, func(x, z, r): _grass(x, z, r))
	_add_motes(30, Color(0.85, 0.95, 1, 0.7))

func _theme_snow() -> void:
	var rand := Util.seeded(4404)
	var d := 4.0
	while d < length + 20.0:
		for s in [-1.0, 1.0]:
			if rand.randf() > 0.3:
				_tree(s * (width / 2.0 + 2.5 + rand.randf() * 3.0), 26.0 - d, rand, true)
		d += 8.0
	_scatter(rand, 12, Callable(self, "_make_snowbank"))
	_snow_extras(rand)

func _make_snowbank(x: float, z: float, _r: RandomNumberGenerator) -> void:
	var bank := Util.sph(self, 1.5, Util.pbr(Color(1, 1, 1), "snow", 0.9, 0.0, Vector2(2, 2)), Vector3(x, -0.5, z), 10, 7)
	bank.scale = Vector3(1.3, 0.75, 1.0)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 1.5, "h": 1.1, "y0": 0.0})

func _snow_extras(rand: RandomNumberGenerator) -> void:
	_scatter(rand, 6, func(x, z, r): _add_box(x, z, 1.15, 1.15, 1.15, Util.pbr(Color(1, 1, 1), "planks", 0.9)))
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
	_scatter(rand, 8, func(x, z, r): _add_box(x, z, 1.2, 1.2, 1.3, Util.pbr(Color(0.8, 0.6, 0.4), "rust", 0.75, 0.4)))
	d = 20.0
	while d < length:
		_quiver((1.0 if int(d) % 52 < 26 else -1.0) * (width / 2.0 + 4.5), 26.0 - d, rand)
		d += 26.0
	_scatter(rand, 5, func(x, z, r): _rock_glb(x, z, r))

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
	_scatter(rand, 10, func(x, z, r): _add_box(x, z, 1.25, 1.25, 1.25, Util.pbr(Color(1, 1, 1), "planks", 0.9)))
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

func _make_egg(x: float, z: float, _r: RandomNumberGenerator) -> void:
	var egg := Util.sph(self, 0.8, Util.pbr(Color(0.85, 0.55, 0.65), "alien", 0.45, 0.0, Vector2(1.5, 1.5)), Vector3(x, 0.55, z), 10, 8)
	egg.scale = Vector3(1, 1.25, 1)
	_add_collider({"type": "circle", "x": x, "z": z, "r": 0.8, "h": 1.2, "y0": 0.0})
	eggs.append({"mesh": egg, "x": x, "z": z, "hatched": false})

# ---------------- 机关 ----------------
func _build_gate(dist: float) -> void:
	var z := 26.0 - dist
	var frame_m := Util.pbr(Color(0.22, 0.25, 0.28), "", 0.5, 0.6)
	_add_box(-(width / 2.0 - 1.0), z, 2, 1, 6, frame_m)
	_add_box(width / 2.0 - 1.0, z, 2, 1, 6, frame_m)
	_add_box(0, z, width, 1, 1, frame_m, 5.0)
	var field := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(width - 4.0, 5.0)
	fp.orientation = PlaneMesh.FACE_Z
	field.mesh = fp
	field.material_override = Util.flat(Color(0.2, 0.8, 1, 0.38))
	field.position = Vector3(0, 2.5, z)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	var collider := _add_collider({"type": "box", "x": 0.0, "z": z, "w": width - 3.4, "d": 0.9, "h": 5.2, "y0": 0.0})
	var sensor := GateSensor.new()
	sensor.pos = Vector3(0, 3.1, z)
	sensor.hit_x = 0.0
	sensor.hit_y = 3.1
	sensor.hit_z = z + 0.8
	sensor.projectiles = _ctx["projectiles"]
	var sg := Node3D.new()
	sg.position = Vector3(0, 3.1, z + 0.8)
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
	var gate := {"dist": dist, "z": z, "field": field, "collider": collider, "sensor": sensor, "open": false}
	sensor.on_open = func():
		collider["disabled"] = true
		field.visible = false
		sg.visible = false
		gate["open"] = true
		pickups.spawn_letter(2.5, 3.4, z - 3.5, "+")
	sensor.on_score = _ctx["on_score"]
	sensors.append(sensor)
	gates.append(gate)

func _build_flame(dist: float, i: int) -> void:
	var z := 26.0 - dist
	var x := (1.0 if i % 2 == 0 else -1.0) * width * 0.18
	Util.cyl(self, 0.55, 0.7, 0.5, Util.pbr(Color(0.5, 0.3, 0.12), "rust", 0.7, 0.5), Vector3(x, 0.25, z), 12)
	var flame := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.85
	cm.height = 4.4
	cm.radial_segments = 10
	flame.mesh = cm
	flame.material_override = Util.glow(Color(1, 0.42, 0.1), 2.2, 0.85)
	flame.position = Vector3(x, 2.4, z)
	flame.visible = false
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	var warn := Util.sph(self, 0.3, Util.glow(Color(1, 0.8, 0.2), 2.0, 0.0), Vector3(x, 0.8, z), 8, 6)
	warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.append({"x": x, "z": z, "flame": flame, "warn": warn, "period": 3.4, "phase": float(i) * 1.3, "erupting": false})

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
	g.position = Vector3(0, 0, z)
	add_child(g)
	var collider := _add_collider({"type": "box", "x": 0.0, "z": z, "w": 3.4, "d": 2.0, "h": 1.7, "y0": 0.0})
	carts.append({"group": g, "collider": collider, "z": z, "phase": float(i) * 2.1, "speed": 0.55 + float(i) * 0.12, "hit_cd": 0.0})

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
	g.position = Vector3(0, 0, z)
	add_child(g)
	crushers.append({"group": g, "press": press, "z": z, "period": 4.4, "phase": float(i) * 1.5, "state": "up"})

# ---------------- 生成/目标 ----------------
func _spawn_enemy(type: String, x: float, z: float) -> Enemy:
	var y := get_support_y(x, z, 999.0)
	if type == "sniper":
		var plat := _add_box(x, z, 1.9, 1.9, 2.2, Util.pbr(Color(0.8, 0.76, 0.66), "rock", 0.9, 0.0, Vector2.ONE), y)
		plat.position.y = y + 1.1
		y += 2.2
	var e := Enemy.new()
	add_child(e)
	e.setup(type, Vector3(x, y, z), _enemy_ctx, _ctx["soldier_scene"])
	enemies.append(e)
	return e

func spawn_minion(type: String, x: float, z: float) -> void:
	_spawn_enemy(type, x, z)

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
	# 刷怪/飞鹰/检查点
	for s in _spawn_queue:
		if not s["done"] and dist >= float(s["dist"]) - 30.0:
			s["done"] = true
			_spawn_enemy(String(s["type"]), float(s["x"]), 26.0 - float(s["dist"]))
	for f in _falcon_queue:
		if not f["done"] and dist >= float(f["dist"]):
			f["done"] = true
			pickups.spawn_falcon(player.global_position.z - 20.0, String(f["letter"]), width / 2.0)
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
		if enemies[i].update_enemy(dt, player, camera_pos):
			enemies[i].destroy_enemy()
			enemies.remove_at(i)
	# Boss 触发：玩家越过竞技场入口线（距终点 length-11）3 米后才落闸封场，
	# 屏障必须落在玩家身后——旧口径 length-42 会把屏障刷在玩家面前，Boss 被封在墙后打不到（v3.0.0 软锁根因）
	if not boss_activated and dist >= length - 8.0:
		boss_activated = true
		var barrier_z := boss_z + 27.0
		var wall := MeshInstance3D.new()
		var wp := PlaneMesh.new()
		wp.size = Vector2(width, 6.0)
		wp.orientation = PlaneMesh.FACE_Z
		wall.mesh = wp
		var bm := Util.flat(Color(1, 0.2, 0.27, 0.16))
		bm.emission_enabled = true
		bm.emission = Color(1, 0.15, 0.2)
		bm.emission_energy_multiplier = 0.7
		wall.material_override = bm
		wall.position = Vector3(0, boss_y + 3.0, barrier_z)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wall)
		_barrier_wall = wall
		# 两侧发生器立柱：让能量墙看着是设备撑起来的，不是凭空一块红板
		for px in [-width / 2.0 + 0.4, width / 2.0 - 0.4]:
			Util.cyl(self, 0.32, 0.42, 6.4, Util.pbr(Color(0.2, 0.21, 0.24), "metal", 0.5, 0.6), Vector3(px, boss_y + 3.2, barrier_z), 10)
			Util.sph(self, 0.3, Util.glow(Color(1, 0.2, 0.15), 2.2), Vector3(px, boss_y + 6.6, barrier_z), 10, 8)
		_barrier_col = _add_collider({"type": "box", "x": 0.0, "z": barrier_z, "w": width, "d": 0.7, "h": 8.0, "y0": boss_y})
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
	# 火焰喷口
	for f in flames:
		var t := fmod(time + float(f["phase"]), float(f["period"]))
		var erupting := t > 1.3 and t < 2.5
		f["erupting"] = erupting
		var wm: StandardMaterial3D = (f["warn"] as MeshInstance3D).material_override
		wm.albedo_color.a = 0.85 if (t > 0.8 and t <= 1.3) else 0.0
		(f["flame"] as MeshInstance3D).visible = erupting
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
			if absf(dx) < 2.2 and absf(dz) < 1.9 and player.global_position.y < 1.9:
				c["hit_cd"] = 1.0
				if player.take_damage(1):
					player.global_position.z += 2.6
	# 瀑布落石
	if String(data["theme"]) == "waterfall" and player.alive:
		_rock_timer -= dt
		if _rock_timer <= 0.0 and dist > 20.0 and dist < length - 45.0:
			_rock_timer = randf_range(2.2, 3.6)
			var rz: float = player.global_position.z - 26.0
			var rm := Util.sph(self, 0.55, Util.pbr(Color(0.85, 0.8, 0.7), "rock", 0.95), Vector3(randf_range(-width / 2.0 + 3.0, width / 2.0 - 3.0), 0, rz), 7, 5)
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
				if player.alive:
					var dx: float = player.global_position.x
					var dz: float = player.global_position.z - float(c["z"])
					if absf(dx) < 2.9 and absf(dz) < 1.9 and player.global_position.y < 1.3:
						player.take_damage(1)
				_ctx["projectiles"].spawn_explosion_fx(Vector3(0, 0.3, float(c["z"])), 1.6, Color(0.8, 0.6, 0.4))
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
