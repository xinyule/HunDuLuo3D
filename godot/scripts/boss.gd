class_name Boss
extends Node3D

## Boss —— 部件制弱点框架（8 只各有机制，见原作解析文档）
## 部件 Part 与敌人共用可击接口：hit_x/hit_y/hit_z/hit_r/alive/targetable/on_hit

class Part:
	extends RefCounted
	var part_name := ""
	var hp := 1
	var max_hp := 1
	var alive := true
	var targetable := true
	var vulnerable := true
	var is_core := false
	var hit_x := 0.0
	var hit_y := 0.0
	var hit_z := 0.0
	var hit_r := 1.0
	var node: Node3D
	var owner: Boss
	func on_hit(dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
		if owner:
			owner._part_hit(self, dmg, _point)

var boss_id := ""
var alive := true
var activated := false
var targets: Array = []
var _ctx: Dictionary
var _group: Node3D
var _t := 0.0
var _fire_timer := 2.0
var _special_timer := 5.0
var _total_hp := 1
var _total_max := 1
var _mats: Array = []
var _anim_nodes: Dictionary = {}
var _reinf_timer := 6.0 # 最终 Boss 增援首波延迟（1.2.0）
var _reinforcements: Array = []

func setup(p_id: String, pos: Vector3, ctx: Dictionary) -> void:
	boss_id = p_id
	_ctx = ctx
	global_position = pos
	_group = Node3D.new()
	add_child(_group)
	match p_id:
		"defenseWall": _build_wall(false)
		"finalGate": _build_wall(true)
		"baseCore": _build_base_core()
		"gromaides": _build_gromaides()
		"godomuga": _build_godomuga()
		"guldaf": _build_guldaf()
		"gordea": _build_gordea()
		"alienHeart": _build_alien_heart()
	_total_max = 0
	_total_hp = 0
	for p in targets:
		_total_max += p.max_hp
		_total_hp += p.hp
	_sync_part_positions()

func activate() -> void:
	activated = true

var hp_fraction: float:
	get:
		return clampf(float(_total_hp) / float(maxi(1, _total_max)), 0.0, 1.0)

func _pbr(c: Color, rough: float = 0.7, metal: float = 0.2, tex: String = "") -> Material:
	var m := Util.pbr(c, tex, rough, metal)
	_mats.append(m)
	return m

func _glow(c: Color, e: float = 2.6) -> Material:
	var m := Util.glow(c, e)
	_mats.append(m)
	return m

func _add_part(part_name: String, hp: int, node: Node3D, r: float, core: bool = false) -> Part:
	var p := Part.new()
	p.part_name = part_name
	p.hp = hp
	p.max_hp = hp
	p.node = node
	p.hit_r = r
	p.is_core = core
	p.owner = self
	targets.append(p)
	return p

func _sync_part_positions() -> void:
	for p in targets:
		if p.node and is_instance_valid(p.node):
			var gp: Vector3 = p.node.global_position
			p.hit_x = gp.x
			p.hit_y = gp.y
			p.hit_z = gp.z

# ---------------- 建模 ----------------
# 带平铺重复的 PBR（大面积石/混凝土面用，避免贴图被拉成一整张糊脸）
func _pbr2(c: Color, rough: float, metal: float, tex: String, rep: Vector2) -> Material:
	var m := Util.pbr(c, tex, rough, metal, rep)
	_mats.append(m)
	return m

# 压扁/拉伸球（碟身、颅腔、肉团等曲面体）
func _sphs(parent: Node, r: float, mat: Material, pos: Vector3, scl: Vector3, w: int = 18, h: int = 14) -> MeshInstance3D:
	var mi := Util.sph(parent, r, mat, pos, w, h)
	mi.scale = scl
	return mi

# 圆环：TorusMesh 原生平放在 XZ 面；face_z=true（默认）转正对 +Z（核心舱环/眼框），false 平放（颈圈/碟边）
func _torus(parent: Node, radius: float, ring: float, mat: Material, pos: Vector3, sides: int = 28, face_z: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - ring
	tm.outer_radius = radius + ring
	tm.rings = sides
	tm.ring_segments = 12
	mi.mesh = tm
	mi.material_override = mat
	mi.position = pos
	if face_z:
		mi.rotation.x = PI / 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

# 两点间圆柱（肢体/蛇颈/血管/斜撑）：r_a 在 a 端、r_b 在 b 端
func _limb(parent: Node, a: Vector3, b: Vector3, r_a: float, r_b: float, mat: Material, sides: int = 10) -> MeshInstance3D:
	var dir := b - a
	var len := dir.length()
	var mid := (a + b) * 0.5
	var mi := Util.cyl(parent, r_b, r_a, len, mat, mid, sides)
	var d := dir / len
	if absf(d.y) > 0.999:
		mi.transform = Transform3D(Basis(Vector3.RIGHT, PI if d.y < 0.0 else 0.0), mid)
	else:
		mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, d)), mid)
	return mi

func _build_wall(big: bool) -> void:
	# 防御壁与最终闸门共用炮塔/核心锚点（玩法零差异），墙体构图完全不同
	if big:
		_build_gate()
	else:
		_build_fortress()

# 旋转炮塔：锚点 (±6.3s, 3.05s, 1.05)、hit_r 1.3 与旧版一致；子件绕节点原点转 Y
func _wall_turret(sx: float, s: float, main_m: Material, dark: Material) -> Node3D:
	Util.box(_group, Vector3(3.2 * s, 1.5 * s, 1.9), dark, Vector3(sx, 2.05 * s, 0.8)) # 炮座
	var tur := Node3D.new()
	tur.position = Vector3(sx, 3.05 * s, 1.05)
	_group.add_child(tur)
	var barrel_m := _pbr(Color(0.07, 0.07, 0.08), 0.35, 0.85)
	Util.cyl(tur, 1.02, 1.14, 0.5, dark, Vector3(0, -0.18, 0), 16) # 塔座
	_torus(tur, 0.9, 0.13, main_m, Vector3(0, 0.1, 0), 20, false) # 颈圈平放
	_sphs(tur, 0.86, main_m, Vector3(0, 0.3, 0), Vector3(1, 0.85, 1), 18, 12) # 穹顶
	Util.box(tur, Vector3(0.95, 0.55, 0.55), dark, Vector3(0, 0.42, 0.5)) # 炮盾
	for bx in [-0.28, 0.28]:
		var barrel := Util.cyl(tur, 0.085, 0.095, 1.5, barrel_m, Vector3(bx, 0.45, 0.95), 10)
		barrel.rotation.x = PI / 2.0
		var muzzle := Util.cyl(tur, 0.13, 0.13, 0.28, dark, Vector3(bx, 0.45, 1.62), 10)
		muzzle.rotation.x = PI / 2.0
	Util.sph(tur, 0.16, _glow(Color(1, 0.15, 0.1), 2.6), Vector3(0, 0.88, 0.4), 10, 8) # 传感器眼
	Util.box(tur, Vector3(0.55, 0.42, 0.95), dark, Vector3(signf(sx) * 1.28, 0.05, -0.15)) # 外侧弹药箱
	var ant := Util.cyl(tur, 0.02, 0.03, 0.85, dark, Vector3(-0.5, 0.95, -0.3), 6)
	ant.rotation.z = 0.15
	return tur

