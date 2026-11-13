class_name ProjectileSystem
extends Node3D

## 弹丸池：玩家子弹（线段-球体命中）/ 敌方红弹（慢速可躲）/ 榴弹（抛物线+爆炸）/ 圆盘
## clear() 用代际守卫，避免命中回调链中途清表导致迭代越界（JS 版实锤过的 bug，Godot 版同样防范）

var _bullets: Array = []
var _orbs: Array = []
var _grenades: Array = []
var _fx: Array = []
var _pools: Array = [] # 地面残留：血泊/黏液/焦痕（独立于敌人回收，留存十几秒再淡出）

## 地面残留一滩（血泊/焦痕等）：扁圆盘贴地，存活期末尾 3 秒淡出
func spawn_pool(pos: Vector3, color: Color, radius: float = 0.55, life: float = 14.0) -> void:
	if _pools.size() > 42:
		var old: Dictionary = _pools.pop_front()
		if is_instance_valid(old["mesh"]):
			old["mesh"].queue_free()
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.07
	cm.height = 0.03
	cm.radial_segments = 12
	mesh.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.85)
	if _tex_fx.has("scorch"):
		m.albedo_texture = _tex_fx["scorch"] # Kenney CC0 焦痕图给池面不规则边缘与质感
	m.roughness = 0.3
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = pos
	_pools.append({"mesh": mesh, "t": 0.0, "life": life})
var _gen := 0
## 难度档的敌弹速度倍率（main 按难度设置；只作用于敌方光弹/圆盘，不碰玩家子弹）
var orb_speed_scale := 1.0
var _bullet_geo: Mesh
var _orb_geo: SphereMesh
var _disc_geo: CylinderMesh
var _fx_geo: SphereMesh
var _mat_cache: Dictionary = {}
var _disc_mat: Material
var _grenade_mat: Material
var _lights: Array[OmniLight3D] = []
# ---- 对象池：弹丸/特效网格节点复用（热身后射击不再产生节点增删）----
# 每条活弹条目带 "pool" 键指回自己的空闲池；死亡/清场时回池隐藏而非 queue_free。
# 地面残留 _pools 不池化：其圆盘几何随半径逐个不同，且已有上限 42+自然消退兜底。
var _free_bullets: Array = []
var _free_orbs: Array = [] # 光弹与榴弹共用球几何
var _free_discs: Array = []
var _free_fx: Array = []

# ---- 战斗反馈批：粒子/面片/弹壳/冲击波环（纯表现层，全部池化；素材 Kenney CC0）----
var _tex_fx: Dictionary = {}
var _tracer_mat: Material
var _tracer_wave_mat: Material
var _orb_mat: Material
var _trail_mat: Material
var _grenade_geo: SphereMesh
var _grenade_mat2: Material
var _flash_geo: QuadMesh
var _flash_mat: Material
var _free_flash: Array = []
var _flashes: Array = []
var _muzzle_light: OmniLight3D
var _shell_geo: BoxMesh
var _shell_mat: Material
var _free_shells: Array = []
var _shells: Array = []
var _ring_geo: TorusMesh
var _ring_base_mat: Material
var _free_rings: Array = []
var _rings: Array = []
var _expl_groups: Array = [] # 全套爆炸组 {fire, smoke, spark}
var _expl_idx := 0
var _mini_groups: Array = [] # 部件命中级小爆炸 {fire, spark}
var _mini_idx := 0
var _hit_emitters: Dictionary = {} # kind -> Array[GPUParticles3D]
var _hit_idx: Dictionary = {}
var _puff_pool: Array = []
var _puff_idx := 0
var _th: Callable # 最近一帧的地形高度回调（弹壳落地/炮弹拖尾用）
var shake_hook: Callable # main 设置：func(pos, radius)，按距离衰减给镜头震屏

func _take(pool: Array) -> MeshInstance3D:
	while not pool.is_empty():
		var m = pool.pop_back()
		if is_instance_valid(m):
			(m as MeshInstance3D).visible = true
			return m
	var nm := MeshInstance3D.new()
	add_child(nm)
	return nm

func _give(pool: Array, m) -> void:
	if m != null and is_instance_valid(m):
		(m as MeshInstance3D).visible = false
		pool.append(m)

