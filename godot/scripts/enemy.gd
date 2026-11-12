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

const HUMANOID := ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar"]
const TINTS := {
	# 整体提饱和提亮与环境（丛林绿褐/基地灰）拉开距离——用户实测「NPC 糊在背景里看不清」（2026-11-12 三修）
	"rifleman": Color(0.56, 0.62, 0.24), "runner": Color(0.88, 0.18, 0.1),
	"sniper": Color(0.52, 0.4, 0.75), "mortar": Color(0.72, 0.5, 0.26),
	"garth": Color(0.34, 0.37, 0.46), "langel": Color(0.45, 0.58, 0.8),
	"akbar": Color(0.3, 0.55, 0.6),
}

func setup(p_type: String, pos: Vector3, ctx: Dictionary, soldier_scene: PackedScene) -> void:
	type = p_type
	_ctx = ctx
	_data = Data.ENEMIES[type]
	hp = int(_data["hp"])
	max_hp = hp
	score_value = int(_data["score"])
	global_position = pos
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
	_build(soldier_scene)
	_build_hp_bar()

func _reg_mat(m: Material) -> Material:
	_mats.append(m)
	return m

func _pbr(c: Color, rough: float = 0.8, metal: float = 0.0, tex: String = "") -> Material:
	var m := Util.pbr(c, tex, rough, metal)
	_mats.append(m)
	_flash_mats.append(m)
	return m

func _build(soldier_scene: PackedScene) -> void:
	if HUMANOID.has(type) and soldier_scene != null:
		_build_soldier(soldier_scene)
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
	# 染色：复制导入材质并乘色调（保留原贴图）
	var tint: Color = TINTS[type]
	_tint_recursive(_model, tint)
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
			"rifleman", "sniper", "garth", "langel": _stance_clip = "Pistol_Idle"
			_: _stance_clip = "Idle"
		_anim.play(_stance_clip)
	# 枪械（除红衣突击兵无枪、榴弹兵用筒）
	if type != "runner" and type != "mortar":
		_attach_gun(_model, type == "sniper")
	if type == "mortar":
		var tube := Util.cyl(self, 0.11, 0.13, 0.85, _pbr(Color(0.2, 0.2, 0.2), 0.5, 0.6), Vector3(0.48, 0.62, 0.15))
		tube.rotation.z = -0.5
		Util.box(self, Vector3(0.5, 0.22, 0.5), _pbr(Color(0.27, 0.27, 0.27), 0.6, 0.4), Vector3(0.48, 0.11, 0.15))
	_attach_gear()
	if type == "akbar":
		_model.position.y = -1.05
		targetable = false