# 中央核心舱：锚点 (0, 3.9s, 0.95)、hit_r 1.1s 与旧版一致；红核嵌进双环舱座，不再是裸球贴墙
func _wall_core(s: float, main_m: Material, dark: Material) -> void:
	var socket := Util.cyl(_group, 1.66 * s, 1.66 * s, 0.5, dark, Vector3(0, 3.9 * s, 0.42), 24)
	socket.rotation.x = PI / 2.0
	_torus(_group, 1.38 * s, 0.19 * s, main_m, Vector3(0, 3.9 * s, 0.72))
	_torus(_group, 1.08 * s, 0.08 * s, dark, Vector3(0, 3.9 * s, 0.86))
	for i in 4:
		var a := PI / 4.0 + float(i) * PI / 2.0
		Util.sph(_group, 0.11 * s, dark, Vector3(cos(a) * 1.38 * s, 3.9 * s + sin(a) * 1.38 * s, 0.8), 8, 6)
	var core := Util.sph(_group, 0.98 * s, _glow(Color(1, 0.13, 0.13), 3.2), Vector3(0, 3.9 * s, 0.95), 20, 16)
	var core_p := _add_part("core", 1088, core, 1.1 * s, true) # 对标原版 32 发（调平表 §5）
	core_p.vulnerable = false
	_anim_nodes["core"] = core

# 防御壁（第 1 关）：FC 原版构图——堡垒墙体 + 双炮塔 + 中央核心舱
func _build_fortress() -> void:
	var s := 1.0
	var steel := _pbr(Color(0.88, 0.91, 0.97), 0.48, 0.68, "metal")
	var steel_lt := _pbr(Color(0.98, 1.0, 1.05), 0.42, 0.72, "metal")
	var dark := _pbr(Color(0.36, 0.38, 0.42), 0.62, 0.55, "metal")
	var conc := _pbr2(Color(0.52, 0.5, 0.46), 0.92, 0.0, "concrete", Vector2(3, 1))
	# 两级基座台
	Util.box(_group, Vector3(19.2, 1.1, 3.2), conc, Vector3(0, 0.55, 0))
	Util.box(_group, Vector3(18.4, 0.75, 2.6), dark, Vector3(0, 1.45, 0))
	# 三段墙板：外框 + 凹陷内板 + 亮面芯板 + 竖缝 + 铆钉
	for i in 3:
		var px := -6.0 + float(i) * 6.0
		Util.box(_group, Vector3(5.7, 5.3, 1.05), steel, Vector3(px, 4.25, 0))
		Util.box(_group, Vector3(4.55, 4.15, 0.16), dark, Vector3(px, 4.25, 0.56))
		Util.box(_group, Vector3(3.85, 3.45, 0.12), steel_lt, Vector3(px, 4.25, 0.66))
		Util.box(_group, Vector3(0.32, 5.3, 0.22), dark, Vector3(px + 2.95, 4.25, 0.6))
		for ry in [2.35, 6.15]:
			for rx in [-2.45, 2.45]:
				var rivet := Util.cyl(_group, 0.07, 0.07, 0.08, dark, Vector3(px + rx, ry, 0.6), 8)
				rivet.rotation.x = PI / 2.0
	# 两侧扶壁塔 + 正面光带 + 塔顶信标
	for sx in [-8.85, 8.85]:
		Util.box(_group, Vector3(1.7, 7.3, 2.3), steel, Vector3(sx, 3.65, 0))
		Util.box(_group, Vector3(1.95, 0.55, 2.55), dark, Vector3(sx, 7.55, 0))
		Util.box(_group, Vector3(0.2, 5.6, 0.12), _glow(Color(1, 0.55, 0.1), 1.4), Vector3(sx, 4.0, 1.18))
		Util.sph(_group, 0.17, _glow(Color(1, 0.2, 0.1), 2.4), Vector3(sx, 8.05, 0), 8, 6)
	# 顶梁 + 垛口 + 警示灯带
	Util.box(_group, Vector3(18.4, 0.8, 1.8), dark, Vector3(0, 7.3, 0))
	for i in 5:
		Util.box(_group, Vector3(1.6, 0.5, 0.7), steel, Vector3(-7.2 + float(i) * 3.6, 7.95, 0.5))
	Util.box(_group, Vector3(17.6, 0.18, 0.1), _glow(Color(1, 0.55, 0.1), 1.6), Vector3(0, 6.82, 0.95))
	var turrets: Array = []
	for sx in [-6.3, 6.3]:
		var tur := _wall_turret(sx, s, steel, dark)
		turrets.append(tur)
		_add_part("turret", 544, tur, 1.3) # 对标原版 16 发（调平表 §5：防御壁/最终闸门炮塔同值）
	_anim_nodes["turrets"] = turrets
	_wall_core(s, steel, dark)

# 最终闸门（第 7 关）：与防御壁彻底区分——双扇装甲闸门 + X 形斜撑 + 门柱塔 + 能量门缝
func _build_gate() -> void:
	var s := 1.25
	var rust := _pbr(Color(0.78, 0.55, 0.44), 0.58, 0.55, "rust")
	var rust_dk := _pbr(Color(0.55, 0.38, 0.3), 0.66, 0.45, "rust")
	var dark := _pbr(Color(0.3, 0.28, 0.28), 0.6, 0.6, "metal")
	var conc := _pbr2(Color(0.4, 0.38, 0.35), 0.95, 0.0, "concrete", Vector2(3, 1))
	Util.box(_group, Vector3(19.5 * s, 1.1, 3.4), conc, Vector3(0, 0.55, 0))
	Util.box(_group, Vector3(18.6 * s, 0.7, 2.7), dark, Vector3(0, 1.45, 0))
	# 两侧门柱塔（正面竖光带 + 塔顶信标）
	for sx in [-8.3 * s, 8.3 * s]:
		Util.box(_group, Vector3(2.7 * s, 8.4 * s, 2.7), rust_dk, Vector3(sx, 4.2 * s, 0))
		Util.box(_group, Vector3(3.1 * s, 0.6, 3.1), dark, Vector3(sx, 8.7 * s, 0))
		Util.box(_group, Vector3(0.5, 6.8 * s, 0.1), _glow(Color(1, 0.55, 0.1), 1.5), Vector3(sx, 4.6 * s, 1.38))
		Util.sph(_group, 0.2, _glow(Color(1, 0.25, 0.1), 2.4), Vector3(sx, 9.15 * s, 0), 8, 6)
	# 双扇闸门：门板 + 上下横梁 + X 形斜撑
	for side in [-1.0, 1.0]:
		var cx: float = side * 3.95 * s
		Util.box(_group, Vector3(7.7 * s, 6.3 * s, 0.85), rust, Vector3(cx, 4.5 * s, 0))
		Util.box(_group, Vector3(7.7 * s, 0.55, 0.2), dark, Vector3(cx, 7.35 * s, 0.5))
		Util.box(_group, Vector3(7.7 * s, 0.55, 0.2), dark, Vector3(cx, 1.65 * s, 0.5))
		var brace := Util.box(_group, Vector3(9.6 * s, 0.62, 0.18), dark, Vector3(cx, 4.5 * s, 0.52))
		brace.rotation.z = side * 0.68
		var brace2 := Util.box(_group, Vector3(9.6 * s, 0.62, 0.18), dark, Vector3(cx, 4.5 * s, 0.52))
		brace2.rotation.z = -side * 0.68
	# 中央门缝 + 能量缝光带 + 门楣填充板
	Util.box(_group, Vector3(0.55, 6.3 * s, 1.0), dark, Vector3(0, 4.5 * s, 0))
	Util.box(_group, Vector3(0.13, 5.9 * s, 0.1), _glow(Color(1, 0.6, 0.15), 2.0), Vector3(0, 4.5 * s, 0.53))
	Util.box(_group, Vector3(13.5 * s, 0.85, 0.5), rust_dk, Vector3(0, 7.92 * s, 0))
	# 顶梁 + 两根液压斜杆
	Util.box(_group, Vector3(19.2 * s, 1.0, 2.3), dark, Vector3(0, 8.6 * s, 0))
	for sx in [-6.9 * s, 6.9 * s]:
		_limb(_group, Vector3(sx, 8.1 * s, 0.9), Vector3(sx * 0.55, 6.4 * s, 0.9), 0.17, 0.11, rust_dk, 10)
	var turrets: Array = []
	for sx in [-6.3 * s, 6.3 * s]:
		var tur := _wall_turret(sx, s, rust, dark)
		turrets.append(tur)
		_add_part("turret", 544, tur, 1.3) # 对标原版 16 发（调平表 §5）
	_anim_nodes["turrets"] = turrets
	_wall_core(s, rust, dark)
	# 核心舱装甲眉（闸门版独有，上下遮罩衬出核心舱）
	Util.box(_group, Vector3(3.6 * s, 0.5, 0.7), dark, Vector3(0, 5.35 * s, 0.6))
	Util.box(_group, Vector3(3.6 * s, 0.5, 0.7), dark, Vector3(0, 2.45 * s, 0.6))