func _init() -> void:
	# 玩家弹：拉长胶囊当曳光体（长轴 Y，spawn 时把 Y 轴对齐弹道）
	var cap := CapsuleMesh.new()
	cap.radius = 0.055
	cap.height = 1.25
	cap.radial_segments = 8
	cap.rings = 4
	_bullet_geo = cap
	# 敌弹：橙红光弹，半径 0.15→0.20 放大可读性
	_orb_geo = SphereMesh.new()
	_orb_geo.radius = 0.2
	_orb_geo.height = 0.4
	_orb_geo.radial_segments = 10
	_orb_geo.rings = 6
	_disc_geo = CylinderMesh.new()
	_disc_geo.top_radius = 0.42
	_disc_geo.bottom_radius = 0.42
	_disc_geo.height = 0.09
	_disc_geo.radial_segments = 14
	_fx_geo = SphereMesh.new()
	_fx_geo.radius = 1.0
	_fx_geo.height = 2.0
	_fx_geo.radial_segments = 12
	_fx_geo.rings = 6
	for i in 2:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 7.0
		l.light_color = Color(1, 0.6, 0.25)
		add_child(l)
		_lights.append(l)
	_build_fx_assets()

## 加色混合发光材质（曳光/拖尾：不受光、自发光、叠加发亮）
func _add_mat(color: Color, energy: float) -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _tex_mat(tex: Texture2D, tint: Color, add_blend: bool) -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if add_blend:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## 粒子发射器模板：一次性爆发、世界坐标、贴图 billboard；每台自有过程材质（可逐台改色）
func _make_emitter(tex: Texture2D, amount: int, lifetime: float, color: Color, vel: float, gravity: Vector3, spread: float, quad_size: float, add_blend: bool, damping: float = 0.0, shape_r: float = 0.3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -15, -40), Vector3(80, 50, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.gravity = gravity
	pm.initial_velocity_min = vel * 0.55
	pm.initial_velocity_max = vel
	if damping > 0.0:
		pm.damping_min = damping * 0.7
		pm.damping_max = damping
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = shape_r
	pm.scale_min = 0.8
	pm.scale_max = 1.25
	pm.color = color
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.65, Color(1, 1, 1, 0.85))
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pm.color_ramp = gtex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = _tex_mat(tex, Color.WHITE, add_blend)
	p.draw_pass_1 = quad
	# 粒子系统必须走 billboard 粒子模式才随视角转面
	(quad.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.emitting = false
	add_child(p)
	return p

func _build_fx_assets() -> void:
	for tn in ["muzzle", "flame", "smoke", "spark", "circle", "scorch", "dirt"]:
		var tp := "res://assets/fx/%s.png" % tn
		if ResourceLoader.exists(tp):
			_tex_fx[tn] = load(tp)
	_tracer_mat = _add_mat(Color(1.0, 0.86, 0.30), 3.4) # 玩家弹：亮黄曳光
	_tracer_wave_mat = _add_mat(Color(1.0, 0.70, 0.12), 3.4) # 火球枪：橙黄
	_orb_mat = Util.glow(Color(1, 0.32, 0.08), 3.0) # 敌弹：橙红
	_trail_mat = _add_mat(Color(1, 0.36, 0.1), 2.6)
	_flash_geo = QuadMesh.new()
	_flash_geo.size = Vector2.ONE
	_flash_mat = _tex_mat(_tex_fx.get("muzzle"), Color(1, 0.72, 0.35), true) # 深橙染色防 ADD 过曝成白团（fx_fire 实拍修正）
	_shell_geo = BoxMesh.new()
	_shell_geo.size = Vector3(0.022, 0.022, 0.06)
	_shell_mat = Util.pbr(Color(0.72, 0.52, 0.18), "", 0.35, 0.85)
	_ring_geo = TorusMesh.new()
	_ring_geo.inner_radius = 0.86
	_ring_geo.outer_radius = 1.0
	_ring_geo.rings = 40
	_ring_geo.ring_segments = 8
	_ring_base_mat = Util.glow(Color(1, 0.75, 0.4), 2.0, 0.5)
	(_ring_base_mat as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_grenade_geo = SphereMesh.new()
	_grenade_geo.radius = 0.21
	_grenade_geo.height = 0.42
	_grenade_geo.radial_segments = 12
	_grenade_geo.rings = 8
	_grenade_mat2 = Util.pbr(Color(0.16, 0.15, 0.13), "", 0.45, 0.6)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 5.5
	_muzzle_light.light_color = Color(1, 0.7, 0.35)
	add_child(_muzzle_light)
	# 爆炸全套组 ×5（火球+烟尘+火花）
	var flame: Texture2D = _tex_fx.get("flame")
	var smoke: Texture2D = _tex_fx.get("smoke")
	var spark: Texture2D = _tex_fx.get("spark")
	var circle: Texture2D = _tex_fx.get("circle")
	var dirt: Texture2D = _tex_fx.get("dirt")
	for i in 5:
		_expl_groups.append({
			"fire": _make_emitter(flame, 16, 0.5, Color(1, 0.62, 0.22), 3.2, Vector3(0, 1.5, 0), 180.0, 1.7, true, 2.5),
			"smoke": _make_emitter(smoke, 12, 1.25, Color(0.23, 0.21, 0.21, 0.55), 1.7, Vector3(0, 1.1, 0), 38.0, 1.9, false, 1.2),
			"spark": _make_emitter(spark, 18, 0.55, Color(1, 0.7, 0.25), 8.5, Vector3(0, -9, 0), 180.0, 0.3, true),
		})
	for i in 3: # 部件命中级小爆炸组
		_mini_groups.append({
			"fire": _make_emitter(flame, 7, 0.32, Color(1, 0.65, 0.25), 1.8, Vector3(0, 1, 0), 180.0, 0.8, true, 2.0, 0.15),
			"spark": _make_emitter(spark, 10, 0.4, Color(1, 0.7, 0.25), 6.0, Vector3(0, -8, 0), 180.0, 0.24, true, 0.0, 0.15),
		})
	_hit_emitters = {"blood": [], "goo": [], "spark": [], "rock": []}
	for i in 5:
		(_hit_emitters["blood"] as Array).append(_make_emitter(circle, 13, 0.45, Color(0.42, 0.03, 0.03), 3.0, Vector3(0, -12, 0), 65.0, 0.11, false, 0.0, 0.12))
		(_hit_emitters["spark"] as Array).append(_make_emitter(spark, 14, 0.4, Color(1, 0.62, 0.2), 6.5, Vector3(0, -6, 0), 180.0, 0.26, true, 0.0, 0.12))
	for i in 3:
		(_hit_emitters["goo"] as Array).append(_make_emitter(circle, 12, 0.5, Color(0.3, 0.6, 0.12), 2.8, Vector3(0, -11, 0), 65.0, 0.12, false, 0.0, 0.12))
		(_hit_emitters["rock"] as Array).append(_make_emitter(dirt, 11, 0.5, Color(0.55, 0.5, 0.44), 3.4, Vector3(0, -11, 0), 70.0, 0.16, false, 0.0, 0.12))
	for kind in _hit_emitters:
		_hit_idx[kind] = 0
	for i in 10: # 烟 puff（炮弹拖尾/炮口烟）
		_puff_pool.append(_make_emitter(smoke, 3, 0.55, Color(0.52, 0.5, 0.5, 0.42), 0.5, Vector3(0, 0.7, 0), 50.0, 0.55, false, 0.5, 0.08))

## 把胶囊长轴（局部 Y）对齐弹道的正交基
static func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var up := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)

func _basis_face(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.93 else Vector3.RIGHT
	return Basis.looking_at(d, up)

## 敌弹拖尾：交叉双面片挂在弹体子级（+Z 为弹道反方向），随弹体池复用、逐 spawn 开关
func _set_trail(mesh: MeshInstance3D, on: bool) -> void:
	var tr := mesh.get_node_or_null("Trail") as Node3D
	if tr == null:
		if not on:
			return
		tr = Node3D.new()
		tr.name = "Trail"
		mesh.add_child(tr)
		for rot in [Vector3(0, PI / 2, 0), Vector3(PI / 2, 0, 0)]:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.85, 0.15)
			qm.material = _trail_mat
			q.mesh = qm
			q.rotation = rot
			q.position = Vector3(0, 0, 0.52)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tr.add_child(q)
	tr.visible = on

## 枪口火光：星形贴图面片正对弹道绽放（随机滚转），玩家开火可选带一盏瞬时点光
func spawn_muzzle_flash(pos: Vector3, dir: Vector3, mul: float = 1.0, with_light: bool = false) -> void:
	var mesh := _take(_free_flash)
	mesh.mesh = _flash_geo
	mesh.material_override = _flash_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b := _basis_face(dir) * Basis(Vector3(0, 0, 1), randf() * TAU)
	mesh.global_transform = Transform3D(b, pos)
	var s := 0.55 * mul
	mesh.scale = Vector3.ONE * s
	_flashes.append({"mesh": mesh, "t": 0.0, "dur": 0.05, "s0": s, "pool": _free_flash})
	if with_light and _muzzle_light:
		_muzzle_light.global_position = pos + dir.normalized() * 0.25
		_muzzle_light.light_energy = 2.8

## 抛弹壳：黄铜小壳从抛壳口弹出，自旋+重力+落地弹跳一次
func spawn_shell(pos: Vector3, eject_dir: Vector3) -> void:
	if _shells.size() >= 56:
		var old: Dictionary = _shells.pop_front()
		_give(old["pool"], old["mesh"])
	var mesh := _take(_free_shells)
	mesh.mesh = _shell_geo
	mesh.material_override = _shell_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.scale = Vector3.ONE
	mesh.global_position = pos
	mesh.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	var vel := eject_dir.normalized() * randf_range(0.9, 1.5) + Vector3.UP * randf_range(1.4, 2.1)
	_shells.append({"mesh": mesh, "vel": vel, "ang": Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14)), "t": 0.0, "rest": false, "pool": _free_shells})

