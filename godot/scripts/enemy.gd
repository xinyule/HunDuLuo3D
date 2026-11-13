class_name Enemy
extends Node3D

## 敌人 —— 原作名册岗位制 AI，全类型发射实体弹丸
## 人型兵（Ledder/Greeder/狙击/榴弹/Garth/Langel/Akbar）用骨骼士兵模型按兵种染色；
## 炮台/自走弹/把妖虫/石像/扫讨车为机械或异形建模。
## 可击接口（与 Boss 部件/感应器/飞鹰统一）：hit_x/hit_y/hit_z/hit_r/alive/targetable/on_hit

var type := ""
var hp := 1
var max_hp := 1
var alive := true
var targetable := true
var hit_x := 0.0
var hit_y := 1.0
var hit_z := 0.0
var hit_r := 0.8
var score_value := 0

var _ctx: Dictionary
var _data: Dictionary
var _death_t := 0.0
var _death_clip := false
var _death_len := 0.85
var _t := 0.0
var _fire_timer := 1.0
var _alert := false # 交战状态：看见/贴近/挨打才激活（开放版全量预置敌人的行为门）
var _los_t := 0.0 # 视线复核计时（错峰降频）
var _los_ok := false
var _dormant := 0.0 # 远处降频步进累积
var _aim_mod_e: AimModifier = null # 射手上身俯仰（骨骼后处理，与主角同套）
var _home := Vector3.ZERO # 出生点（营地中心）：未交战时在周围巡逻
var _patrol_t := 0.0
var _patrol_dest := Vector3.ZERO
var _patrol_moving := false
var _alert_icon: Label3D = null # 发现玩家瞬间的「！」
var _alert_t := 0.0
var _was_alert := false
var _burst_left := 0
var _melee_timer := 0.0
var _facing := PI
var _flash_t := 0.0
var _stance_clip := "" # 站姿/常态片段（受击/射击反应播完后回到它）
var _react_t := 0.0 # 反应片段剩余时间
var _scored := false
var _base_x := 0.0
var _base_y := 0.0
var _mats: Array = []
var _flash_mats: Array = []
var _model: Node3D
var _anim: AnimationPlayer
var _head: Node3D
var _roller_ball: MeshInstance3D
var _hp_bar: Node3D
var _hp_fill: MeshInstance3D
var _hp_w := 1.15
var _ak_phase := 0 # 0潜伏 1升起 2射击 3下沉
var _ak_timer := 0.0
var _ak_shots := 0

const HUMANOID := ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar", "bomber", "shield"]
const TINTS := {
	# 整体提饱和提亮与环境（丛林绿褐/基地灰）拉开距离——用户实测「NPC 糊在背景里看不清」（2026-11-12 三修）
	"rifleman": Color(0.56, 0.62, 0.24), "runner": Color(0.88, 0.18, 0.1),
	"sniper": Color(0.52, 0.4, 0.75), "mortar": Color(0.72, 0.5, 0.26),
	"garth": Color(0.34, 0.37, 0.46), "langel": Color(0.45, 0.58, 0.8),
	"akbar": Color(0.3, 0.55, 0.6),
	"bomber": Color(0.42, 0.44, 0.4), "shield": Color(0.5, 0.52, 0.55),
}

## 新兵种数值兜底（4A 线）：Data.ENEMIES 的正式条目在 data.gd（合并阶段抄入，值须与此严格一致）；
## setup 先查 Data.ENEMIES、缺失才用这里，保证合并前后行为不变。
const FALLBACK_DATA := {
	"bomber": {"hp": 30, "speed": 0.0, "radius": 0.55, "score": 200, "fire_interval": 2.9, "orb_speed": 0.0, "range": 36.0},
	"shield": {"hp": 30, "speed": 2.2, "radius": 0.55, "score": 250, "fire_interval": 3.0, "orb_speed": 17.0, "range": 40.0},
}

func setup(p_type: String, pos: Vector3, ctx: Dictionary, soldier_scenes: Dictionary) -> void:
	type = p_type
	_ctx = ctx
	_data = Data.ENEMIES.get(type, {})
	if _data.is_empty():
		_data = FALLBACK_DATA.get(type, {})
	hp = int(_data["hp"])
	max_hp = hp
	score_value = int(_data["score"])
	global_position = pos
	_home = pos
	_base_x = pos.x
	_base_y = pos.y
	_t = randf() * 10.0
	_fire_timer = randf_range(0.5, 1.4)
	hit_x = pos.x
	hit_z = pos.z
	hit_y = pos.y + 1.0
	hit_r = float(_data["radius"]) + 0.3
	if type == "tank":
		hit_y = pos.y + 1.7
		hit_r = 2.1
	elif type == "turret":
		hit_y = pos.y + 0.9
		hit_r = 1.0
	elif type == "statue":
		hit_y = pos.y + 1.6
		hit_r = 1.05
	_build(soldier_scenes)
	_build_hp_bar()

func _reg_mat(m: Material) -> Material:
	_mats.append(m)
	return m

func _pbr(c: Color, rough: float = 0.8, metal: float = 0.0, tex: String = "") -> Material:
	var m := Util.pbr(c, tex, rough, metal)
	_mats.append(m)
	_flash_mats.append(m)
	return m