func _build_base_core() -> void:
	# 独炎眼（第 2 关）：墙体机座 + 中央巨型独眼（眼睑+环框+瞳孔）+ 两侧炮舱
	# 锚点不变：pod 节点 (±2.6,2.6,0.9) r0.62；eye 球 (0,5.4,0.8) r1.15——update 靠缩放它做开/闭眼
	var steel := _pbr(Color(0.7, 0.76, 0.86), 0.5, 0.65, "metal")
	var dark := _pbr(Color(0.32, 0.35, 0.42), 0.6, 0.55, "metal")
	var brass := _pbr(Color(0.55, 0.42, 0.2), 0.4, 0.8)
	# 机座墙：主板 + 凹陷面板 + 两侧立柱 + 底裙
	Util.box(_group, Vector3(7.6, 6.6, 0.9), steel, Vector3(0, 3.3, -0.3))
	Util.box(_group, Vector3(6.4, 5.4, 0.14), dark, Vector3(0, 3.3, 0.18))
	Util.box(_group, Vector3(0.7, 6.6, 1.3), dark, Vector3(-3.85, 3.3, -0.2))
	Util.box(_group, Vector3(0.7, 6.6, 1.3), dark, Vector3(3.85, 3.3, -0.2))
	Util.box(_group, Vector3(8.6, 0.85, 1.9), dark, Vector3(0, 0.42, 0))
	Util.box(_group, Vector3(8.6, 0.16, 0.1), _glow(Color(1, 0.55, 0.1), 1.5), Vector3(0, 0.9, 0.96))
	# 眼眶：凹座 + 金属环框 + 上下眼睑壳（眼球缩放收进睑内=闭眼）
	_sphs(_group, 1.5, dark, Vector3(0, 5.4, 0.3), Vector3(1, 1, 0.55), 20, 16)
	_torus(_group, 1.3, 0.22, brass, Vector3(0, 5.4, 0.66))
	_sphs(_group, 1.32, dark, Vector3(0, 6.35, 0.5), Vector3(1.05, 0.5, 0.75), 18, 12)
	_sphs(_group, 1.32, dark, Vector3(0, 4.45, 0.5), Vector3(1.05, 0.5, 0.75), 18, 12)
	var brow := Util.box(_group, Vector3(3.3, 0.42, 0.6), dark, Vector3(0, 6.48, 0.55))
	brow.rotation.x = -0.18
	var eye := Util.sph(_group, 1.15, _glow(Color(1, 0.2, 0.2), 3.0), Vector3(0, 5.4, 0.8), 20, 16)
	Util.sph(eye, 0.4, _glow(Color(0.25, 0.02, 0.03), 0.7), Vector3(0, 0, 0.82), 12, 10) # 瞳孔（眼球子节点，随开/闭眼缩放）
	var eye_p := _add_part("eye", 544, eye, 1.3, true) # 对标原版 16 发（调平表 §5）
	_anim_nodes["eye"] = eye
	_anim_nodes["eye_part"] = eye_p
	# 两侧炮舱：支臂 + 装甲球舱 + 炮管 + 传感透镜；线缆回墙
	for sx in [-2.6, 2.6]:
		Util.box(_group, Vector3(0.55, 0.55, 1.1), dark, Vector3(sx, 2.6, 0.25))
		var pod := Node3D.new()
		pod.position = Vector3(sx, 2.6, 0.9)
		_group.add_child(pod)
		_sphs(pod, 0.52, steel, Vector3.ZERO, Vector3(1, 1, 1.15), 16, 12)
		var barrel := Util.cyl(pod, 0.11, 0.13, 0.9, dark, Vector3(0, -0.12, 0.55), 10)
		barrel.rotation.x = PI / 2.0
		Util.sph(pod, 0.17, _glow(Color(1, 0.65, 0.0), 2.4), Vector3(0, 0.22, 0.48), 10, 8)
		_limb(_group, Vector3(sx, 3.15, 0.6), Vector3(sx * 0.82, 4.6, 0.05), 0.07, 0.07, dark, 8)
		_limb(_group, Vector3(sx * 0.82, 4.6, 0.05), Vector3(sx * 0.4, 5.9, 0.0), 0.07, 0.07, dark, 8)
		_add_part("pod", 272, pod, 0.62) # 对标原版房核心级 8 发（调平表 §5）

