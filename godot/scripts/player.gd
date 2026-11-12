class_name Player
extends Node3D

## 玩家 Bill/Lance —— Quaternius UAL（CC0）骨骼模型 + 46 条动画（跑/跳/翻滚/趴/瞄准/死亡），
## 红头巾/子弹带等身份件挂骨骼；瞄准俯仰走 AimModifier 胸骨后处理
## 状态只通过信号通知 Game，绝不直接改游戏状态（旧 JS 版致命 bug 的结构性教训，Godot 版沿用）

signal died
signal damaged

var radius := 0.38
var facing := PI # 朝 -Z
var vy := 0.0
var grounded := true
var prone := false
var alive := true
var hp_cells := 3
var weapon := "N"
var rapid := false
var barrier := 0.0
var invuln := 0.0
var fire_timer := 0.0
var aim_pitch := 0.0

var _blink := false
var _walk_phase := 0.0
var _flip := 0.0
var _flash_t := 0.0
var _char_id := "bill"

var visual: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _aim_mod: AimModifier
var _cur_clip := ""
var _sprinting := false
var _hit_t := 0.0 # 受击反应剩余时间
var _land_t := 0.0 # 落地动作剩余时间
var _recoil := 0.0 # 开火后坐（0..1，驱动胸骨后仰）
var _shield: MeshInstance3D
var _flash: MeshInstance3D

static var _ual_scene: PackedScene = null

func _init() -> void:
	hp_cells = int(Data.PLAYER["max_cells"])

func setup(char_id: String) -> void:
	_char_id = char_id
	_build_mesh()

func _mat(c: Color, rough: float = 0.8, metal: float = 0.0, tex: String = "") -> StandardMaterial3D:
	return Util.pbr(c, tex, rough, metal)