## 命中分型粒子（血/绿浆/火花/碎石）：enemy 按 _fx_kind 调用
func spawn_hit_fx(pos: Vector3, kind: String) -> void:
	var arr: Array = _hit_emitters.get(kind, _hit_emitters["spark"])
	if arr.is_empty():
		return
	var idx := int(_hit_idx.get(kind, 0))
	_hit_idx[kind] = idx + 1
	var p := arr[idx % arr.size()] as GPUParticles3D
	if kind == "spark":
		(p.process_material as ParticleProcessMaterial).color = Color(1, 0.62, 0.2)
	p.global_position = pos
	p.restart()

## 烟 puff：炮弹拖尾、炮口余烟
func spawn_smoke_puff(pos: Vector3, _mul: float = 1.0) -> void:
	if _puff_pool.is_empty():
		return
	var p := _puff_pool[_puff_idx % _puff_pool.size()] as GPUParticles3D
	_puff_idx += 1
	p.global_position = pos
	p.restart()

func _fire_ring(pos: Vector3, radius: float) -> void:
	var mesh := _take(_free_rings)
	if mesh.material_override == null:
		mesh.material_override = _ring_base_mat.duplicate()
	mesh.mesh = _ring_geo
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.rotation = Vector3.ZERO
	mesh.scale = Vector3.ONE * 0.3
	mesh.global_position = pos + Vector3(0, 0.18, 0)
	_rings.append({"mesh": mesh, "t": 0.0, "dur": 0.34, "radius": radius, "pool": _free_rings})