func _build_gromaides() -> void:
	# 阴兽魔神像（第 3 关）：石质坐像——阶梯基座、盘腿、躯干、双臂利爪、带角魔颅
	# 锚点不变：head (0,6.6,0.4)；jaw 子节点基准 (0,-1.25,0.3)（update 只改其 y）；mouth 球 (0,-0.55,1.15)@head r0.85
	var stone := _pbr2(Color(0.68, 0.67, 0.64), 0.95, 0.0, "concrete", Vector2(3, 2))
	var stone_dk := _pbr2(Color(0.5, 0.49, 0.47), 0.97, 0.0, "concrete", Vector2(3, 2))
	var bone := _pbr(Color(0.72, 0.67, 0.57), 0.8, 0.0)
	# 阶梯基座 + 盘坐腿盘 + 膝 + 脚
	Util.box(_group, Vector3(7.4, 0.7, 3.8), stone_dk, Vector3(0, 0.35, 0))
	Util.box(_group, Vector3(6.3, 0.7, 3.2), stone, Vector3(0, 1.05, 0))
	Util.box(_group, Vector3(5.6, 1.15, 2.6), stone, Vector3(0, 1.95, 0))
	_sphs(_group, 0.88, stone, Vector3(-2.25, 2.25, 0.85), Vector3(1, 0.8, 1), 14, 10)
	_sphs(_group, 0.88, stone, Vector3(2.25, 2.25, 0.85), Vector3(1, 0.8, 1), 14, 10)
	Util.box(_group, Vector3(1.35, 0.55, 1.15), stone_dk, Vector3(-1.7, 1.62, 1.3))
	Util.box(_group, Vector3(1.35, 0.55, 1.15), stone_dk, Vector3(1.7, 1.62, 1.3))
	# 躯干：收腰石柱 + 腹团 + 胸盘符环
	Util.cyl(_group, 1.55, 2.05, 2.6, stone, Vector3(0, 3.85, 0), 14)
	_sphs(_group, 1.6, stone, Vector3(0, 3.15, 0.5), Vector3(1.05, 0.9, 0.75), 16, 12)
	var chest := Util.cyl(_group, 1.02, 1.02, 0.24, stone_dk, Vector3(0, 4.4, 1.3), 20)
	chest.rotation.x = PI / 2.0
	_torus(_group, 0.55, 0.07, _glow(Color(1, 0.6, 0.15), 1.3), Vector3(0, 4.4, 1.46))
	# 肩 + 双臂（上臂下垂、前臂前探，爪手按在膝前）
	_sphs(_group, 1.0, stone, Vector3(-2.2, 4.9, 0), Vector3(1.15, 0.85, 1), 14, 10)
	_sphs(_group, 1.0, stone, Vector3(2.2, 4.9, 0), Vector3(1.15, 0.85, 1), 14, 10)
	for sx in [-1.0, 1.0]:
		_limb(_group, Vector3(sx * 2.55, 4.75, 0.1), Vector3(sx * 3.05, 3.35, 0.5), 0.52, 0.44, stone, 12)
		_limb(_group, Vector3(sx * 3.05, 3.35, 0.5), Vector3(sx * 2.45, 2.4, 1.15), 0.44, 0.37, stone, 12)
		_sphs(_group, 0.52, stone_dk, Vector3(sx * 2.42, 2.25, 1.32), Vector3(1, 0.78, 1.15), 12, 9) # 爪手
		for ci in 3:
			var claw := Util.cyl(_group, 0.055, 0.008, 0.34, bone, Vector3(sx * 2.42 + (float(ci) - 1.0) * 0.24, 2.02, 1.66), 6)
			claw.rotation.x = 0.55
	Util.cyl(_group, 0.85, 1.0, 0.85, stone_dk, Vector3(0, 5.6, 0.3), 12) # 颈
	# 魔颅（head 节点内）：颅腔 + 面团 + 眉脊 + 獠牙 + 双角 + 耳鳍
	var head := Node3D.new()
	head.position = Vector3(0, 6.6, 0.4)
	_group.add_child(head)
	_sphs(head, 1.42, stone, Vector3(0, 0.18, -0.15), Vector3(1.02, 0.92, 0.98), 20, 16)
	_sphs(head, 1.05, stone, Vector3(0, -0.28, 0.35), Vector3(0.92, 0.85, 0.8), 18, 14)
	var brow := Util.box(head, Vector3(2.3, 0.42, 0.55), stone_dk, Vector3(0, 0.55, 0.95))
	brow.rotation.x = -0.15
	Util.box(head, Vector3(0.34, 0.55, 0.4), stone_dk, Vector3(0, -0.12, 1.12)).rotation.x = 0.2
	for sx in [-1.0, 1.0]:
		Util.sph(head, 0.17, _glow(Color(1, 0.85, 0.2), 2.6), Vector3(sx * 0.56, 0.08, 0.98), 10, 8) # 眼（半嵌进面团）
		_limb(head, Vector3(sx * 1.05, 0.95, -0.1), Vector3(sx * 1.58, 1.62, -0.28), 0.17, 0.11, bone, 8) # 角·根
		_limb(head, Vector3(sx * 1.58, 1.62, -0.28), Vector3(sx * 1.52, 2.28, -0.02), 0.11, 0.015, bone, 8) # 角·梢
		var fin := Util.box(head, Vector3(0.12, 0.72, 0.52), stone_dk, Vector3(sx * 1.4, 0.05, -0.05))
		fin.rotation.z = sx * 0.5
		Util.cyl(head, 0.02, 0.075, 0.4, bone, Vector3(sx * 0.36, -0.22, 1.55), 6).rotation.x = PI # 上獠牙（贴在发光口腔前，尖朝下）
	_sphs(head, 0.78, stone_dk, Vector3(0, -0.55, 0.82), Vector3(1, 0.72, 0.55), 14, 10) # 口腔凹座
	var mouth := Util.sph(head, 0.62, _glow(Color(1, 0.4, 0.05), 3.0), Vector3(0, -0.55, 1.15), 14, 11)
	var mouth_p := _add_part("mouth", 1020, mouth, 0.85, true) # 对标估算 30 发（调平表 §5）
	mouth_p.vulnerable = false
	_anim_nodes["mouth_part"] = mouth_p
	# 下颌（独立子节点，update 按基准 y 开合）：颌体 + 下巴 + 上翘下獠牙
	var jaw := Node3D.new()
	jaw.position = Vector3(0, -1.25, 0.3)
	head.add_child(jaw)
	Util.box(jaw, Vector3(1.9, 0.5, 1.7), stone, Vector3(0, -0.18, 0.25))
	_sphs(jaw, 0.6, stone, Vector3(0, -0.3, 0.78), Vector3(1.1, 0.6, 1), 12, 9)
	for sx in [-1.0, 1.0]:
		Util.cyl(jaw, 0.07, 0.015, 0.36, bone, Vector3(sx * 0.3, 0.14, 0.95), 6) # 下獠牙（尖朝上）
	_anim_nodes["jaw"] = jaw
	_anim_nodes["head"] = head

func _build_godomuga() -> void:
	# 分幻鬼（第 4 关）：幽门框 + 核心环座 + 四只面具幽鬼（半透飘体）
	# 锚点不变：phantoms 必须 MeshInstance3D@_group（update 逐帧覆写 position）；core 球 (0,3.4,1.0) r1.1
	var frame := _pbr(Color(0.46, 0.38, 0.62), 0.55, 0.5, "metal")
	var frame_dk := _pbr(Color(0.26, 0.2, 0.38), 0.65, 0.4, "metal")
	Util.box(_group, Vector3(9.4, 0.7, 2.4), frame_dk, Vector3(0, 0.35, -0.2))
	for sx in [-3.7, 3.7]:
		Util.box(_group, Vector3(1.1, 6.6, 1.1), frame, Vector3(sx, 3.95, -0.3))
		Util.box(_group, Vector3(1.5, 0.5, 1.5), frame_dk, Vector3(sx, 7.45, -0.3))
		Util.box(_group, Vector3(0.14, 5.2, 0.1), _glow(Color(0.62, 0.38, 1), 1.5), Vector3(sx * 0.835, 3.9, 0.28))
	Util.box(_group, Vector3(8.6, 1.0, 1.2), frame, Vector3(0, 6.9, -0.3))
	Util.box(_group, Vector3(8.0, 0.16, 0.1), _glow(Color(0.62, 0.38, 1), 1.6), Vector3(0, 6.32, 0.32))
	# 核心环座：背盘 + 双环（核心在环心显形）
	var disc := Util.cyl(_group, 1.08, 1.08, 0.24, frame_dk, Vector3(0, 3.4, 0.28), 24)
	disc.rotation.x = PI / 2.0
	_torus(_group, 1.28, 0.13, frame, Vector3(0, 3.4, 0.5))
	_torus(_group, 1.02, 0.06, _glow(Color(0.62, 0.38, 1), 1.4), Vector3(0, 3.4, 0.62))
	# 幽鬼：半透魂体球 + 苍白面具 + 品红眼 + 垂尾（子件随幻影节点一起绕轨/对齐）
	var ghost_m := Util.glow(Color(0.62, 0.38, 1), 1.15, 0.5)
	_mats.append(ghost_m)
	var mask_m := _pbr(Color(0.9, 0.88, 0.94), 0.55, 0.05)
	var phantoms: Array = []
	for i in 4:
		var ph := Util.sph(_group, 0.72, ghost_m, Vector3.ZERO, 16, 12)
		ph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sphs(ph, 0.4, mask_m, Vector3(0, 0.14, 0.4), Vector3(0.82, 1.05, 0.55), 14, 11)
		Util.sph(ph, 0.055, _glow(Color(1, 0.35, 0.9), 2.4), Vector3(-0.15, 0.22, 0.66), 8, 6)
		Util.sph(ph, 0.055, _glow(Color(1, 0.35, 0.9), 2.4), Vector3(0.15, 0.22, 0.66), 8, 6)
		Util.box(ph, Vector3(0.15, 0.04, 0.03), frame_dk, Vector3(0, -0.14, 0.64))
		var tail := Util.cyl(ph, 0.46, 0.02, 1.2, ghost_m, Vector3(0, -0.78, 0), 12)
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		phantoms.append(ph)
	_anim_nodes["phantoms"] = phantoms
	var core := Util.sph(_group, 0.95, _glow(Color(1, 0.8, 0.2), 3.2), Vector3(0, 3.4, 1.0), 18, 14)
	core.visible = false
	var core_p := _add_part("core", 780, core, 1.1, true)
	core_p.vulnerable = false
	core_p.targetable = false
	_anim_nodes["core"] = core
	_anim_nodes["core_part"] = core_p