func _build_mesh() -> void:
	var pal: Dictionary = Data.CHARACTERS[_char_id]
	visual = Node3D.new()
	add_child(visual)
	if _ual_scene == null:
		_ual_scene = load("res://assets/char/ual.glb")
	_model = _ual_scene.instantiate() as Node3D
	visual.add_child(_model)
	_tint_model(_model, Color(0.83, 0.62, 0.44) if _char_id == "bill" else Color(0.74, 0.52, 0.37))
	_anim = _find_anim(_model)
	if _anim:
		for n in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Pistol_Idle", "Pistol_Aim_Up", "Pistol_Aim_Neutral", "Pistol_Aim_Down", "Swim_Idle"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var skel := _find_skel(_model)
	if skel:
		_aim_mod = AimModifier.new()
		skel.add_child(_aim_mod)
		_attach_identity(skel, pal)
		_attach_pants(skel, pal)
		_attach_rifle(skel)
	_play_clip("Idle")

	# 防护罩
	_shield = Util.sph(self, 1.3, Util.flat(Color(0.4, 0.8, 1, 0.20)), Vector3(0, 1.0, 0), 18, 12)
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	# 枪口闪光（独立于 visual，避免翻滚影响）
	_flash = Util.sph(get_parent() if get_parent() else self, 0.17, Util.glow(Color(1, 0.8, 0.35), 3.0, 0.0), Vector3.ZERO, 8, 6)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _tint_model(n: Node, main_color: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var orig := mi.get_active_material(s)
				if orig is StandardMaterial3D:
					var m := (orig as StandardMaterial3D).duplicate() as StandardMaterial3D
					# 关节面（M_Joints）压暗当阴影色，主体面用肤色——模型无贴图，直接定色
					m.albedo_color = main_color.darkened(0.42) if orig.resource_name.contains("Joint") else main_color
					# 织物纹理（近白乘数 + 法线）：只加布料经纬与皮肤起伏，不改定色
					m.albedo_texture = Util.tex_diff("weave")
					m.normal_texture = Util.tex_nor("weave")
					m.normal_scale = 0.35
					m.texture_filter = 5 # 各向异性过滤
					mi.set_surface_override_material(s, m)
	for c in n.get_children():
		_tint_model(c, main_color)

func _bone_attach(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	return ba

func _attach_identity(skel: Skeleton3D, pal: Dictionary) -> void:
	var head := _bone_attach(skel, "DEF-head")
	if _char_id == "bill":
		# 比尔：红头巾（环 + 后飘尾）
		var band_m := _mat(pal["bandana"], 0.85)
		var bandana := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.095
		tm.outer_radius = 0.15
		bandana.mesh = tm
		bandana.material_override = band_m
		bandana.position = Vector3(0, 0.16, 0)
		bandana.rotation.x = PI / 2.0
		head.add_child(bandana)
		Util.box(head, Vector3(0.09, 0.24, 0.03), band_m, Vector3(0.08, -0.02, -0.155))
		# 白背心：筒形壳裹住躯干（挂 spine.002，平板会像广告牌——实测教训）
		var chest := _bone_attach(skel, "DEF-spine.002")
		var vest_m := _mat(pal["top"], 0.95, 0.0, "weave")
		var vest := Util.cyl(chest, 0.20, 0.165, 0.52, vest_m, Vector3(0, 0.10, 0), 12)
		vest.scale = Vector3(1.3, 1, 0.85)
	else:
		# 兰斯：长发（发盖 + 后发）+ 斜挎子弹带
		var hair_m := _mat(pal["hair"], 0.95)
		var cap := Util.sph(head, 0.145, hair_m, Vector3(0, 0.17, -0.01), 12, 9)
		cap.scale = Vector3(1, 0.85, 1)
		Util.box(head, Vector3(0.24, 0.36, 0.07), hair_m, Vector3(0, 0.0, -0.13))
		var chest := _bone_attach(skel, "DEF-spine.003")
		var strap := Util.box(chest, Vector3(0.46, 0.09, 0.38), _mat(Color(0.25, 0.18, 0.1), 0.85, 0.0, "weave"), Vector3(0, 0.1, 0))
		strap.rotation.z = 0.6
		# 子弹带正面一排黄铜子弹粒
		var brass := _mat(Color(0.85, 0.62, 0.25), 0.35, 0.9)
		for i in 6:
			Util.cyl(strap, 0.021, 0.021, 0.055, brass, Vector3(-0.15 + float(i) * 0.06, 0.01, 0.20), 8)

func _attach_pants(skel: Skeleton3D, pal: Dictionary) -> void:
	var pants_m := _mat(pal["pants"], 0.9, 0.0, "weave")
	var boot_m := _mat(Color(0.08, 0.07, 0.06), 0.7)
	var pad_m := _mat(Color(0.12, 0.12, 0.13), 0.6, 0.2)
	var hips := _bone_attach(skel, "DEF-hips")
	Util.box(hips, Vector3(0.42, 0.3, 0.3), pants_m, Vector3(0, 0.03, 0))
	Util.box(hips, Vector3(0.44, 0.08, 0.32), _mat(Color(0.3, 0.2, 0.1), 0.8), Vector3(0, 0.16, 0))
	# 皮带扣（黄铜）
	Util.box(hips, Vector3(0.1, 0.06, 0.025), _mat(Color(0.8, 0.65, 0.3), 0.3, 0.9), Vector3(0, 0.16, 0.163))
	for side in ["L", "R"]:
		var thigh := _bone_attach(skel, "DEF-thigh." + side)
		Util.cyl(thigh, 0.11, 0.095, 0.54, pants_m, Vector3(0, -0.26, 0), 10)
		var shin := _bone_attach(skel, "DEF-shin." + side)
		Util.cyl(shin, 0.09, 0.075, 0.52, pants_m, Vector3(0, -0.25, 0), 10)
		# 护膝
		Util.box(shin, Vector3(0.17, 0.19, 0.05), pad_m, Vector3(0, -0.16, 0.082))
		var foot := _bone_attach(skel, "DEF-foot." + side)
		Util.box(foot, Vector3(0.11, 0.09, 0.27), boot_m, Vector3(0, -0.04, 0.05))

func _attach_rifle(skel: Skeleton3D) -> void:
	var hand := _bone_attach(skel, "DEF-hand.R")
	var gun := Node3D.new()
	hand.add_child(gun)
	var gun_m := _mat(Color(0.1, 0.1, 0.11), 0.45, 0.8)
	Util.box(gun, Vector3(0.07, 0.12, 0.62), gun_m, Vector3(0, 0, 0.24))
	Util.box(gun, Vector3(0.045, 0.045, 0.3), gun_m, Vector3(0, 0.02, 0.68))
	Util.box(gun, Vector3(0.06, 0.18, 0.08), gun_m, Vector3(0, -0.12, 0.16))
	Util.box(gun, Vector3(0.055, 0.11, 0.2), gun_m, Vector3(0, 0.09, 0.28))
	gun.position = Vector3(0, 0.03, 0.02)
	gun.rotation.x = -0.3

func _play_clip(clip_name: String) -> void:
	if _anim == null or clip_name == _cur_clip or not _anim.has_animation(clip_name):
		return
	_cur_clip = clip_name
	_anim.play(clip_name, 0.16)

func chest_y() -> float:
	return global_position.y + (0.4 if prone else 1.15)

func reset_player(point: Vector3, keep_weapon: bool) -> void:
	global_position = point
	vy = 0.0
	grounded = true
	prone = false
	hp_cells = int(Data.PLAYER["max_cells"])
	alive = true
	barrier = 0.0
	invuln = 0.0
	_blink = false
	if not keep_weapon:
		weapon = "N"
		rapid = false
	facing = PI
	visible = true
	_sync_visual(0.0, false, false)

func respawn_player(point: Vector3) -> void:
	reset_player(point, false)
	invuln = float(Data.PLAYER["respawn_invuln"])
	_blink = true

func take_damage(cells: int) -> bool:
	if not alive or invuln > 0.0 or barrier > 0.0:
		return false
	hp_cells -= cells
	invuln = float(Data.PLAYER["hit_invuln"])
	AudioSys.play("hurt")
	damaged.emit()
	if hp_cells <= 0:
		hp_cells = 0
		alive = false
		_cur_clip = ""
		_play_clip("Death01")
		died.emit()
	else:
		_hit_t = 0.32 # 没打死 → 受击反应片段
	return true

func heal(n: int) -> void:
	hp_cells = mini(int(Data.PLAYER["max_cells"]), hp_cells + n)

func apply_pickup(letter: String) -> void:
	AudioSys.play("pickup")
	if letter == "R":
		rapid = true
	elif letter == "B":
		barrier = 8.0
	elif letter == "+":
		heal(1)
	elif Data.WEAPONS.has(letter):
		weapon = letter

func update_player(dt: float, snap: Dictionary, level, p_aim_yaw: float, p_aim_pitch: float, aiming_or_shooting: bool) -> void:
	if not alive:
		return
	aim_pitch = p_aim_pitch
	if invuln > 0.0: invuln -= dt
	if barrier > 0.0: barrier = maxf(0.0, barrier - dt)
	_shield.visible = barrier > 0.0
	if fire_timer > 0.0: fire_timer -= dt
	if _recoil > 0.0: _recoil = maxf(0.0, _recoil - dt * 5.0)
	if _flash_t > 0.0:
		_flash_t -= dt
		var m: StandardMaterial3D = _flash.material_override
		m.albedo_color.a = maxf(0.0, _flash_t / 0.05) * 0.9
	if _blink:
		if invuln <= 0.0:
			_blink = false
			visible = true
		else:
			visible = int(Time.get_ticks_msec() / 90) % 2 == 0

	prone = bool(snap["prone"]) and grounded
	var move: Vector2 = snap["move"]
	var moving := move.length() > 0.1
	var speed := float(Data.PLAYER["walk_speed"])
	_sprinting = false
	if prone:
		speed = float(Data.PLAYER["prone_speed"])
	elif bool(snap["run"]) and not aiming_or_shooting:
		speed = float(Data.PLAYER["run_speed"])
		_sprinting = true

	var sin_y := sin(p_aim_yaw)
	var cos_y := cos(p_aim_yaw)
	var wx := move.x * -cos_y + -move.y * sin_y
	var wz := move.x * sin_y + -move.y * cos_y
	var nx := global_position.x + wx * speed * dt
	var nz := global_position.z + wz * speed * dt
	var half_w: float = level.width / 2.0 - 1.1
	nx = clampf(nx, -half_w, half_w)
	nz = clampf(nz, -level.length - 14.0, 30.0)
	var resolved := _resolve_horizontal(nx, nz, level)
	nx = resolved.x
	nz = resolved.y
	global_position.x = nx
	global_position.z = nz

	var support: float = level.get_support_y(nx, nz, global_position.y)
	if grounded:
		if bool(snap["jump"]):
			vy = float(Data.PLAYER["jump_velocity"])
			grounded = false
			_flip = 0.01
			AudioSys.play("jump")
		elif support < global_position.y - 1.5:
			grounded = false
			vy = 0.0
		else:
			global_position.y = support
	if not grounded:
		vy -= float(Data.PLAYER["gravity"]) * dt
		global_position.y += vy * dt
		if _flip > 0.0: _flip += dt * 5.2
		var s2: float = level.get_support_y(nx, nz, global_position.y)
		if global_position.y <= s2:
			global_position.y = s2
			if vy < -5.0: _land_t = 0.22 # 重落地才播落地片段
			vy = 0.0
			grounded = true
			_flip = 0.0

	if aiming_or_shooting:
		facing = p_aim_yaw
	elif moving:
		var target := atan2(wx, wz)
		var diff := target - facing
		while diff > PI: diff -= TAU
		while diff < -PI: diff += TAU
		facing += diff * minf(1.0, dt * 14.0)

	if moving and grounded:
		_walk_phase += dt * speed * 1.35
	_sync_visual(dt, moving, aiming_or_shooting)

func _resolve_horizontal(nx: float, nz: float, level) -> Vector2:
	var feet_y := global_position.y
	var body_top := feet_y + (float(Data.PLAYER["prone_height"]) if prone else float(Data.PLAYER["height"]))
	for c in level.colliders:
		if c.get("disabled", false) or c.get("no_collide", false):
			continue
		var c_bot := float(c.get("y0", 0.0))
		var c_top := c_bot + float(c.get("h", 6.0))
		if c_top <= feet_y + 0.55: continue
		if c_bot >= body_top - 0.15: continue
		if c["type"] == "box":
			var hw := float(c["w"]) / 2.0 + radius
			var hd := float(c["d"]) / 2.0 + radius
			var dx := nx - float(c["x"])
			var dz := nz - float(c["z"])
			if absf(dx) < hw and absf(dz) < hd:
				var pen_x := hw - absf(dx)
				var pen_z := hd - absf(dz)
				if pen_x < pen_z: nx = float(c["x"]) + (hw if dx >= 0 else -hw)
				else: nz = float(c["z"]) + (hd if dz >= 0 else -hd)
		elif c["type"] == "circle":
			var dx := nx - float(c["x"])
			var dz := nz - float(c["z"])
			var d2 := dx * dx + dz * dz
			var min_d := float(c["r"]) + radius
			if d2 < min_d * min_d and d2 > 0.000001:
				var d := sqrt(d2)
				nx = float(c["x"]) + dx / d * min_d
				nz = float(c["z"]) + dz / d * min_d
	return Vector2(nx, nz)

func _sync_visual(_dt: float, moving: bool, aiming: bool) -> void:
	rotation.y = facing
	# 瞄准俯仰 → 胸骨后处理（移动瞄准时上身跟随准星）
	if _aim_mod:
		var target_pitch := ((aim_pitch * 0.55) if aiming else 0.0) - _recoil * 0.13
		_aim_mod.pitch = lerpf(_aim_mod.pitch, target_pitch, 0.35)
	var clip := "Idle"
	if not grounded:
		# 跳跃自带翻跟头 → 直接播 Roll 片段（原作标志动作）；坠落播 Jump
		clip = "Roll" if _flip > 0.0 else "Jump"
		visual.rotation.x = 0.0
		visual.position.y = 0.0
	elif prone:
		clip = "Crouch_Fwd" if moving else "Crouch_Idle"
		visual.rotation.x = 1.15
		visual.position.y = -0.5
	else:
		visual.rotation.x = 0.0
		visual.position.y = 0.0
		if aiming and not moving:
			clip = "Pistol_Aim_Up" if aim_pitch > 0.22 else ("Pistol_Aim_Down" if aim_pitch < -0.22 else "Pistol_Aim_Neutral")
		elif moving:
			if aiming:
				clip = "Walk"
			elif _sprinting:
				clip = "Sprint"
			else:
				clip = "Jog_Fwd"
	# 一次性动作片段优先：受击 > 落地
	if _hit_t > 0.0: _hit_t -= _dt
	if _land_t > 0.0: _land_t -= _dt
	if grounded and not prone:
		if _hit_t > 0.0:
			clip = "Hit_Chest"
		elif _land_t > 0.0:
			clip = "Jump_Land"
	_play_clip(clip)

func muzzle_world() -> Vector3:
	var fx := sin(facing)
	var fz := cos(facing)
	return global_position + Vector3(fx * 0.55, 0.35 if prone else 1.32, fz * 0.55)

func try_shoot(projectiles, aim_point: Vector3) -> bool:
	if not alive or fire_timer > 0.0:
		return false
	var w: Dictionary = Data.WEAPONS[weapon]
	fire_timer = float(w["fire_rate"]) * (Data.RAPID_FACTOR if rapid else 1.0)
	var muzzle := muzzle_world()
	var base_dir := aim_point - muzzle
	if base_dir.length_squared() < 0.01:
		base_dir = Vector3(sin(facing), 0, cos(facing))
	base_dir = base_dir.normalized()
	var right := Vector3(-base_dir.z, 0, base_dir.x).normalized()
	var up := base_dir.cross(right).normalized()
	var pellets := int(w["pellets"])
	for i in pellets:
		var dir := base_dir
		if pellets > 1:
			var t := (float(i) / float(pellets - 1) - 0.5)
			dir += right * (t * float(w["spread"]) * 2.2)
			dir += up * (randf() - 0.5) * float(w["spread"]) * 0.4
		elif float(w["spread"]) > 0.0:
			dir += right * (randf() - 0.5) * float(w["spread"]) * 2.0
			dir += up * (randf() - 0.5) * float(w["spread"]) * 2.0
		projectiles.spawn_player_bullet(muzzle, dir.normalized(), w)
	_flash.global_position = muzzle + base_dir * 0.25
	var m: StandardMaterial3D = _flash.material_override
	m.albedo_color.a = 0.9
	_flash_t = 0.05
	_recoil = 1.0 # 后坐：胸骨短暂后仰（_sync_visual 消费）
	AudioSys.play("shoot" if weapon != "M" else "shoot_m", -4.0)
	return true

func destroy_player() -> void:
	if is_instance_valid(_flash):
		_flash.queue_free()
	queue_free()