func _tint_recursive(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mesh := mi.mesh
		if mesh:
			for s in mesh.get_surface_count():
				var orig := mi.get_active_material(s)
				if orig is StandardMaterial3D:
					var m := (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.albedo_color = tint
					# 与主角同款织物纹理（乘数+法线），纯色面不再塑料感
					m.albedo_texture = Util.tex_diff("weave")
					m.normal_texture = Util.tex_nor("weave")
					m.normal_scale = 0.35
					m.texture_filter = 5 # 各向异性过滤
					m.emission_enabled = false
					mi.set_surface_override_material(s, m)
					_mats.append(m)
					_flash_mats.append(m)
	for ch in n.get_children():
		_tint_recursive(ch, tint)

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

func _attach_gun(model: Node3D, long_gun: bool) -> void:
	var gun := Node3D.new()
	var gm := Util.pbr(Color(0.09, 0.09, 0.1), "", 0.45, 0.8)
	Util.box(gun, Vector3(0.07, 0.11, 1.0 if long_gun else 0.6), gm, Vector3(0, 0, 0.3))
	Util.box(gun, Vector3(0.05, 0.16, 0.07), gm, Vector3(0, -0.1, 0.12))
	var skel := _find_skeleton(model)
	if skel:
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).contains("RightHand") or skel.get_bone_name(i) == "DEF-hand.R":
				var ba := BoneAttachment3D.new()
				ba.bone_name = skel.get_bone_name(i)
				skel.add_child(ba)
				ba.add_child(gun)
				gun.position = Vector3(0, 0.05, 0.05)
				gun.rotation.x = -0.35
				return
	model.add_child(gun)
	gun.position = Vector3(0.3, 1.1, 0.3)

func _eba(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	if skel == null or skel.find_bone(bone) < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	return ba

func _helmet(skel: Skeleton3D, color: Color, metal: float = 0.15) -> void:
	var head := _eba(skel, "DEF-head")
	if head == null:
		return
	var hm := _pbr(color, 0.55, metal)
	var dome := Util.sph(head, 0.158, hm, Vector3(0, 0.175, 0), 14, 10)
	dome.scale = Vector3(1.1, 0.68, 1.12)
	Util.cyl(head, 0.185, 0.19, 0.028, hm, Vector3(0, 0.132, 0), 14)

## 兵种装备件：头盔/胸甲/肩甲/背包/帽兜/头带——兵种一眼可辨
func _attach_gear() -> void:
	var skel := _find_skeleton(_model)
	if skel == null:
		return
	var tint: Color = TINTS[type]
	match type:
		"rifleman":
			_helmet(skel, Color(0.78, 0.8, 0.35)) # 亮黄盔，丛林里最扎眼
		"garth":
			_helmet(skel, Color(0.16, 0.17, 0.2), 0.55)
			var visor := _eba(skel, "DEF-head")
			if visor:
				Util.box(visor, Vector3(0.17, 0.035, 0.03), Util.glow(Color(1, 0.45, 0.1), 2.2), Vector3(0, 0.1, 0.148))
			var armor := _pbr(Color(0.2, 0.21, 0.25), 0.42, 0.65)
			var chest := _eba(skel, "DEF-spine.002")
			if chest:
				Util.box(chest, Vector3(0.38, 0.42, 0.09), armor, Vector3(0, 0.1, 0.155))
			for side in ["L", "R"]:
				var arm := _eba(skel, "DEF-upper_arm." + side)
				if arm:
					Util.box(arm, Vector3(0.2, 0.12, 0.24), armor, Vector3(0, 0.03, 0))
		"langel":
			_helmet(skel, Color(0.92, 0.94, 0.97), 0.4) # 白盔
		"mortar":
			_helmet(skel, Color(0.85, 0.55, 0.2)) # 亮橙盔
			var back := _eba(skel, "DEF-spine.002")
			if back:
				Util.box(back, Vector3(0.36, 0.46, 0.18), _pbr(Color(0.3, 0.24, 0.14), 0.9), Vector3(0, 0.1, -0.21))
				Util.cyl(back, 0.05, 0.05, 0.4, _pbr(Color(0.55, 0.42, 0.2), 0.6, 0.3), Vector3(0.12, 0.42, -0.21), 8)
		"sniper":
			var head := _eba(skel, "DEF-head")
			if head:
				var cm := _pbr(Color(0.62, 0.5, 0.85), 0.9)
				Util.cyl(head, 0.15, 0.158, 0.085, cm, Vector3(0, 0.185, 0), 12)
				Util.box(head, Vector3(0.17, 0.025, 0.15), cm, Vector3(0, 0.148, 0.165))
		"runner":
			var head2 := _eba(skel, "DEF-head")
			if head2:
				var band := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.095
				tm.outer_radius = 0.148
				band.mesh = tm
				band.material_override = _pbr(tint.darkened(0.45), 0.9)
				band.position = Vector3(0, 0.155, 0)
				band.rotation.x = PI / 2.0
				head2.add_child(band)
	# 统一敌方标识：左臂猩红臂章（水里的 Akbar 除外）——任何距离先认红
	if type != "akbar":
		var arm := _eba(skel, "DEF-upper_arm.L")
		if arm:
			Util.box(arm, Vector3(0.17, 0.09, 0.19), _pbr(Color(0.8, 0.07, 0.09), 0.7), Vector3(0, -0.08, 0))

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

func _build_turret() -> void:
	_model = Node3D.new()
	add_child(_model)
	var metal := _pbr(Color(0.42, 0.45, 0.4), 0.55, 0.6, "metal")
	Util.cyl(_model, 0.85, 1.05, 0.6, metal, Vector3(0, 0.3, 0), 14)
	_head = Node3D.new()
	_head.position.y = 0.95
	_model.add_child(_head)
	Util.box(_head, Vector3(1.05, 0.65, 0.85), _pbr(Color(0.3, 0.36, 0.28), 0.5, 0.6, "metal"), Vector3.ZERO)
	var bm := _pbr(Color(0.1, 0.1, 0.1), 0.4, 0.8)
	for bx in [-0.22, 0.22]:
		var barrel := Util.cyl(_head, 0.08, 0.08, 0.8, bm, Vector3(bx, 0, 0.55))
		barrel.rotation.x = PI / 2.0
	Util.sph(_head, 0.1, _reg_mat(Util.glow(Color(1, 0.15, 0.15), 2.5)), Vector3(0, 0.12, 0.44), 8, 6)

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

func _build_statue() -> void:
	_model = Node3D.new()
	add_child(_model)
	var stone := _pbr(Color(0.75, 0.72, 0.66), 0.95, 0.0, "rock")
	Util.box(_model, Vector3(1.5, 0.8, 1.5), stone, Vector3(0, 0.4, 0))
	Util.box(_model, Vector3(1.1, 1.0, 1.1), stone, Vector3(0, 1.3, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 2.15, 0)
	_model.add_child(_head)
	Util.box(_head, Vector3(0.85, 0.7, 1.05), stone, Vector3.ZERO)
	for hx in [-0.28, 0.28]:
		var horn := Util.cyl(_head, 0.01, 0.11, 0.45, stone, Vector3(hx, 0.5, -0.1), 6)
		Util.sph(_head, 0.08, _reg_mat(Util.glow(Color(1, 0.8, 0.2), 2.5)), Vector3(hx, 0.1, 0.5), 8, 6)
	Util.box(_head, Vector3(0.5, 0.2, 0.1), _reg_mat(Util.glow(Color(1, 0.33, 0.06), 2.5)), Vector3(0, -0.18, 0.53))

func _build_tank() -> void:
	# Dogra 重装甲扫讨车：卡车式车体 + 六轮 + 前部发光核心（弱点意象）
	_model = Node3D.new()
	add_child(_model)
	var hull_m := _pbr(Color(0.5, 0.52, 0.46), 0.5, 0.65, "metal")
	Util.box(_model, Vector3(2.5, 1.15, 4.0), hull_m, Vector3(0, 1.05, 0))
	Util.box(_model, Vector3(2.7, 0.55, 4.3), _pbr(Color(0.2, 0.2, 0.23), 0.6, 0.5), Vector3(0, 0.32, 0))
	var wheel_m := _pbr(Color(0.08, 0.08, 0.09), 0.7, 0.3)
	for sx in [-1.15, 1.15]:
		for wz in [-1.45, 0, 1.45]:
			var wheel := Util.cyl(_model, 0.42, 0.42, 0.24, wheel_m, Vector3(sx, 0.42, wz), 12)
			wheel.rotation.z = PI / 2.0
	_head = Node3D.new()
	_head.position = Vector3(0, 1.95, -0.6)
	_model.add_child(_head)
	Util.box(_head, Vector3(1.5, 0.65, 1.3), _pbr(Color(0.45, 0.4, 0.52), 0.5, 0.6, "metal"), Vector3.ZERO)
	var barrel := Util.cyl(_head, 0.13, 0.13, 1.5, _pbr(Color(0.1, 0.1, 0.1), 0.4, 0.8), Vector3(0, 0, 1.2))
	barrel.rotation.x = PI / 2.0
	Util.sph(_model, 0.3, _reg_mat(Util.glow(Color(1, 0.2, 0.1), 3.0)), Vector3(0, 1.05, 2.05), 12, 9)

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

func on_hit(dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
	if not alive:
		return
	hp -= dmg
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
	_ctx["projectiles"].spawn_orb(from, (target - from).normalized(), speed, 1)
	AudioSys.play("enemy_shoot", -10.0)

func _fire_grenade(player, from_h: float = 1.1) -> void:
	_react("Pistol_Shoot", 0.26)
	var from := _muzzle_pos(from_h)
	var t := 1.35
	var g := 16.0
	var vel := Vector3(
		(player.global_position.x - from.x) / t,
		((player.global_position.y + 0.3 - from.y) + 0.5 * g * t * t) / t,
		(player.global_position.z - from.z) / t)
	_ctx["projectiles"].spawn_grenade(from, vel)
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

	match type:
		"rifleman", "garth", "langel":
			_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.85, 1.2)
				_fire_orb(player, float(_data["orb_speed"]), 1.25, 0.5)
		"sniper":
			_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive:
				_fire_timer = float(_data["fire_interval"])
				_fire_orb(player, float(_data["orb_speed"]), 1.3, 0.25)
		"mortar":
			_face_player()
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.9, 1.15)
				_fire_grenade(player)
		"statue":
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive:
				_fire_timer = float(_data["fire_interval"]) * randf_range(0.9, 1.2)
				_fire_grenade(player, 2.1)
		"akbar":
			_update_akbar(dt, player, dist)
		"turret":
			if _head:
				_head.rotation.y = _facing - rotation.y
			if dist < float(_data["range"]) and player.alive:
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
			if dist > melee_r and player.alive:
				var sp := float(_data.get("speed", 5.0))
				global_position.x += dx / dist * sp * dt
				global_position.z += dz / dist * sp * dt
			elif player.alive and _melee_timer <= 0.0:
				_melee_timer = float(_data.get("melee_cooldown", 0.9))
				player.take_damage(1)
		"roller":
			if player.alive and dist > 0.01:
				var sp := float(_data["speed"])
				global_position.x += dx / dist * sp * dt
				global_position.z += dz / dist * sp * dt
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
			_face_player()
			if _head:
				_head.rotation.y = _facing - rotation.y
			_fire_timer -= dt
			if _fire_timer <= 0.0 and dist < float(_data["range"]) and player.alive:
				_fire_timer = float(_data["fire_interval"])
				for i in [-1, 0, 1]:
					var from := _muzzle_pos(1.8)
					var dir := Vector3(dx, player.chest_y() - from.y, dz).normalized()
					var right := Vector3(-dir.z, 0, dir.x)
					dir = (dir + right * i * 0.12).normalized()
					_ctx["projectiles"].spawn_orb(from, dir, float(_data["orb_speed"]), 1)
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

func _face_player() -> void:
	if type != "turret" and type != "tank":
		rotation.y = _facing + PI if HUMANOID.has(type) else _facing
	# GLB 士兵在 Godot 里朝 -Z（引擎约定），故人型兵偏 π；自建模型朝 +Z 不偏

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