func _build_guldaf() -> void:
	# 反重力飞碟（第 5 关）：透镜形碟身 + 顶舱罩 + 环边航行灯 + 腹部核心与孢子舱
	# 锚点不变：ship (0,6.4,0) 自转/浮动；pod (±2.2,-0.75,0)@ship r0.8；core (0,-1.1,0)@ship r1.15
	var ship := Node3D.new()
	ship.position = Vector3(0, 6.4, 0)
	_group.add_child(ship)
	_anim_nodes["ship"] = ship
	var hull := _pbr(Color(0.88, 0.93, 1.02), 0.42, 0.55, "metal")
	var hull_dk := _pbr(Color(0.62, 0.68, 0.78), 0.48, 0.65, "metal")
	_sphs(ship, 3.9, hull, Vector3.ZERO, Vector3(1, 0.3, 1), 28, 18) # 碟身：压扁球=透镜剖面
	_sphs(ship, 2.3, hull_dk, Vector3(0, -0.72, 0), Vector3(1, 0.5, 1), 22, 14) # 腹舱
	_torus(ship, 3.62, 0.17, hull_dk, Vector3(0, -0.12, 0), 36, false) # 碟边环（平放）
	_torus(ship, 1.32, 0.14, hull_dk, Vector3(0, 0.62, 0), 24, false) # 舱罩颈圈
	_sphs(ship, 1.22, _pbr(Color(0.95, 1.0, 1.08), 0.25, 0.9, "metal"), Vector3(0, 0.98, 0), Vector3(1, 0.78, 1), 20, 14) # 顶舱罩
	Util.cyl(ship, 0.035, 0.05, 0.75, hull_dk, Vector3(0, 2.0, 0), 6)
	Util.sph(ship, 0.1, _glow(Color(1, 0.2, 0.15), 2.6), Vector3(0, 2.42, 0), 8, 6) # 顶部信标
	for i in 8:
		var a := float(i) / 8.0 * TAU
		Util.sph(ship, 0.15, _glow(Color(0.3, 0.9, 1), 2.2), Vector3(cos(a) * 3.68, -0.22, sin(a) * 3.68), 8, 6) # 环边航行灯
	for px in [-2.2, 2.2]:
		var pod := Node3D.new()
		pod.position = Vector3(px, -0.75, 0)
		ship.add_child(pod)
		Util.capsule(pod, 0.42, 1.05, hull_dk, Vector3.ZERO) # 孢子舱
		Util.sph(pod, 0.15, _glow(Color(0.45, 1, 0.55), 2.2), Vector3(0, -0.5, 0), 8, 6)
		_torus(pod, 0.4, 0.07, hull, Vector3(0, 0.3, 0), 16, false)
		_add_part("pod", 200, pod, 0.8)
	_torus(ship, 1.06, 0.17, hull_dk, Vector3(0, -1.02, 0), 24, false) # 腹部核心环框（平放朝下）
	var core := Util.sph(ship, 0.95, _glow(Color(1, 0.2, 0.2), 3.2), Vector3(0, -1.1, 0), 18, 14)
	_add_part("core", 820, core, 1.15, true)

func _build_gordea() -> void:
	# 格鲁蒂亚巨装甲兵（第 6 关）：人形巨型机器人——装甲腿/裙甲/分层胸甲/头盔颅/肩甲/机械臂/胸前圆盘发射器
	# 锚点不变：head 网格 (0,5.95,0)@body（"body" 部件 r3.1 以头为锚覆盖全身）；gem 球 (0,4.1,0.82)@body r0.62
	# 圆盘从 (±1.6,5.6,0.8) 发射——发射器正对该位置装在胸甲前角
	var armor := _pbr(Color(0.66, 0.48, 0.32), 0.52, 0.62, "rust")
	var dark := _pbr(Color(0.26, 0.24, 0.24), 0.58, 0.6, "metal")
	var brass := _pbr(Color(0.62, 0.47, 0.2), 0.38, 0.85)
	var body := Node3D.new()
	_group.add_child(body)
	_anim_nodes["body"] = body
	# 双腿：大腿/膝盘/小腿装甲 + 重靴
	for sx in [-1.0, 1.0]:
		_limb(body, Vector3(sx * 0.85, 3.6, 0), Vector3(sx * 0.95, 2.2, 0.1), 0.52, 0.46, armor, 12)
		var knee := Util.cyl(body, 0.52, 0.52, 0.3, dark, Vector3(sx * 0.97, 2.05, 0.18), 14)
		knee.rotation.z = PI / 2.0
		_limb(body, Vector3(sx * 0.95, 1.9, 0.1), Vector3(sx * 1.0, 0.78, 0.05), 0.44, 0.37, armor, 12)
		Util.box(body, Vector3(1.05, 0.5, 1.7), dark, Vector3(sx * 1.0, 0.28, 0.28))
		Util.box(body, Vector3(1.1, 0.22, 0.5), brass, Vector3(sx * 1.0, 0.16, 1.05))
	# 骨盆 + 裙甲
	Util.box(body, Vector3(2.3, 0.9, 1.3), dark, Vector3(0, 3.9, 0))
	Util.box(body, Vector3(1.15, 1.05, 0.14), armor, Vector3(0, 3.2, 0.68)).rotation.x = 0.25
	for sx in [-1.0, 1.0]:
		Util.box(body, Vector3(0.14, 1.05, 1.15), armor, Vector3(sx * 1.22, 3.25, 0)).rotation.z = -sx * 0.22
	# 腰 + 分层胸甲 + 前甲板 + 肩线饰带
	Util.box(body, Vector3(2.2, 0.95, 1.25), dark, Vector3(0, 4.55, 0))
	Util.box(body, Vector3(2.7, 1.3, 1.45), armor, Vector3(0, 5.2, 0))
	Util.box(body, Vector3(2.2, 1.0, 0.14), dark, Vector3(0, 5.3, 0.76))
	Util.box(body, Vector3(2.9, 0.3, 1.55), brass, Vector3(0, 5.7, 0))
	# 胸前圆盘发射器（对位圆盘发射点 ±1.6,5.6,0.8）
	for sx in [-1.0, 1.0]:
		var lun := Util.cyl(body, 0.52, 0.52, 0.2, dark, Vector3(sx * 1.45, 5.55, 0.72), 18)
		lun.rotation.x = PI / 2.0
		_torus(body, 0.38, 0.06, _glow(Color(1, 0.6, 0.15), 1.8), Vector3(sx * 1.45, 5.55, 0.84))
	# 宝石座（gem 锚点在腰甲正面）
	_torus(body, 0.56, 0.1, brass, Vector3(0, 4.1, 0.76))
	Util.box(body, Vector3(1.5, 0.3, 0.3), dark, Vector3(0, 4.72, 0.66))
	var gem := Util.sph(body, 0.42, _glow(Color(1, 0.85, 0.2), 3.2), Vector3(0, 4.1, 0.82), 14, 11)
	# 头盔颅（head 锚点不动）：颅球 + 面甲 + 双眼 + 中央刃角 + 侧舱；颈座压在胸甲上沿
	Util.cyl(body, 0.42, 0.5, 0.5, dark, Vector3(0, 5.62, 0), 12)
	var head := _sphs(body, 0.8, armor, Vector3(0, 5.95, 0), Vector3(0.95, 1.0, 1.0), 18, 14)
	Util.box(head, Vector3(0.95, 0.58, 0.3), dark, Vector3(0, -0.14, 0.6))
	Util.sph(head, 0.09, _glow(Color(1, 0.2, 0.15), 2.8), Vector3(-0.24, 0.06, 0.8), 8, 6)
	Util.sph(head, 0.09, _glow(Color(1, 0.2, 0.15), 2.8), Vector3(0.24, 0.06, 0.8), 8, 6)
	_limb(head, Vector3(0, 0.52, 0.08), Vector3(0, 1.28, -0.28), 0.15, 0.02, brass, 8)
	Util.box(head, Vector3(0.3, 0.5, 0.62), dark, Vector3(-0.8, -0.05, 0))
	Util.box(head, Vector3(0.3, 0.5, 0.62), dark, Vector3(0.8, -0.05, 0))
	# 肩甲 + 机械臂 + 拳
	for sx in [-1.0, 1.0]:
		_sphs(body, 0.92, armor, Vector3(sx * 1.95, 5.8, 0), Vector3(1.2, 0.75, 1.1), 16, 12)
		_limb(body, Vector3(sx * 2.15, 5.5, 0), Vector3(sx * 2.5, 4.35, 0.1), 0.45, 0.4, dark, 12)
		Util.sph(body, 0.42, brass, Vector3(sx * 2.5, 4.22, 0.1), 12, 9) # 肘关节
		_limb(body, Vector3(sx * 2.5, 4.1, 0.1), Vector3(sx * 2.3, 3.1, 0.25), 0.48, 0.42, armor, 12)
		_sphs(body, 0.5, dark, Vector3(sx * 2.28, 2.72, 0.3), Vector3(1, 0.85, 1.1), 12, 9) # 拳
	# 背包 + 排气管
	Util.box(body, Vector3(1.7, 1.9, 0.6), dark, Vector3(0, 5.3, -1.02))
	for sx in [-0.55, 0.55]:
		Util.cyl(body, 0.13, 0.16, 1.15, dark, Vector3(sx, 6.2, -1.05), 10)
	_add_part("body", 1500, head, 3.1) # 身体以头部节点为锚、半径覆盖全身（沿用已调平的判定）
	_add_part("gem", 700, gem, 0.62, true)