func _mat(color: Color) -> Material:
	if not _mat_cache.has(color):
		_mat_cache[color] = Util.glow(color, 2.4)
	return _mat_cache[color]

func spawn_player_bullet(from: Vector3, dir: Vector3, w: Dictionary) -> void:
	var mesh := _take(_free_bullets)
	mesh.mesh = _bullet_geo
	var wave := bool(w.get("wave", false))
	# 曳光口径（用户 22:00）：玩家弹统一亮黄拉长光体；火球枪橙黄加粗，靠弹形与武器区分而非杂色
	mesh.material_override = _tracer_wave_mat if wave else _tracer_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s0 := Vector3(1.7, 1.0, 1.7) if wave else Vector3.ONE
	mesh.basis = _basis_y_to(dir) # 先定向再缩放（basis 赋值会覆盖 scale，顺序不可反）
	mesh.scale = s0
	mesh.global_position = from
	_bullets.append({
		"mesh": mesh, "pos": from, "dir": dir,
		"speed": float(w["bullet_speed"]), "damage": int(w["damage"]),
		"pierce": bool(w["pierce"]), "wave": wave, "s0": s0,
		"life": 2.2, "gen": _gen, "pen": [], "pool": _free_bullets,
	})

## boom>0：重弹（坦克炮/Boss 弹）——命中时播全套爆炸视觉（纯表现，不加任何伤判）
func spawn_orb(from: Vector3, dir: Vector3, speed: float, damage: int = 1, boom: float = 0.0) -> void:
	var mesh := _take(_free_orbs)
	mesh.mesh = _orb_geo
	mesh.material_override = _orb_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.basis = _basis_face(dir)
	mesh.scale = Vector3.ONE
	_set_trail(mesh, true)
	mesh.global_position = from
	_orbs.append({"mesh": mesh, "pos": from, "dir": dir, "speed": speed * orb_speed_scale, "damage": damage, "life": 6.0, "gen": _gen, "r": 0.2, "boom": boom, "pool": _free_orbs})