func _build(soldier_scenes: Dictionary) -> void:
	if HUMANOID.has(type) and soldier_scenes.has(type):
		_build_soldier(soldier_scenes[type])
		return
	match type:
		"turret": _build_turret()
		"roller": _build_roller()
		"spore": _build_spore()
		"statue": _build_statue()
		"tank": _build_tank()
		_: _build_fallback_soldier()

func _build_soldier(soldier_scene: PackedScene) -> void:
	_model = soldier_scene.instantiate() as Node3D
	add_child(_model)
	if type == "garth":
		_model.scale = Vector3.ONE * 1.08
	# Mixamo 集成：兵种区分 = 各自独立 GLB（旧 Gear 装备件/贴图染色系统已废弃）；
	# 这里只做材质逐实例复制登记，保证受击闪白按实例生效不串扰
	_collect_flash_mats()
	_anim = _find_anim(_model)
	if _anim:
		for n in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Pistol_Idle", "Swim_Idle"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_death_clip = _anim.has_animation("Death01")
		if _death_clip:
			_death_len = _anim.get_animation("Death01").length + 0.3
		match type:
			"runner": _stance_clip = "Jog_Fwd"
			"akbar": _stance_clip = "Swim_Idle"
			"rifleman", "sniper", "garth", "langel", "shield": _stance_clip = "Pistol_Idle"
			_: _stance_clip = "Idle"
		_anim.play(_stance_clip)
	# 枪械（Mixamo 集成定案配枪；迫击炮兵用拼装迫击炮道具；掷弹兵双手掷雷不配枪）
	if type != "mortar" and type != "bomber":
		_attach_gun(_model, type)
	if type == "mortar":
		_build_mortar_prop()
	if type == "shield":
		_build_shield_prop()
	# 警觉标记：发现玩家瞬间头顶冒「！」（先有反应、再开火，不是站桩靶子）
	_alert_icon = Label3D.new()
	_alert_icon.text = "!"
	_alert_icon.font_size = 128
	_alert_icon.modulate = Color(1, 0.55, 0.15)
	_alert_icon.outline_size = 18
	_alert_icon.outline_modulate = Color(0.25, 0.05, 0.0)
	_alert_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_icon.position = Vector3(0, 2.4, 0)
	_alert_icon.visible = false
	add_child(_alert_icon)
	if type in ["rifleman", "garth", "langel", "sniper", "mortar", "shield"]:
		var skel2 := _find_skeleton(_model)
		if skel2:
			_aim_mod_e = AimModifier.new()
			skel2.add_child(_aim_mod_e)
	if type == "akbar":
		_model.position.y = -1.05
		targetable = false

## 材质逐实例复制登记：受击闪白（_flash_mats）与命中表现按实例走，不串扰同场景的其他敌人
func _collect_flash_mats() -> void:
	_collect_mats_recursive(_model)

func _collect_mats_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mesh := mi.mesh
		if mesh:
			for s in mesh.get_surface_count():
				var orig := mi.get_active_material(s)
				if orig is StandardMaterial3D:
					var m := (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(s, m)
					_mats.append(m)
					_flash_mats.append(m)
	for ch in n.get_children():
		_collect_mats_recursive(ch)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for ch in n.get_children():
		var r := _find_anim(ch)
		if r:
			return r
	return null

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for ch in n.get_children():
		var r := _find_skeleton(ch)
		if r:
			return r
	return null

## 敌兵配枪（Mixamo 集成定案）：AK=步枪兵/突击兵、M24=狙击手、低模 M4=其余持枪兵种
## 低模枪（Quaternius）枪身沿 +X、单位偏大：按实测 AABB 居中后绕 Y 转到 +Z、按目标枪长缩放
const GUN_BY_TYPE := {
	"rifleman": "ak", "runner": "ak", "sniper": "m24",
	"garth": "m4_low", "langel": "m4_low", "akbar": "m4_low",
}
const GUN_FIT := { # key -> [x 跨度, AABB 中心, 目标枪长]
	"ak": [5.4937, Vector3(1.0795, 0.0635, 0.0), 0.95],
	"m24": [7.2946, Vector3(0.6055, -0.046, 0.0745), 1.2],
	"m4_low": [5.1688, Vector3(0.825, 0.177, 0.0005), 0.95],
}
static var _gun_scenes: Dictionary = {}

func _attach_gun(model: Node3D, p_type: String) -> void:
	var key: String = GUN_BY_TYPE.get(p_type, "m4_low")
	if not _gun_scenes.has(key):
		_gun_scenes[key] = load("res://assets/weapons/%s.glb" % key)
	var fit: Array = GUN_FIT[key]
	var sc: float = float(fit[2]) / float(fit[0])
	var gun := Node3D.new()
	var rot := Node3D.new()
	rot.rotation.y = -PI / 2.0 # +X 枪身 -> +Z（枪口朝前；方向由实拍复核）
	rot.scale = Vector3.ONE * sc
	gun.add_child(rot)
	var inst: Node3D = (_gun_scenes[key] as PackedScene).instantiate()
	inst.position = -(fit[1] as Vector3)
	rot.add_child(inst)
	var skel := _find_skeleton(model)
	if skel:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i) == "hand_r":
				var ba := BoneAttachment3D.new()
				ba.bone_name = skel.get_bone_name(i)
				skel.add_child(ba)
				ba.add_child(gun)
				gun.scale = Vector3.ONE * Player.attach_scale_comp(skel) # 同 player：反向补偿 GLB 单位缩放
				gun.position = Vector3(0, 0.05, 0.3) # 枪身已按 AABB 居中，前移让握把落在约 1/3 处（枪口朝前）
				gun.rotation.x = -0.35
				return
	model.add_child(gun)
	gun.position = Vector3(0.3, 1.1, 0.3)