func _build_alien_heart() -> void:
	# 天王创魔心 + 龙神加瓦（第 8 关）：异形肉壁 + 巨型心脏（血管/瘤结）+ S 颈龙首 + 两侧护卫肉柱
	# 锚点不变：dragon (-4.6,0,1.2)、dhead (1.5,4.4,0.3)@dragon r1.35（龙首朝 +Z）；heart 球 (1.8,4.3,0.9) r1.8（update 脉动覆写其 scale）
	var flesh := _pbr2(Color(0.52, 0.27, 0.33), 0.72, 0.0, "alien", Vector2(2, 2))
	var flesh_dk := _pbr(Color(0.32, 0.14, 0.21), 0.8, 0.0, "alien")
	var bone := _pbr(Color(0.88, 0.85, 0.76), 0.6, 0.0)
	# 肉壁：背板 + 前凸肉团簇 + 卵囊 + 环形血管纹
	Util.box(_group, Vector3(15.5, 8.6, 1.6), flesh, Vector3(0, 4.3, -1.7))
	_sphs(_group, 2.3, flesh, Vector3(-6.2, 5.6, -0.95), Vector3(1, 1, 0.42), 16, 12)
	_sphs(_group, 1.9, flesh, Vector3(-1.2, 6.6, -0.9), Vector3(1, 1, 0.42), 16, 12)
	_sphs(_group, 2.1, flesh, Vector3(5.9, 6.2, -0.95), Vector3(1, 1, 0.42), 16, 12)
	_sphs(_group, 1.7, flesh, Vector3(-5.4, 1.9, -0.9), Vector3(1, 1, 0.42), 14, 10)
	_sphs(_group, 1.6, flesh, Vector3(4.6, 1.7, -0.9), Vector3(1, 1, 0.42), 14, 10)
	var egg_m := Util.glow(Color(0.78, 0.62, 0.55), 0.35, 0.9)
	_mats.append(egg_m)
	_sphs(_group, 0.82, egg_m, Vector3(-4.3, 3.3, 0.15), Vector3(1, 1.15, 1), 12, 9) # 卵囊
	_sphs(_group, 0.68, egg_m, Vector3(4.9, 3.6, 0.15), Vector3(1, 1.15, 1), 12, 9)
	# 两侧护卫肉柱：肉团叠柱 + 发光荚
	for sx in [-7.6, 7.6]:
		_limb(_group, Vector3(sx, 0.5, 0.25), Vector3(sx, 5.3, 0.25), 0.58, 0.5, flesh_dk, 12) # 柱芯
		_sphs(_group, 1.15, flesh_dk, Vector3(sx, 1.1, 0.3), Vector3(1, 1, 0.8), 14, 10)
		_sphs(_group, 1.0, flesh, Vector3(sx, 2.9, 0.3), Vector3(1, 1, 0.8), 14, 10)
		_sphs(_group, 0.85, flesh_dk, Vector3(sx, 4.6, 0.3), Vector3(1, 1, 0.8), 12, 9)
		Util.sph(_group, 0.4, _glow(Color(0.5, 1, 0.4), 2.0), Vector3(sx, 3.4, 1.05), 10, 8)
	# 心脏本体：有机材质（异形贴图 + 暗红自发光），瘤结作子节点随脉动一起胀缩
	var hm := StandardMaterial3D.new()
	hm.albedo_texture = load("res://assets/tex/alien_diff.jpg")
	hm.albedo_color = Color(0.9, 0.42, 0.48)
	hm.normal_texture = load("res://assets/tex/alien_nor_gl.jpg")
	hm.normal_enabled = true
	hm.roughness = 0.38
	hm.emission_enabled = true
	hm.emission = Color(0.55, 0.07, 0.11)
	hm.emission_energy_multiplier = 0.55
	_mats.append(hm)
	var heart := Util.sph(_group, 1.55, hm, Vector3(1.8, 4.3, 0.9), 22, 18)
	heart.scale = Vector3(1, 1.18, 1)
	_sphs(heart, 0.34, hm, Vector3(0.7, 0.5, 1.0), Vector3(1, 1, 1), 10, 8)
	_sphs(heart, 0.28, hm, Vector3(-0.85, 0.78, 0.72), Vector3(1, 1, 1), 10, 8)
	_sphs(heart, 0.3, hm, Vector3(0.12, -0.95, 1.02), Vector3(1, 1, 1), 10, 8)
	var heart_p := _add_part("heart", 4500, heart, 1.8, true) # 1.2.0：1870→4500 大幅加难（用户「太太太简单了」；可通关实证见 boss120 探针）
	heart_p.vulnerable = false
	_anim_nodes["heart"] = heart
	_anim_nodes["heart_part"] = heart_p
	# 大血管：主动脉弧管爬向左上 + 右支血管 + 根部触须（兄弟节点，不随脉动）
	var aorta := _pbr(Color(0.44, 0.15, 0.21), 0.5, 0.0, "alien")
	_limb(_group, Vector3(1.6, 5.75, 0.75), Vector3(0.2, 6.9, 0.35), 0.36, 0.3, aorta, 12)
	_limb(_group, Vector3(0.2, 6.9, 0.35), Vector3(-1.6, 7.5, -0.1), 0.3, 0.24, aorta, 12)
	_limb(_group, Vector3(3.05, 5.15, 0.75), Vector3(4.6, 6.1, 0.2), 0.22, 0.17, aorta, 10)
	_limb(_group, Vector3(1.15, 3.05, 0.8), Vector3(0.55, 0.6, 1.7), 0.17, 0.1, aorta, 10)
	_limb(_group, Vector3(2.55, 2.95, 0.8), Vector3(3.1, 0.5, 1.9), 0.17, 0.1, aorta, 10)
	_limb(_group, Vector3(0.7, 5.5, 0.15), Vector3(-2.4, 6.9, -0.15), 0.2, 0.13, aorta, 10) # 贴墙血管
	_limb(_group, Vector3(3.2, 5.8, 0.15), Vector3(5.4, 7.1, -0.15), 0.18, 0.12, aorta, 10)
	# 龙神加瓦：肉丘基座 + 三段 S 形颈 + 背刺 + 龙首（颅/吻/颌/牙/角/眼/颈鳍，朝 +Z）
	var dragon := Node3D.new()
	dragon.position = Vector3(-4.6, 0, 1.2)
	_group.add_child(dragon)
	_anim_nodes["dragon"] = dragon
	var dmat := _pbr2(Color(0.36, 0.48, 0.31), 0.68, 0.0, "alien", Vector2(1, 1))
	_sphs(dragon, 1.5, flesh_dk, Vector3(0, 0.45, 0), Vector3(1.15, 0.65, 1.15), 14, 10)
	_limb(dragon, Vector3(0, 0.8, 0), Vector3(0.5, 2.3, 0.15), 0.62, 0.52, dmat, 12)
	_limb(dragon, Vector3(0.5, 2.3, 0.15), Vector3(1.05, 3.45, 0.25), 0.52, 0.44, dmat, 12)
	_limb(dragon, Vector3(1.05, 3.45, 0.25), Vector3(1.5, 4.2, 0.3), 0.44, 0.4, dmat, 12)
	for sp in [Vector3(0.28, 1.95, -0.42), Vector3(0.72, 3.0, -0.36), Vector3(1.18, 3.92, -0.28)]:
		Util.cyl(dragon, 0.015, 0.11, 0.52, bone, sp, 6).rotation.x = -0.5 # 背刺
	var dhead := Node3D.new()
	dhead.position = Vector3(1.5, 4.4, 0.3)
	dragon.add_child(dhead)
	_sphs(dhead, 0.85, dmat, Vector3(0, 0.1, 0.25), Vector3(0.72, 0.8, 1.25), 18, 14) # 颅（长轴朝 +Z）
	Util.box(dhead, Vector3(0.62, 0.42, 0.85), dmat, Vector3(0, -0.08, 1.05)) # 吻
	Util.box(dhead, Vector3(0.55, 0.18, 0.8), dmat, Vector3(0, -0.44, 1.0)) # 下颌
	Util.cyl(dhead, 0.01, 0.09, 0.44, bone, Vector3(0, 0.3, 1.38), 6).rotation.x = 1.05 # 鼻角
	for tz in [0.78, 1.05, 1.32]:
		for tx in [-0.17, 0.17]:
			Util.cyl(dhead, 0.045, 0.008, 0.22, bone, Vector3(tx, -0.34, tz), 5).rotation.x = PI # 上牙
	for tz in [0.95, 1.25]:
		for tx in [-0.14, 0.14]:
			Util.cyl(dhead, 0.04, 0.008, 0.18, bone, Vector3(tx, -0.26, tz), 5) # 下牙
	Util.sph(dhead, 0.11, _glow(Color(0.75, 1, 0.3), 2.6), Vector3(0.52, 0.34, 0.62), 8, 6) # 眼
	Util.sph(dhead, 0.11, _glow(Color(0.75, 1, 0.3), 2.6), Vector3(-0.52, 0.34, 0.62), 8, 6)
	for sx in [-1.0, 1.0]:
		_limb(dhead, Vector3(sx * 0.38, 0.55, -0.3), Vector3(sx * 0.55, 0.98, -1.08), 0.12, 0.015, bone, 8) # 后扫角
	var frill := Util.box(dhead, Vector3(1.35, 0.95, 0.1), flesh_dk, Vector3(0, 0.12, -0.58))
	frill.rotation.x = -0.3
	var dragon_p := _add_part("dragon", 1870, dhead, 1.35) # 对标原版公式 55 发（调平表 §5）
	_anim_nodes["dragon_part"] = dragon_p