func spawn_disc(from: Vector3, dir: Vector3, speed: float) -> void:
	var mesh := _take(_free_discs)
	mesh.mesh = _disc_geo
	if _disc_mat == null:
		_disc_mat = Util.glow(Color(1, 0.45, 0.15), 1.6)
	mesh.material_override = _disc_mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.scale = Vector3.ONE
	mesh.rotation = Vector3.ZERO
	_set_trail(mesh, false)
	mesh.global_position = from
	_orbs.append({"mesh": mesh, "pos": from, "dir": dir, "speed": speed * orb_speed_scale, "damage": 1, "life": 6.0, "gen": _gen, "r": 0.42, "disc": true, "pool": _free_discs})

func spawn_grenade(from: Vector3, vel: Vector3) -> void:
	var mesh := _take(_free_orbs)
	mesh.mesh = _grenade_geo # 炮弹本体加大（r 0.15→0.21），飞行中带烟拖尾（update 链）
	mesh.material_override = _grenade_mat2
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.scale = Vector3.ONE
	mesh.rotation = Vector3.ZERO
	_set_trail(mesh, false)
	mesh.global_position = from
	_grenades.append({"mesh": mesh, "pos": from, "vel": vel, "gen": _gen, "trail_t": 0.0, "pool": _free_orbs})

func spawn_explosion_fx(pos: Vector3, radius: float, color: Color = Color(1, 0.55, 0.2)) -> void:
	if radius < 1.2:
		# 部件命中级（Boss 部件/无敌火花等高频调用）：小火球+火花，不上全套
		if not _mini_groups.is_empty():
			var mg: Dictionary = _mini_groups[_mini_idx % _mini_groups.size()]
			_mini_idx += 1
			(mg["fire"].process_material as ParticleProcessMaterial).color = color
			(mg["spark"].process_material as ParticleProcessMaterial).color = color
			for key in mg:
				var mp := mg[key] as GPUParticles3D
				mp.global_position = pos
				mp.restart()
	else:
		# 全套爆炸：粒子火球+上升烟尘+四溅火花 + 冲击波环 + 核心闪光 + 点光
		if not _expl_groups.is_empty():
			var g: Dictionary = _expl_groups[_expl_idx % _expl_groups.size()]
			_expl_idx += 1
			(g["fire"].process_material as ParticleProcessMaterial).color = color
			(g["spark"].process_material as ParticleProcessMaterial).color = color.lightened(0.25)
			for key in g:
				var ep := g[key] as GPUParticles3D
				ep.global_position = pos
				ep.restart()
		_fire_ring(pos, radius)
		var mesh := _take(_free_fx)
		mesh.mesh = _fx_geo
		# 材质不能共享：_fx 更新链会逐个改 albedo alpha，故仍逐次新建材质（节点与几何已池化）
		mesh.material_override = Util.glow(color, 2.2, 0.55)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.scale = Vector3.ONE * 0.3
		mesh.rotation = Vector3.ZERO
		mesh.global_position = pos
		_fx.append({"mesh": mesh, "t": 0.0, "dur": 0.16, "radius": radius, "pool": _free_fx})
		for l in _lights:
			if l.light_energy <= 0.0:
				l.global_position = pos
				l.light_color = color
				l.light_energy = 2.0 + radius * 0.55
				break
	if shake_hook.is_valid():
		shake_hook.call(pos, radius)
	# 爆炸音按半径加强：越大越响、音高越低沉
	AudioSys.play("explosion", clampf(-8.5 + radius * 1.15, -8.5, -1.0), clampf(1.16 - radius * 0.06, 0.78, 1.12))

func clear_all() -> void:
	_gen += 1
	for arr in [_bullets, _orbs, _grenades]:
		for p in arr:
			_give(p["pool"], p["mesh"])
		arr.clear()
	for arr2 in [_shells, _flashes, _rings]:
		for e in arr2:
			_give(e["pool"], e["mesh"])
		arr2.clear()
	if _muzzle_light:
		_muzzle_light.light_energy = 0.0

func _seg_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0001:
		t = clampf((c - a).dot(ab) / len2, 0.0, 1.0)
	var p := a + ab * t
	return p.distance_squared_to(c) <= r * r