## 迫击炮道具（定案拼装，无正品模型）：斜置炮管 + Bipod 双脚架（Quaternius CC0）+ 底板
func _build_mortar_prop() -> void:
	var prop := Node3D.new()
	prop.position = Vector3(0.48, 0, 0.15)
	add_child(prop)
	var metal := _pbr(Color(0.23, 0.24, 0.22), 0.5, 0.6)
	var tube := Util.cyl(prop, 0.085, 0.095, 1.05, metal, Vector3(0, 0.52, 0.02))
	tube.rotation.x = -0.72 # 炮口朝前上方
	var bipod: Node3D = (load("res://assets/weapons/bipod.glb") as PackedScene).instantiate()
	bipod.scale = Vector3.ONE * 0.45 # 原生高 1.33、原点在顶：缩放后腿长约 0.6
	bipod.position = Vector3(0, 0.64, 0.3)
	prop.add_child(bipod)
	Util.box(prop, Vector3(0.56, 0.09, 0.56), metal, Vector3(0, 0.045, -0.2))

## 盾牌兵大盾：背板大一圈当描边 + 主板 + 猩红横带 + 中央铆钉圆头，整体 1.06 宽 × 1.58 高。
## 挂载走躯干骨（spine_02 优先）+ attach_scale_comp 缩放补偿：盾随身体姿态/死亡倒地一起动，
## 不再尸体倒了盾还立着（首轮截图实锤）；骨骼本地 +Y 沿脊柱向上、+Z 朝前（与 AimModifier 的
## spine 俯仰轴约定一致），板面以骨原点（≈胸高 1.05m）为中心。无骨骼时退回模型空间挂载。
func _build_shield_prop() -> void:
	var rim := _pbr(Color(0.52, 0.54, 0.58), 0.38, 0.85)
	var plate := _pbr(Color(0.3, 0.32, 0.36), 0.46, 0.8)
	var holder := Node3D.new()
	var base_y := 1.0 # 模型空间回退时板心高度；骨骼挂载时骨原点即胸高，板心归零
	var skel := _find_skeleton(_model)
	var ba: BoneAttachment3D = null
	if skel:
		for bn in ["spine_02", "spine_01", "spine_03"]:
			ba = _eba(skel, bn)
			if ba:
				break
	if ba:
		ba.add_child(holder)
		holder.scale = Vector3.ONE * Player.attach_scale_comp(skel)
		base_y = 0.0
	else:
		add_child(holder)
	Util.box(holder, Vector3(1.06, 1.58, 0.045), rim, Vector3(0, base_y, 0.435))
	Util.box(holder, Vector3(0.98, 1.5, 0.06), plate, Vector3(0, base_y, 0.465))
	Util.box(holder, Vector3(0.98, 0.17, 0.065), _pbr(Color(0.55, 0.09, 0.07), 0.55, 0.3), Vector3(0, base_y + 0.34, 0.468))
	var boss := Util.sph(holder, 0.13, rim, Vector3(0, base_y + 0.02, 0.5), 12, 9)
	boss.scale = Vector3(1.0, 1.0, 0.55)