# ---------------- 受击/击败 ----------------
func _part_hit(part: Part, dmg: int, point: Vector3 = Vector3.ZERO) -> void:
	if not alive or not part.alive:
		return
	if not part.vulnerable:
		# 无敌部位也要有反馈：蓝灰火花表示「打不动」，别让玩家以为没命中
		if point != Vector3.ZERO:
			_ctx["projectiles"].spawn_explosion_fx(point, 0.8, Color(0.5, 0.65, 1.0))
		return
	if point != Vector3.ZERO:
		_ctx["projectiles"].spawn_explosion_fx(point, 0.9, Color(1.0, 0.75, 0.3))
	part.hp -= dmg
	_total_hp -= dmg
	if part.hp <= 0:
		part.hp = 0
		part.alive = false
		part.targetable = false
		if part.node and is_instance_valid(part.node):
			part.node.visible = false
			_ctx["projectiles"].spawn_explosion_fx(part.node.global_position, 2.4)
		_on_part_destroyed(part)
		if part.is_core:
			_defeat()

func _on_part_destroyed(part: Part) -> void:
	match boss_id:
		"defenseWall", "finalGate":
			var left := 0
			for p in targets:
				if p.part_name == "turret" and p.alive:
					left += 1
			if left == 0:
				for p in targets:
					if p.is_core:
						p.vulnerable = true
				var cb: Callable = _ctx.get("on_core_exposed", Callable())
				if cb.is_valid():
					cb.call()
		"alienHeart":
			if part.part_name == "dragon":
				_anim_nodes["heart_part"].vulnerable = true

func _defeat() -> void:
	if not alive:
		return
	alive = false
	_ctx["projectiles"].spawn_explosion_fx(global_position + Vector3(0, 3, 0), 5.0)
	_ctx["projectiles"].spawn_explosion_fx(global_position + Vector3(2, 1.5, 1), 3.5)
	_ctx["on_score"].call(int(Data.BOSSES[boss_id]["score"]))
	_group.visible = false
	_ctx["on_defeated"].call()