## 返回点所在的第一个有效碰撞体（无则空字典）。碰撞体可带 mat 标签：
## hard（默认，岩石/金属/混凝土/树干）全挡；wood（木箱/木板）玩家子弹可穿透
func _collider_at(p: Vector3, colliders: Array) -> Dictionary:
	for c in colliders:
		if c.get("disabled", false) or c.get("no_collide", false):
			continue
		var y0 := float(c.get("y0", 0.0))
		if p.y < y0 or p.y > y0 + float(c.get("h", 6.0)):
			continue
		if c["type"] == "box":
			if absf(p.x - float(c["x"])) <= float(c["w"]) / 2.0 and absf(p.z - float(c["z"])) <= float(c["d"]) / 2.0:
				return c
		elif c["type"] == "circle":
			var dx := p.x - float(c["x"])
			var dz := p.z - float(c["z"])
			var r := float(c["r"])
			if dx * dx + dz * dz <= r * r:
				return c
	return {}

## 子弹命中掩体/地形：火花粒子（按传入色调染），替代旧发光球
func spawn_impact_fx(pos: Vector3, color: Color) -> void:
	var arr: Array = _hit_emitters.get("spark", [])
	if arr.is_empty():
		return
	var idx := int(_hit_idx.get("spark", 0))
	_hit_idx["spark"] = idx + 1
	var p := arr[idx % arr.size()] as GPUParticles3D
	(p.process_material as ParticleProcessMaterial).color = color
	p.global_position = pos
	p.restart()

## 木质掩体承伤：打烂后碰撞失效、网格移除（掩体是真能打坏的）
func _damage_wood(c: Dictionary, dmg: int) -> void:
	if not c.has("hp"):
		return
	c["hp"] = float(c["hp"]) - float(dmg)
	if float(c["hp"]) <= 0.0 and not bool(c.get("disabled", false)):
		c["disabled"] = true
		var node = c.get("node")
		if node != null and is_instance_valid(node):
			spawn_impact_fx((node as Node3D).global_position, Color(0.8, 0.6, 0.35))
			(node as Node).queue_free()