## 挂件坐标约定同 player.gd：骨骼本地 +Y 指向子关节，脸朝 +Z（attach_diag.gd 实证）
func _eba(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	if skel == null or skel.find_bone(bone) < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	return ba

## 一次性反应片段（受击/射击）：播完由 update_enemy 拉回站姿
func _react(clip: String, dur: float) -> void:
	if not alive or _anim == null or _react_t > 0.0:
		return
	if _anim.has_animation(clip):
		_anim.play(clip, 0.05)
		_react_t = dur

func _build_fallback_soldier() -> void:
	_model = Node3D.new()
	add_child(_model)
	var tint: Color = TINTS.get(type, Color(0.6, 0.6, 0.55))
	Util.capsule(_model, 0.3, 1.15, _pbr(tint, 0.9), Vector3(0, 1.0, 0))
	Util.sph(_model, 0.17, _pbr(Color(0.79, 0.63, 0.42), 0.6), Vector3(0, 1.72, 0))

func _find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for ch in n.get_children():
		var r := _find_named(ch, nm)
		if r:
			return r
	return null

func _build_turret() -> void:
	# Quaternius Turret Cannon（CC0）：Top 件原点在模型中心，update 直接转它的偏航
	_model = Node3D.new()
	add_child(_model)
	var inst: Node3D = (load("res://assets/vehicles/turret_cannon.glb") as PackedScene).instantiate()
	inst.scale = Vector3.ONE * 1.6
	_model.add_child(inst)
	_head = _find_named(inst, "Turret_Cannon_Top") as Node3D
	if _head == null:
		_head = Node3D.new()
		_head.position.y = 0.95
		_model.add_child(_head)
	_collect_flash_mats()

func _build_roller() -> void:
	_model = Node3D.new()
	add_child(_model)
	_roller_ball = Util.sph(_model, 0.45, _pbr(Color(0.2, 0.2, 0.22), 0.4, 0.8, "metal"), Vector3(0, 0.45, 0), 14, 10)
	Util.sph(_model, 0.12, _reg_mat(Util.glow(Color(1, 0.15, 0.15), 2.5)), Vector3(0, 0.55, 0.38), 8, 6)
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var spike := Util.cyl(_model, 0.01, 0.09, 0.28, _pbr(Color(0.55, 0.55, 0.58), 0.35, 0.9), Vector3(cos(a) * 0.47, 0.45 + sin(a) * 0.47, 0), 6)
		spike.rotation.z = -a + PI / 2.0

func _build_spore() -> void:
	_model = Node3D.new()
	add_child(_model)
	var flesh := _pbr(Color(0.48, 0.16, 0.29), 0.5, 0.0, "alien")
	var body := Util.sph(_model, 0.42, flesh, Vector3(0, 0.55, 0), 12, 9)
	body.scale = Vector3(1, 0.85, 1)
	var eye_m := _reg_mat(Util.glow(Color(1, 1, 0.4), 2.0))
	for ex in [-0.15, 0.15]:
		Util.sph(_model, 0.07, eye_m, Vector3(ex, 0.68, 0.34), 8, 6)
	for i in 4:
		var a := float(i) / 4.0 * TAU + 0.4
		var leg := Util.cyl(_model, 0.045, 0.065, 0.55, _pbr(Color(0.29, 0.06, 0.19), 0.6), Vector3(cos(a) * 0.35, 0.25, sin(a) * 0.35), 6)
		leg.rotation.z = cos(a) * 0.5
		leg.rotation.x = -sin(a) * 0.5

## 石像粗粝化（自实现，不依赖 level.gd）：细分盒网格，顶点按「位置向量噪声」位移——
## 位移只取决于顶点位置，同一位置在不同面上位移一致，棱边不裂；法线按位置焊接平滑。
## 轮廓尺寸/位置与旧盒子完全一致，仅表面起伏 ±0.05，碰撞/hit_r 不受影响。
static var _stone_mesh_cache: Dictionary = {}

func _stone_box(parent: Node, size: Vector3, mat: Material, pos: Vector3, seed: float) -> MeshInstance3D:
	var key := "%s|%s" % [str(size), str(seed)]
	if not _stone_mesh_cache.has(key):
		_stone_mesh_cache[key] = _make_noisy_box(size, seed)
	var mi := MeshInstance3D.new()
	mi.mesh = _stone_mesh_cache[key]
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _hash3(x: int, y: int, z: int, seed: float) -> float:
	var s := sin(float(x) * 127.1 + float(y) * 311.7 + float(z) * 74.7 + seed * 269.5) * 43758.5453
	return s - floor(s)

func _vnoise(p: Vector3, seed: float) -> float:
	var fx: float = floor(p.x)
	var fy: float = floor(p.y)
	var fz: float = floor(p.z)
	var xi := int(fx)
	var yi := int(fy)
	var zi := int(fz)
	var xf: float = p.x - fx
	var yf: float = p.y - fy
	var zf: float = p.z - fz
	var u: float = xf * xf * (3.0 - 2.0 * xf)
	var v: float = yf * yf * (3.0 - 2.0 * yf)
	var w: float = zf * zf * (3.0 - 2.0 * zf)
	var c000: float = _hash3(xi, yi, zi, seed)
	var c100: float = _hash3(xi + 1, yi, zi, seed)
	var c010: float = _hash3(xi, yi + 1, zi, seed)
	var c110: float = _hash3(xi + 1, yi + 1, zi, seed)
	var c001: float = _hash3(xi, yi, zi + 1, seed)
	var c101: float = _hash3(xi + 1, yi, zi + 1, seed)
	var c011 := _hash3(xi, yi + 1, zi + 1, seed)
	var c111 := _hash3(xi + 1, yi + 1, zi + 1, seed)
	return lerpf(lerpf(lerpf(c000, c100, u), lerpf(c010, c110, u), v), lerpf(lerpf(c001, c101, u), lerpf(c011, c111, u), v), w)

func _make_noisy_box(size: Vector3, seed: float) -> ArrayMesh:
	var n := 3 # 每面 3×3 细分
	var amp := 0.05
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	# 六面：[法线, U 轴, V 轴, 起始角点]（U×V=法线，三角绕序统一向外）
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-hx, -hy, hz)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(hx, -hy, -hz)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(hx, -hy, hz)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-hx, -hy, -hz)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-hx, hy, -hz)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-hx, -hy, hz)],
	]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for fi in faces.size():
		var face: Array = faces[fi]
		var uax: Vector3 = face[1]
		var vax: Vector3 = face[2]
		var corner: Vector3 = face[3]
		var ulen := size.x if absf(uax.x) > 0.5 else size.y if absf(uax.y) > 0.5 else size.z
		var vlen := size.x if absf(vax.x) > 0.5 else size.y if absf(vax.y) > 0.5 else size.z
		var base := verts.size()
		for j in n + 1:
			for i in n + 1:
				var p: Vector3 = corner + uax * (ulen * float(i) / float(n)) + vax * (vlen * float(j) / float(n))
				var q := p * 1.9
				var off := Vector3(_vnoise(q, seed) - 0.5, _vnoise(q, seed + 31.7) - 0.5, _vnoise(q, seed + 57.3) - 0.5) * (2.0 * amp)
				verts.append(p + off)
				uvs.append(Vector2(float(i) / float(n), float(j) / float(n)))
		for j in n:
			for i in n:
				var a := base + j * (n + 1) + i
				var b := a + 1
				var c := a + n + 1
				var d := c + 1
				indices.append_array([a, b, d, a, d, c])
	# 法线：按焊接位置累加面法线后归一（棱角平滑成粗粝石面）
	var acc := {}
	for t in range(0, indices.size(), 3):
		var ia := indices[t]
		var ib := indices[t + 1]
		var ic := indices[t + 2]
		var fn := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		for idx in [ia, ib, ic]:
			var k := str(verts[idx])
			acc[k] = (acc.get(k, Vector3.ZERO) as Vector3) + fn
	var normals := PackedVector3Array()
	for vi in verts.size():
		var an := acc.get(str(verts[vi]), Vector3.UP) as Vector3
		normals.append(an.normalized() if an.length() > 0.0001 else Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_statue() -> void:
	_model = Node3D.new()
	add_child(_model)
	var stone := _pbr(Color(0.75, 0.72, 0.66), 0.95, 0.0, "rock")
	_stone_box(_model, Vector3(1.5, 0.8, 1.5), stone, Vector3(0, 0.4, 0), 3.1)
	_stone_box(_model, Vector3(1.1, 1.0, 1.1), stone, Vector3(0, 1.3, 0), 7.7)
	_head = Node3D.new()
	_head.position = Vector3(0, 2.15, 0)
	_model.add_child(_head)
	_stone_box(_head, Vector3(0.85, 0.7, 1.05), stone, Vector3.ZERO, 12.3)
	for hx in [-0.28, 0.28]:
		var horn := Util.cyl(_head, 0.01, 0.11, 0.45, stone, Vector3(hx, 0.5, -0.1), 6)
		Util.sph(_head, 0.08, _reg_mat(Util.glow(Color(1, 0.8, 0.2), 2.5)), Vector3(hx, 0.1, 0.5), 8, 6)
	Util.box(_head, Vector3(0.5, 0.2, 0.1), _reg_mat(Util.glow(Color(1, 0.33, 0.06), 2.5)), Vector3(0, -0.18, 0.53))

var _tank_wrap: Node3D = null # 坦克 GLB 朝向节点（update 里随 _facing 转整车）
var _tank_anim: AnimationPlayer = null

func _build_tank() -> void:
	# Dogra 重装甲扫讨车 → Quaternius 坦克（CC0，带骨骼行进动画）：
	# 原生车长 17.68 沿 X、车头在 -X：×0.30 缩放 + rotY 90° 转到 +Z，按实测 AABB 居中贴地
	_model = Node3D.new()
	add_child(_model)
	_tank_wrap = Node3D.new()
	_tank_wrap.rotation.y = PI / 2.0
	_tank_wrap.scale = Vector3.ONE * 0.30
	_model.add_child(_tank_wrap)
	var inst: Node3D = (load("res://assets/vehicles/tank.glb") as PackedScene).instantiate()
	inst.position = Vector3(1.466, 0.013, -2.587)
	_tank_wrap.add_child(inst)
	_head = Node3D.new() # 占位：炮塔随整车朝向（update 对 _head 的赋值无害）
	_head.position = Vector3(0, 1.6, 0)
	_model.add_child(_head)
	_tank_anim = _find_anim(inst)
	if _tank_anim:
		for n in _tank_anim.get_animation_list():
			if n.contains("Forward"):
				_tank_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
				_tank_anim.play(n)
	_collect_flash_mats()
	Util.sph(_model, 0.16, _reg_mat(Util.glow(Color(1, 0.2, 0.1), 3.0)), Vector3(0, 1.0, 2.45), 12, 9) # 核心球收敛（0.3→0.16，位置/判定不变）

func _build_hp_bar() -> void:
	_hp_w = 3.4 if type == "tank" else 1.15
	_hp_bar = Node3D.new()
	var bg := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(_hp_w, 0.13)
	bg.mesh = pm
	bg.material_override = Util.flat(Color(0.14, 0, 0, 0.75))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(_hp_w, 0.13)
	_hp_fill.mesh = pm2
	_hp_fill.material_override = Util.flat(Color(1, 0.27, 0.27))
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_fill.position.z = -0.01
	_hp_bar.add_child(_hp_fill)
	_hp_bar.visible = false
	add_child(_hp_bar)

## 受伤/死亡表现分型：人形出血、孢子喷绿浆、机械冒火花、石像掉碎石
func _fx_kind() -> String:
	match type:
		"spore":
			return "goo"
		"statue":
			return "rock"
		"turret", "tank", "roller":
			return "spark"
		_:
			return "blood"

func on_hit(dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
	if not alive:
		return
	# 盾牌兵正面拦截：玩家子弹的命中点带真实落点，落在盾面正面 ±65° 内被挡下（火花、无伤）；
	# 侧/背命中照常受伤；油桶爆炸等以「敌人自身中心」为命中点的全向伤害水平偏移≈0，不拦截。
	if type == "shield" and _point != Vector3.ZERO:
		var to_hit := Vector3(_point.x - global_position.x, 0.0, _point.z - global_position.z)
		if to_hit.length() > 0.05:
			var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
			if to_hit.normalized().dot(fwd) > 0.42:
				_alert = true # 被打仍警觉（知道有人在正面开火）
				var prs = _ctx.get("projectiles")
				if prs:
					prs.spawn_hit_fx(_point, "spark")
				return
	_alert = true # 挨打即交战（哪怕没看见人）
	hp -= dmg
	var pr = _ctx.get("projectiles")
	if pr and _point != Vector3.ZERO:
		pr.spawn_hit_fx(_point, _fx_kind()) # 分型沿用 _fx_kind，只换表现层为贴图粒子
	_flash_t = 0.08
	for m in _flash_mats:
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			sm.emission_enabled = true
			sm.emission = Color(0.4, 0.4, 0.4)
	if hp <= 0:
		_die()
	else:
		_react("Hit_Chest", 0.3)

func _die() -> void:
	alive = false
	AudioSys.play("die", -6.0, randf_range(0.9, 1.1))
	# 死亡残留：血泊/绿浆留在原地（独立节点，不随尸体回收消失）；机械爆一团火并留焦痕
	var pr2 = _ctx.get("projectiles")
	if pr2:
		var feet := global_position + Vector3(0, 0.045, 0)
		match _fx_kind():
			"blood":
				pr2.spawn_pool(feet, Color(0.35, 0.02, 0.02), randf_range(0.5, 0.72))
			"goo":
				pr2.spawn_pool(feet, Color(0.15, 0.4, 0.08), 0.5)
			"spark":
				if type == "turret" or type == "tank":
					pr2.spawn_explosion_fx(global_position + Vector3(0, 0.8, 0), 1.7)
				pr2.spawn_pool(feet, Color(0.05, 0.05, 0.05), 0.95, 20.0)
			"rock":
				pr2.spawn_hit_fx(global_position + Vector3(0, 1.0, 0), "rock")
	if not _scored:
		_scored = true
		_ctx["on_score"].call(score_value)
	if _hp_bar:
		_hp_bar.visible = false
	for m in _flash_mats:
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).emission_enabled = false
	if _anim and _death_clip:
		# 真死亡动画（骨骼倒地），不再整个人像纸片一样翻倒
		_death_t = _death_len
		_anim.play("Death01", 0.08)
	elif _anim:
		_death_t = 0.85
		_anim.stop()
	else:
		_death_t = 0.85
	if type == "roller":
		_ctx["projectiles"].spawn_explosion_fx(global_position + Vector3(0, 0.5, 0), 1.8)

func _muzzle_pos(h: float) -> Vector3:
	return global_position + Vector3(sin(_facing) * 0.6, h, cos(_facing) * 0.6)

func _fire_orb(player, speed: float, height: float, inacc: float) -> void:
	_react("Pistol_Shoot", 0.26)
	var from := _muzzle_pos(height)
	var target := Vector3(
		player.global_position.x + randf_range(-inacc, inacc),
		player.chest_y() + randf_range(-0.15, 0.25),
		player.global_position.z + randf_range(-inacc, inacc))
	var dirv := (target - from).normalized()
	_ctx["projectiles"].spawn_orb(from, dirv, speed, 1)
	# 开火反馈：枪口火光面片 + 向右抛壳（纯表现，走代码枪口点位与既定妥协一致）
	_ctx["projectiles"].spawn_muzzle_flash(from, dirv, 0.85)
	_ctx["projectiles"].spawn_shell(from + Vector3(0, -0.04, 0), Vector3(-dirv.z, 0, dirv.x))
	AudioSys.play("enemy_shoot", -10.0)

func _fire_grenade(player, from_h: float = 1.1, flight: float = 1.35) -> void:
	_react("Pistol_Shoot", 0.26)
	var from := _muzzle_pos(from_h)
	var t := flight
	var g := 16.0
	var vel := Vector3(
		(player.global_position.x - from.x) / t,
		((player.global_position.y + 0.3 - from.y) + 0.5 * g * t * t) / t,
		(player.global_position.z - from.z) / t)
	_ctx["projectiles"].spawn_grenade(from, vel)
	# 迫击炮发射反馈：大号炮口火光 + 一团发射烟
	_ctx["projectiles"].spawn_muzzle_flash(from, vel.normalized(), 1.7)
	_ctx["projectiles"].spawn_smoke_puff(from)
	AudioSys.play("enemy_shoot", -8.0)

## 返回 true 表示可回收
func update_enemy(dt: float, player, camera_pos: Vector3) -> bool:
	if not alive:
		_death_t -= dt
		if not _death_clip:
			# 无骨骼死亡片段的自建敌人（炮塔/滚球等）才走整体翻倒
			var k := maxf(0.0, _death_t / 0.85)
			rotation.x = (1.0 - k) * PI / 2.0 * 0.9
			global_position.y = _base_y - (1.0 - k) * 0.35
		return _death_t <= 0.0
	# 远处降频：距玩家 >110m 的敌人每 0.3 秒批量步进一次，保开放世界帧率（死亡走逐帧分支不受影响）
	var pdx: float = player.global_position.x - global_position.x
	var pdz: float = player.global_position.z - global_position.z
	if pdx * pdx + pdz * pdz > 12100.0:
		_dormant += dt
		if _dormant < 0.3:
			return false
		dt = _dormant
		_dormant = 0.0
	_t += dt
	if _react_t > 0.0:
		_react_t -= dt
		if _react_t <= 0.0 and alive and _anim and _stance_clip != "":
			_anim.play(_stance_clip, 0.12)
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			for m in _flash_mats:
				if m is StandardMaterial3D:
					(m as StandardMaterial3D).emission_enabled = false
	if _melee_timer > 0.0: _melee_timer -= dt

	var dx: float = player.global_position.x - global_position.x
	var dz: float = player.global_position.z - global_position.z
	var dist := sqrt(dx * dx + dz * dz)
	_facing = atan2(dx, dz)

	# 视线交战：错峰复核视线，看见（射程 1.25 倍内）/贴近/挨打才交战；直射开火还要当帧视线无遮挡
	_los_t -= dt
	if _los_t <= 0.0:
		_los_t = 0.22 + randf() * 0.1
		_los_ok = _compute_los(player)
		if _los_ok and dist < float(_data.get("range", 30.0)) * 1.25:
			_alert = true
	if dist < 9.0 and player.alive:
		_alert = true
	# 警觉表现：刚发现玩家时「！」弹出 0.85 秒；未交战的站桩射手在营地里巡逻走动
	if _alert and not _was_alert:
		_alert_t = 0.85
	_was_alert = _alert
	if _alert_icon:
		_alert_t = maxf(0.0, _alert_t - dt)
		_alert_icon.visible = _alert_t > 0.0
		if _alert_icon.visible:
			_alert_icon.scale = Vector3.ONE * (1.0 + 0.6 * maxf(0.0, _alert_t - 0.55) / 0.3)
	if not _alert and type in ["rifleman", "sniper", "mortar", "garth", "langel", "bomber", "shield"]:
		_patrol(dt)
	# 射手上身俯仰：上身随目标高低俯仰（朝上/朝下打都成立，不再只有平射）
	if _aim_mod_e:
		var elev := 0.0
		if _alert and dist > 0.5:
			elev = clampf(atan2(player.chest_y() - (global_position.y + 1.3), dist), -0.55, 0.55)
		_aim_mod_e.pitch = lerpf(_aim_mod_e.pitch, elev * 0.75, minf(1.0, dt * 8.0))

	match type:
		"rifleman", "garth", "langel":
			if _alert:
				_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _alert and _los_ok:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.85, 1.2)
				_fire_orb(player, float(_data["orb_speed"]), 1.25, 0.5)
		"sniper":
			if _alert:
				_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _alert and _los_ok:
				_fire_timer = float(_data["fire_interval"])
				_fire_orb(player, float(_data["orb_speed"]), 1.3, 0.25)
		"mortar":
			if _alert:
				_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _alert:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.9, 1.15)
				_fire_grenade(player)
		"bomber":
			# 掷弹兵：中距离站位手掷雷（飞行 1.0s 的低弧线），与迫击炮同走榴弹链（弧线越掩体，不查直射视线）
			if _alert:
				_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _alert:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.9, 1.15)
				_fire_grenade(player, 1.35, 1.0)
		"shield":
			# 盾牌兵：举盾缓步逼近到 11m 内停步，偶尔从盾后开火（正面子弹被盾挡，见 on_hit）
			if _alert:
				_face_player()
				if dist > 11.0 and player.alive:
					var sp2 := float(_data.get("speed", 2.2))
					global_position.x += dx / dist * sp2 * dt
					global_position.z += dz / dist * sp2 * dt
					var lv4 = _ctx.get("level")
					if lv4:
						global_position.y = lv4.get_support_y(global_position.x, global_position.z, global_position.y)
					_play_e("Walk")
				else:
					_play_e(_stance_clip)
				_fire_timer -= dt
				if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _los_ok:
					_fire_timer = float(_data["fire_interval"]) * randf_range(0.9, 1.15)
					_fire_orb(player, float(_data["orb_speed"]), 1.25, 0.5)
		"statue":
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _alert:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.9, 1.2)
				_fire_grenade(player, 2.1)
		"akbar":
			_update_akbar(dt, player, dist)
		"turret":
			if _head:
				_head.rotation.y = _facing - rotation.y
			if dist < float(_data["range"]) and player.alive and _alert and _los_ok:
				if _burst_left > 0:
					_fire_timer -= dt
					if _fire_timer <= 0.0:
						_fire_timer = float(_data["fire_interval"])
						_burst_left -= 1
						_fire_orb(player, float(_data["orb_speed"]), 1.05, 0.4)
				else:
					_fire_timer -= dt
					if _fire_timer <= 0.0:
						_burst_left = int(_data["burst"])
						_fire_timer = float(_data["burst_pause"])
		"runner", "spore":
			_face_player()
			var melee_r := float(_data.get("melee_range", 1.6))
			if _alert and dist > melee_r and player.alive:
				var sp := float(_data.get("speed", 5.0))
				global_position.x += dx / dist * sp * dt
				global_position.z += dz / dist * sp * dt
				# 移动贴地：跟着地形起伏走，不再平地滑行穿山
				var lv2 = _ctx.get("level")
				if lv2:
					if type == "spore":
						_base_y = lv2.get_support_y(global_position.x, global_position.z, _base_y)
					else:
						global_position.y = lv2.get_support_y(global_position.x, global_position.z, global_position.y)
			elif _alert and player.alive and _melee_timer <= 0.0:
				_melee_timer = float(_data.get("melee_cooldown", 0.9))
				player.take_damage(1)
		"roller":
			if _alert and player.alive and dist > 0.01:
				var sp := float(_data["speed"])
				global_position.x += dx / dist * sp * dt
				global_position.z += dz / dist * sp * dt
				var lv3 = _ctx.get("level")
				if lv3:
					global_position.y = lv3.get_support_y(global_position.x, global_position.z, global_position.y)
			if _roller_ball:
				_roller_ball.rotation.x -= dt * 9.0
			if dist < float(_data["explode_range"]) and player.alive:
				_ctx["projectiles"].spawn_explosion_fx(global_position + Vector3(0, 0.5, 0), 2.3)
				if dist < 2.4:
					player.take_damage(1)
				hp = 0
				_die()
		"tank":
			global_position.x = _base_x + sin(_t * 0.45) * 6.0
			if _tank_wrap:
				_tank_wrap.rotation.y = PI / 2.0 + _facing - rotation.y
			_face_player()
			if _head:
				_head.rotation.y = _facing - rotation.y
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive and _alert and _los_ok:
				_fire_timer = float(_data["fire_interval"])
				for i in [-1, 0, 1]:
					var from := _muzzle_pos(1.8)
					var dir := Vector3(dx, player.chest_y() - from.y, dz).normalized()
					var right := Vector3(-dir.z, 0, dir.x)
					dir = (dir + right * i * 0.12).normalized()
					_ctx["projectiles"].spawn_orb(from, dir, float(_data["orb_speed"]), 1, 2.0) # 坦克炮弹=重弹：命中播爆炸视觉
				AudioSys.play("enemy_shoot", -8.0)

	hit_x = global_position.x
	hit_z = global_position.z
	if type != "akbar":
		hit_y = global_position.y + (1.7 if type == "tank" else 0.95 if type == "turret" else 1.6 if type == "statue" else 1.0)
	if type == "spore":
		global_position.y = _base_y + absf(sin(_t * 9.0)) * 0.22
		hit_y = global_position.y + 0.6

	if _hp_bar:
		var show := hp < max_hp and dist < 55.0
		_hp_bar.visible = show
		if show:
			var pct := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			_hp_fill.scale.x = pct
			_hp_fill.position.x = -(1.0 - pct) * _hp_w / 2.0
			_hp_bar.position = Vector3(0, 3.1 if type == "tank" else 3.0 if type == "statue" else 2.2, 0)
			if _hp_bar.global_position.distance_to(camera_pos) > 0.6:
				_hp_bar.look_at(camera_pos, Vector3.UP)
	return false