# ---------------- 更新/攻击 ----------------
func update_boss(dt: float, player) -> void:
	if not alive:
		return
	_t += dt
	_sync_part_positions()
	match boss_id:
		"defenseWall", "finalGate":
			var core: MeshInstance3D = _anim_nodes.get("core")
			if core:
				var cp: Part = null
				for p in targets:
					if p.is_core:
						cp = p
				var exposed := cp != null and cp.vulnerable
				core.scale = Vector3.ONE * (1.0 + sin(_t * (5.5 if exposed else 2.0)) * (0.13 if exposed else 0.05))
			if player:
				for p in targets:
					if p.part_name == "turret" and p.alive and p.node:
						var d: Vector3 = player.global_position - p.node.global_position
						p.node.rotation.y = atan2(d.x, d.z)
		"guldaf":
			var ship: Node3D = _anim_nodes["ship"]
			ship.position.y = 6.4 + sin(_t * 1.3) * 0.5
			ship.rotation.y = _t * 0.4
		"gromaides":
			var cyc := fmod(_t, 4.6)
			var open := cyc > 2.6 and cyc < 4.4
			_anim_nodes["mouth_part"].vulnerable = open
			_anim_nodes["jaw"].position.y = -1.25 - (0.4 if open else 0.0)
		"baseCore":
			var cyc := fmod(_t, 3.4)
			var open := cyc < 2.1
			_anim_nodes["eye_part"].vulnerable = open
			_anim_nodes["eye"].scale = Vector3.ONE * (1.0 if open else 0.45)
		"godomuga":
			var phantoms: Array = _anim_nodes["phantoms"]
			var cyc := fmod(_t, 6.8)
			var aligned := cyc > 5.0
			for i in phantoms.size():
				var ph: MeshInstance3D = phantoms[i]
				if aligned:
					ph.position = Vector3(0, 3.4, 0.6)
				else:
					var a := _t * 1.6 + float(i) * TAU / 4.0
					ph.position = Vector3(cos(a) * 2.6, 3.4 + sin(_t * 2.0 + i) * 0.5, 0.6 + sin(a) * 0.5)
			_anim_nodes["core"].visible = aligned
			_anim_nodes["core_part"].vulnerable = aligned
			_anim_nodes["core_part"].targetable = aligned
		"alienHeart":
			var heart: MeshInstance3D = _anim_nodes["heart"]
			var pulse := 1.0 + sin(_t * 5.0) * 0.09
			heart.scale = Vector3(pulse, 1.18 * pulse, pulse)
			var dragon: Node3D = _anim_nodes["dragon"]
			dragon.rotation.y = sin(_t * 0.7) * 0.4
		"gordea":
			var body: Node3D = _anim_nodes["body"]
			body.position.y = absf(sin(_t * 1.8)) * 0.18
	if not activated or player == null or not player.alive:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > 65.0:
		return
	_fire_timer -= dt
	_special_timer -= dt
	match boss_id:
		"defenseWall", "finalGate":
			if _fire_timer <= 0.0:
				_fire_timer = 1.5
				for p in targets:
					if p.part_name == "turret" and p.alive:
						var fwd := Vector3(sin(p.node.rotation.y), 0, cos(p.node.rotation.y))
						_orb_at(p.node.global_position + fwd * 1.6 + Vector3(0, 0.45, 0), player, 17.0, 0.3)
		"baseCore":
			if _fire_timer <= 0.0:
				_fire_timer = 1.9
				_orb_at(_anim_nodes["eye"].global_position, player, 18.0, 0.15)
				for p in targets:
					if p.part_name == "pod" and p.alive:
						_orb_at(p.node.global_position, player, 16.0, 0.5)
		"gromaides":
			if _fire_timer <= 0.0:
				_fire_timer = 2.6
				var from: Vector3 = _anim_nodes["head"].global_position + Vector3(0, -0.5, 1.2)
				_grenade_at(from, player)
			if _special_timer <= 0.0:
				_special_timer = 7.0
				_ctx["spawn_minion"].call("spore", global_position.x + randf_range(-4, 4), global_position.z + 9.0)
		"godomuga":
			if _fire_timer <= 0.0:
				_fire_timer = 1.6
				for i in [-1, 0, 1]:
					_orb_at(global_position + Vector3(i * 1.4, 3.4, 1.2), player, 17.0, 0.1, i * 0.14)
		"guldaf":
			if _fire_timer <= 0.0:
				_fire_timer = 2.1
				_orb_at(global_position + Vector3(0, 5.4, 0), player, 18.0, 0.3)
			if _special_timer <= 0.0:
				_special_timer = 6.0
				_ctx["spawn_minion"].call("spore", global_position.x + randf_range(-5, 5), global_position.z + randf_range(4, 9))
		"gordea":
			if _fire_timer <= 0.0:
				_fire_timer = 2.3
				for i in [-1, 0, 1]:
					var from := global_position + Vector3(i * 1.6, 5.6, 0.8)
					var dir: Vector3 = (player.global_position + Vector3(0, 1.0, 0) - from).normalized()
					var right := Vector3(-dir.z, 0, dir.x)
					_ctx["projectiles"].spawn_disc(from, (dir + right * i * 0.1).normalized(), 15.0)
				AudioSys.play("enemy_shoot", -6.0)
			if _special_timer <= 0.0:
				_special_timer = 9.0
				# 跳砸：玩家在近处且在地面则受伤 + 冲击特效
				_ctx["projectiles"].spawn_explosion_fx(global_position + Vector3(0, 0.4, 3.5), 3.4, Color(0.8, 0.65, 0.4))
				if player.grounded and global_position.distance_to(player.global_position) < 7.5:
					player.take_damage(1)
		"alienHeart":
			var dragon_alive: bool = _anim_nodes["dragon_part"].alive
			if _fire_timer <= 0.0:
				_fire_timer = 1.35 if dragon_alive else 0.85 # 1.2.0：本体开火频率 +~30%（原 1.7/1.1）
				_orb_at(global_position + Vector3(-3.1, 4.6, 1.5), player, 18.0, 0.25)
				if not dragon_alive:
					_orb_at(_anim_nodes["heart"].global_position, player, 19.0, 0.2)
			if _special_timer <= 0.0:
				_special_timer = 8.0
				_ctx["spawn_minion"].call("spore", global_position.x + randf_range(-5, 5), global_position.z + 8.0)
			# 1.2.0 增援波：每 12 秒随机杂兵从竞技场边缘涌入（存活上限 6，见 _spawn_reinforcements）
			_reinf_timer -= dt
			if _reinf_timer <= 0.0:
				_reinf_timer = 12.0
				_spawn_reinforcements(player)

## 最终 Boss 增援（1.2.0）：随机杂兵从竞技场两侧边缘多点涌入——持续压力，但存活上限封顶不淹人
const REINF_TYPES := ["rifleman", "runner", "shield", "bomber"]
const REINF_CAP := 6

func _spawn_reinforcements(player) -> void:
	for i in range(_reinforcements.size() - 1, -1, -1):
		var e = _reinforcements[i]
		if not is_instance_valid(e) or not e.alive:
			_reinforcements.remove_at(i)
	var room := REINF_CAP - _reinforcements.size()
	if room <= 0:
		return
	var n := mini(randi_range(2, 3), room)
	for k in n:
		var side := 1.0 if randf() > 0.5 else -1.0
		var x := global_position.x + side * randf_range(18.0, 38.0)
		var z := global_position.z + randf_range(9.0, 24.0)
		if player != null and Vector2(x - player.global_position.x, z - player.global_position.z).length() < 10.0:
			x = global_position.x - side * randf_range(18.0, 38.0) # 刷点离玩家太近就换另一侧
		var e2 = _ctx["spawn_minion"].call(REINF_TYPES[randi() % REINF_TYPES.size()], x, z)
		if e2 != null:
			_reinforcements.append(e2)

func _orb_at(from: Vector3, player, speed: float, inacc: float, spread_x: float = 0.0) -> void:
	var target := Vector3(
		player.global_position.x + randf_range(-inacc, inacc) * 2.0,
		player.chest_y(),
		player.global_position.z + randf_range(-inacc, inacc) * 2.0)
	var dir: Vector3 = (target - from).normalized()
	if spread_x != 0.0:
		var right := Vector3(-dir.z, 0, dir.x)
		dir = (dir + right * spread_x).normalized()
	_ctx["projectiles"].spawn_orb(from, dir, speed, 1, 1.7) # Boss 重弹：命中播爆炸视觉（纯表现，判定不动）
	AudioSys.play("enemy_shoot", -9.0)

func _grenade_at(from: Vector3, player) -> void:
	var t := 1.3
	var g := 16.0
	var vel := Vector3(
		(player.global_position.x - from.x) / t,
		((player.global_position.y + 0.3 - from.y) + 0.5 * g * t * t) / t,
		(player.global_position.z - from.z) / t)
	_ctx["projectiles"].spawn_grenade(from, vel)

func destroy_boss() -> void:
	queue_free()