func update_projectiles(dt: float, args: Dictionary) -> void:
	var targets: Array = args["targets"]
	var colliders: Array = args["colliders"]
	var player = args["player"]
	var on_player_hit: Callable = args["on_player_hit"]
	var th: Callable = args.get("terrain_h", Callable()) # 地形高度回调：子弹/光弹/榴弹都不能穿山钻地
	_th = th
	var on_enemy_hit: Callable = args.get("on_enemy_hit", Callable()) # 玩家命中敌人回调（main 用作顿帧触发）
	var gen0 := _gen

	# ---- 玩家子弹 ----
	for i in range(_bullets.size() - 1, -1, -1):
		var b: Dictionary = _bullets[i]
		if int(b["gen"]) != gen0:
			continue
		b["life"] = float(b["life"]) - dt
		var prev: Vector3 = b["pos"]
		var np: Vector3 = prev + b["dir"] * float(b["speed"]) * dt
		b["pos"] = np
		var dead := float(b["life"]) <= 0.0
		if not dead:
			for t in targets:
				if not t.alive or t.get("targetable") == false:
					continue
				if _seg_sphere(prev, np, Vector3(t.hit_x, t.hit_y, t.hit_z), float(t.hit_r)):
					t.on_hit(int(b["damage"]), np)
					if gen0 != _gen:
						return # 回调链中发生了 clear_all，整帧放弃
					if on_enemy_hit.is_valid():
						on_enemy_hit.call() # 命中确认 → main 顿帧（带冷却防连发叠加）
					if not bool(b["pierce"]):
						dead = true
					break
		if not dead:
			# 中点+终点双采样，防高速子弹一步跨过薄掩体
			var hit_c := _collider_at((prev + np) * 0.5, colliders)
			var hit_p := (prev + np) * 0.5
			if hit_c.is_empty():
				hit_c = _collider_at(np, colliders)
				hit_p = np
			if not hit_c.is_empty():
				if String(hit_c.get("mat", "hard")) == "wood":
					if not (b["pen"] as Array).has(hit_c):
						(b["pen"] as Array).append(hit_c)
						var dmg_now := int(b["damage"])
						_damage_wood(hit_c, dmg_now) # 木头吃全额伤害
						b["damage"] = maxi(1, dmg_now / 2) # 穿出后伤害减半
						spawn_impact_fx(hit_p, Color(0.8, 0.6, 0.35))
				else:
					spawn_impact_fx(hit_p, Color(1, 0.78, 0.42))
					dead = true
		if not dead and th.is_valid():
			# 地形阻挡：中点+终点采样，子弹钻进山坡/地面即止（开放地形必须有这一层）
			var mid := (prev + np) * 0.5
			if np.y < float(th.call(np.x, np.z)) + 0.03 or mid.y < float(th.call(mid.x, mid.z)) + 0.03:
				spawn_impact_fx(np, Color(0.75, 0.68, 0.5))
				dead = true
		if dead:
			_give(b["pool"], b["mesh"])
			_bullets.remove_at(i)
		else:
			b["mesh"].global_position = np
			if bool(b["wave"]):
				var s := 1.0 + sin(Time.get_ticks_msec() * 0.03) * 0.35
				b["mesh"].scale = (b["s0"] as Vector3) * s

	# ---- 敌方弹丸/圆盘 ----
	for i in range(_orbs.size() - 1, -1, -1):
		var o: Dictionary = _orbs[i]
		if int(o["gen"]) != gen0:
			continue
		o["life"] = float(o["life"]) - dt
		var np: Vector3 = o["pos"] + o["dir"] * float(o["speed"]) * dt
		o["pos"] = np
		var dead := float(o["life"]) <= 0.0
		var cause := "life" if dead else ""
		if not dead and player != null and player.alive:
			var pp: Vector3 = player.global_position
			var dx := np.x - pp.x
			var dz := np.z - pp.z
			var top := 0.62 if player.prone else 1.78
			if dx * dx + dz * dz < 0.42 and np.y > pp.y + 0.05 and np.y < pp.y + top:
				on_player_hit.call(int(o["damage"]))
				if gen0 != _gen:
					return
				dead = true
				cause = "hit"
		if not dead and not _collider_at(np, colliders).is_empty():
			# 敌方光弹是低速能量体：任何实体掩体（含木箱）都能挡
			spawn_impact_fx(np, Color(1, 0.5, 0.3))
			dead = true
			cause = "hit"
		if not dead and th.is_valid() and np.y < float(th.call(np.x, np.z)) + 0.03:
			# 光弹同样被地形挡住——躲进山坳就打不着
			spawn_impact_fx(np, Color(1, 0.5, 0.3))
			dead = true
			cause = "hit"
		if dead:
			# 重弹/圆盘命中时播全套爆炸视觉（纯表现；伤判仍只有原本的直击，不加范围伤）
			var boom_r := float(o.get("boom", 0.0))
			if boom_r <= 0.0 and o.get("disc", false):
				boom_r = 1.5
			if boom_r > 0.0 and cause == "hit":
				spawn_explosion_fx(np, boom_r)
			_give(o["pool"], o["mesh"])
			_orbs.remove_at(i)
		else:
			o["mesh"].global_position = np
			if o.get("disc", false):
				o["mesh"].rotation.y += dt * 14.0

	# ---- 榴弹 ----
	for i in range(_grenades.size() - 1, -1, -1):
		var g: Dictionary = _grenades[i]
		if int(g["gen"]) != gen0:
			continue
		var vel: Vector3 = g["vel"]
		vel.y -= 16.0 * dt
		g["vel"] = vel
		var np: Vector3 = g["pos"] + vel * dt
		g["pos"] = np
		g["mesh"].global_position = np
		# 炮弹烟拖尾：每 0.03 秒留一团烟，弧线全程可读
		g["trail_t"] = float(g.get("trail_t", 0.0)) - dt
		if float(g["trail_t"]) <= 0.0:
			g["trail_t"] = 0.03
			spawn_smoke_puff(np)
		var boom := false
		var ground_y := 0.15
		if th.is_valid():
			ground_y = float(th.call(np.x, np.z)) + 0.15
		if np.y <= ground_y:
			boom = true
		if player != null and player.alive and np.distance_to(player.global_position + Vector3(0, 0.8, 0)) < 1.1:
			boom = true
		if boom:
			spawn_explosion_fx(np, 2.3)
			if player != null and player.alive:
				var pp: Vector3 = player.global_position
				var dx := pp.x - np.x
				var dz := pp.z - np.z
				if dx * dx + dz * dz < 5.3 and pp.y < np.y + 2.0:
					on_player_hit.call(1)
					if gen0 != _gen:
						return
			_give(g["pool"], g["mesh"])
			_grenades.remove_at(i)

	# ---- 爆炸核心闪光（短促：0.16 秒内膨胀淡出，只做闪光不再冒充火球）----
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f["t"] = float(f["t"]) + dt
		var k := float(f["t"]) / float(f["dur"])
		if k >= 1.0:
			_give(f["pool"], f["mesh"])
			_fx.remove_at(i)
		else:
			var e := 1.0 - pow(1.0 - k, 2.0)
			var s := lerpf(float(f["radius"]) * 0.3, float(f["radius"]) * 0.85, e)
			f["mesh"].scale = Vector3(s, s, s)
			var m: StandardMaterial3D = f["mesh"].material_override
			m.albedo_color.a = 0.5 * (1.0 - k)
	for l in _lights:
		if l.light_energy > 0.0:
			l.light_energy = maxf(0.0, l.light_energy - dt * 14.0)

	# ---- 枪口闪光面片 + 点光衰减 ----
	for i in range(_flashes.size() - 1, -1, -1):
		var fl: Dictionary = _flashes[i]
		fl["t"] = float(fl["t"]) + dt
		var fk := float(fl["t"]) / float(fl["dur"])
		if fk >= 1.0:
			_give(fl["pool"], fl["mesh"])
			_flashes.remove_at(i)
		else:
			fl["mesh"].scale = Vector3.ONE * float(fl["s0"]) * (1.1 - 0.35 * fk)
	if _muzzle_light and _muzzle_light.light_energy > 0.0:
		_muzzle_light.light_energy = maxf(0.0, _muzzle_light.light_energy - dt * 46.0)

	# ---- 冲击波环 ----
	for i in range(_rings.size() - 1, -1, -1):
		var r: Dictionary = _rings[i]
		r["t"] = float(r["t"]) + dt
		var rk := float(r["t"]) / float(r["dur"])
		if rk >= 1.0:
			_give(r["pool"], r["mesh"])
			_rings.remove_at(i)
		else:
			var re := 1.0 - pow(1.0 - rk, 2.0)
			var rs := lerpf(0.3, float(r["radius"]) * 1.25, re)
			r["mesh"].scale = Vector3(rs, 1.0, rs)
			((r["mesh"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.5 * (1.0 - rk)

	# ---- 抛弹壳 ----
	for i in range(_shells.size() - 1, -1, -1):
		var sh: Dictionary = _shells[i]
		sh["t"] = float(sh["t"]) + dt
		var sm := sh["mesh"] as MeshInstance3D
		if float(sh["t"]) >= 1.5:
			_give(sh["pool"], sm)
			_shells.remove_at(i)
			continue
		if not bool(sh["rest"]):
			var vel2: Vector3 = sh["vel"]
			vel2.y -= 12.0 * dt
			sh["vel"] = vel2
			var np2: Vector3 = sm.global_position + vel2 * dt
			var floor_y := 0.03
			if _th.is_valid():
				floor_y = float(_th.call(np2.x, np2.z)) + 0.03
			if np2.y <= floor_y and vel2.y < 0.0:
				np2.y = floor_y
				if absf(vel2.y) > 0.9:
					vel2.y = -vel2.y * 0.38
					vel2.x *= 0.7
					vel2.z *= 0.7
					sh["vel"] = vel2
					sh["ang"] = (sh["ang"] as Vector3) * 0.5
				else:
					sh["rest"] = true
			sm.global_position = np2
			sm.rotation += (sh["ang"] as Vector3) * dt
		if float(sh["t"]) > 1.3:
			sm.scale = Vector3.ONE * maxf(0.05, (1.5 - float(sh["t"])) / 0.2)

	# ---- 地面残留（血泊/焦痕）----
	for i in range(_pools.size() - 1, -1, -1):
		var pl: Dictionary = _pools[i]
		pl["t"] = float(pl["t"]) + dt
		var left := float(pl["life"]) - float(pl["t"])
		if left <= 0.0:
			pl["mesh"].queue_free()
			_pools.remove_at(i)
		elif left < 3.0:
			(pl["mesh"].material_override as StandardMaterial3D).albedo_color.a = 0.85 * left / 3.0

func destroy_all() -> void:
	clear_all()
	for f in _fx:
		if is_instance_valid(f["mesh"]):
			f["mesh"].queue_free()
	_fx.clear()
	for pool in [_free_bullets, _free_orbs, _free_discs, _free_fx, _free_shells, _free_flash, _free_rings]:
		for m in pool:
			if is_instance_valid(m):
				m.queue_free()
		pool.clear()
	for pl in _pools:
		if is_instance_valid(pl["mesh"]):
			pl["mesh"].queue_free()
	_pools.clear()
