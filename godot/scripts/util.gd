class_name Util
extends RefCounted

## 共享工具：PBR 材质（CC0 实拍贴图）、基础网格搭建、种子随机

static var _tex_cache: Dictionary = {}

static func tex_diff(n: String) -> Texture2D:
	if not _tex_cache.has(n):
		_tex_cache[n] = load("res://assets/tex/%s_diff.jpg" % n)
	return _tex_cache[n]

static func tex_nor(n: String) -> Texture2D:
	var k := n + "_nor"
	if not _tex_cache.has(k):
		_tex_cache[k] = load("res://assets/tex/%s.jpg" % k)
	return _tex_cache[k]

static func pbr(color: Color, tex_name: String = "", rough: float = 0.85, metal: float = 0.0, rep: Vector2 = Vector2.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = 5 # TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC：各向异性过滤，斜着看地面/墙面贴图不糊（现代 3D 标配）
	if tex_name != "":
		m.albedo_texture = tex_diff(tex_name)
		m.normal_texture = tex_nor(tex_name)
		m.normal_scale = 0.7
		m.texture_repeat = 1 # TEXTURE_REPEAT_ENABLED
		m.uv1_scale = Vector3(rep.x, rep.y, 1.0)
	return m

static func glow(color: Color, energy: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func flat(color: Color, alpha: float = -1.0) -> StandardMaterial3D:
	# alpha 省略时用 color 自带的透明度——历史上调用方都把透明度写在 Color 里，
	# 而旧实现用参数 1.0 覆盖了它，护盾/电网/屏障全渲染成不透明（实测教训）
	var a := color.a if alpha < 0.0 else alpha
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, a)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func box(parent: Node, size: Vector3, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func cyl(parent: Node, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3 = Vector3.ZERO, sides: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func sph(parent: Node, r: float, mat: Material, pos: Vector3 = Vector3.ZERO, w: int = 14, h: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = w
	sm.rings = h
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func capsule(parent: Node, r: float, h: float, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func seeded(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r