func _play_e(clip: String) -> void:
	if _anim and clip != "" and _react_t <= 0.0 and _anim.current_animation != clip:
		_anim.play(clip, 0.15)

## 营地巡逻：未交战时在出生点周围慢速往返（走两步、停一停），世界是活的不是靶场
func _patrol(dt: float) -> void:
	_patrol_t -= dt
	if _patrol_moving:
		var to := _patrol_dest - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.4 or _patrol_t <= 0.0:
			_patrol_moving = false
			_patrol_t = randf_range(1.2, 3.2)
			_play_e(_stance_clip)
		else:
			var dir := to / d
			global_position.x += dir.x * 1.35 * dt
			global_position.z += dir.z * 1.35 * dt
			var lv = _ctx.get("level")
			if lv:
				global_position.y = lv.get_support_y(global_position.x, global_position.z, global_position.y)
			rotation.y = atan2(dir.x, dir.z)
			_play_e("Walk")
	elif _patrol_t <= 0.0:
		_patrol_moving = true
		_patrol_t = randf_range(2.0, 3.6)
		var a := randf() * TAU
		var r := randf_range(1.5, 4.2)
		_patrol_dest = _home + Vector3(cos(a) * r, 0.0, sin(a) * r)

## 视线复核：眼睛点 → 玩家胸口，地形隆起与实体掩体都会挡（关卡提供 has_los）
func _compute_los(player) -> bool:
	var lvl = _ctx.get("level")
	if lvl == null or player == null or not player.alive:
		return false
	var eye_h := 1.45
	if type == "turret":
		eye_h = 1.2
	elif type == "statue":
		eye_h = 2.4
	elif type == "tank":
		eye_h = 2.0
	elif type == "akbar":
		eye_h = 0.6
	var eye := global_position + Vector3(0, eye_h, 0)
	var tgt := Vector3(player.global_position.x, player.chest_y(), player.global_position.z)
	return lvl.has_los(eye, tgt)

func _face_player() -> void:
	if type != "turret" and type != "tank":
		rotation.y = _facing
	# 新 GLB 士兵在 Godot 里朝 +Z（与自建模型同约定），不再偏 π（旧 UAL 朝 -Z 才需要）

func _update_akbar(dt: float, player, dist: float) -> void:
	_ak_timer -= dt
	match _ak_phase:
		0: # 潜伏
			targetable = false
			hit_r = 0.01
			if _ak_timer <= 0.0 and dist < float(_data["range"]) and player.alive:
				_ak_phase = 1
				_ak_timer = 0.55
		1: # 升起
			_model.position.y = lerpf(_model.position.y, -0.12, minf(1.0, dt * 6.0))
			if _ak_timer <= 0.0:
				_ak_phase = 2
				_ak_timer = 2.0
				_ak_shots = 2
				targetable = true
				hit_r = float(_data["radius"]) + 0.3
				hit_y = global_position.y + 1.35
		2: # 射击
			_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and _ak_shots > 0:
				_fire_timer = 0.8
				_ak_shots -= 1
				_fire_orb(player, float(_data["orb_speed"]), 1.35, 0.4)
			if _ak_timer <= 0.0:
				_ak_phase = 3
				_ak_timer = 0.55
		3: # 下沉
			_model.position.y = lerpf(_model.position.y, -1.05, minf(1.0, dt * 6.0))
			targetable = false
			hit_r = 0.01
			if _ak_timer <= 0.0:
				_ak_phase = 0
				_ak_timer = randf_range(1.2, 2.4)

func destroy_enemy() -> void:
	queue_free()
