class_name Player
extends Node3D

## 玩家 Bill/Lance —— 原作复原造型（红头巾/背心或裸上身/蓝或红裤），关节枢轴动画
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
var _hip_l: Node3D
var _hip_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: Node3D
var _shield: MeshInstance3D
var _flash: MeshInstance3D
var _gun_tip: Node3D

func _init() -> void:
	hp_cells = int(Data.PLAYER["max_cells"])

func setup(char_id: String) -> void:
	_char_id = char_id
	_build_mesh()

func _mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	return Util.pbr(c, "", rough, metal)

func _build_mesh() -> void:
	var pal: Dictionary = Data.CHARACTERS[_char_id]
	var skin := _mat(Color(0.83, 0.62, 0.44), 0.55)
	var pants := _mat(pal["pants"], 0.9)
	var top := _mat(pal["top"], 0.9)
	var band := _mat(pal["bandana"], 0.85)
	var hair_m := _mat(pal["hair"], 0.95)
	var boot := _mat(Color(0.08, 0.07, 0.06), 0.7)
	var gun_m := _mat(Color(0.1, 0.1, 0.11), 0.45, 0.8)

	visual = Node3D.new()
	add_child(visual)

	# ---- 腿（髋枢轴）----
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.15 * side, 0.98, 0)
		visual.add_child(hip)
		var leg := Util.capsule(hip, 0.115, 0.92, pants, Vector3(0, -0.44, 0))
		leg.scale = Vector3(1.15, 1, 1.15)
		Util.box(hip, Vector3(0.17, 0.12, 0.3), boot, Vector3(0, -0.93, 0.05))
		if side < 0: _hip_l = hip
		else: _hip_r = hip
	# 骨盆
	Util.box(visual, Vector3(0.46, 0.24, 0.3), pants, Vector3(0, 1.04, 0))
	Util.box(visual, Vector3(0.48, 0.09, 0.32), _mat(Color(0.3, 0.2, 0.1), 0.8), Vector3(0, 1.14, 0)) # 皮带

	# ---- 躯干（壮实：胸肌+腹肌分层）----
	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.12, 0)
	visual.add_child(_torso)
	var chest_mat: Material = top if not pal["bare_chest"] else skin
	var chest := Util.cyl(_torso, 0.30, 0.215, 0.52, chest_mat, Vector3(0, 0.30, 0), 14)
	chest.scale = Vector3(1.25, 1, 0.82)
	var pecs := Util.sph(_torso, 0.21, chest_mat, Vector3(0, 0.44, 0.05))
	pecs.scale = Vector3(1.55, 0.95, 0.85)
	Util.cyl(_torso, 0.20, 0.185, 0.2, skin if not pal["bare_chest"] else chest_mat, Vector3(0, 0.02, 0), 12)
	if pal["bare_chest"]:
		# 兰斯：斜挎子弹带（兰博标志）
		var strap := Util.box(_torso, Vector3(0.5, 0.09, 0.36), _mat(Color(0.25, 0.18, 0.1), 0.85), Vector3(0, 0.34, 0))
		strap.rotation.z = 0.6
	else:
		# 比尔白背心肩带
		Util.box(_torso, Vector3(0.13, 0.2, 0.3), top, Vector3(-0.2, 0.52, 0))
		Util.box(_torso, Vector3(0.13, 0.2, 0.3), top, Vector3(0.2, 0.52, 0))

	# ---- 手臂（肩枢轴）----
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.40 * side, 1.52, 0)
		visual.add_child(sh)
		var arm := Util.capsule(sh, 0.095, 0.8, skin, Vector3(0, -0.36, 0))
		arm.scale = Vector3(1.2, 1, 1.2)
		Util.sph(sh, 0.085, skin, Vector3(0, -0.74, 0))
		if side < 0: _arm_l = sh
		else: _arm_r = sh
	# ---- 枪（挂右手）----
	var gun := Node3D.new()
	gun.position = Vector3(0, -0.74, 0.08)
	_arm_r.add_child(gun)
	Util.box(gun, Vector3(0.09, 0.14, 0.66), gun_m, Vector3(0, 0, 0.26))
	Util.box(gun, Vector3(0.05, 0.05, 0.34), gun_m, Vector3(0, 0.03, 0.72))
	Util.box(gun, Vector3(0.07, 0.2, 0.09), gun_m, Vector3(0, -0.13, 0.18))
	Util.box(gun, Vector3(0.06, 0.12, 0.22), gun_m, Vector3(0, 0.1, 0.3))
	_gun_tip = Node3D.new()
	_gun_tip.position = Vector3(0, 0.03, 0.92)
	gun.add_child(_gun_tip)

	# ---- 头 ----
	var head_p := Node3D.new()
	head_p.position = Vector3(0, 1.60, 0)
	visual.add_child(head_p)
	Util.sph(head_p, 0.145, skin, Vector3(0, 0.15, 0))
	var hair := Util.sph(head_p, 0.15, hair_m, Vector3(0, 0.185, -0.015))
	hair.scale = Vector3(1, 0.82, 1)
	if pal["long_hair"]:
		var back := Util.box(head_p, Vector3(0.26, 0.34, 0.08), hair_m, Vector3(0, 0.02, -0.13))
		back.rotation.x = 0.15
	# 红头巾：环 + 后飘尾
	var bandana := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.115
	tm.outer_radius = 0.165
	bandana.mesh = tm
	bandana.material_override = band
	bandana.position = Vector3(0, 0.235, 0)
	bandana.rotation.x = PI / 2.0
	head_p.add_child(bandana)
	Util.box(head_p, Vector3(0.09, 0.3, 0.03), band, Vector3(0.09, 0.1, -0.17))

	# 防护罩
	_shield = Util.sph(self, 1.3, Util.flat(Color(0.4, 0.8, 1, 0.20)), Vector3(0, 1.0, 0), 18, 12)
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	# 枪口闪光（独立于 visual，避免翻滚影响）
	_flash = Util.sph(get_parent() if get_parent() else self, 0.17, Util.glow(Color(1, 0.8, 0.35), 3.0, 0.0), Vector3.ZERO, 8, 6)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
		died.emit()
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
	if prone:
		speed = float(Data.PLAYER["prone_speed"])
	elif bool(snap["run"]) and not aiming_or_shooting:
		speed = float(Data.PLAYER["run_speed"])

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

func _sync_visual(dt: float, moving: bool, aiming: bool) -> void:
	rotation.y = facing
	if not grounded and _flip > 0.0:
		visual.rotation.x = -minf(_flip, 1.0) * TAU
		visual.position.y = 0.0
	elif prone:
		visual.rotation.x = 1.25
		visual.position.y = -0.55
	else:
		visual.rotation.x = 0.0
		visual.position.y = absf(sin(_walk_phase)) * 0.07 if (moving and grounded) else 0.0
	var swing := sin(_walk_phase) * 0.62 if (moving and grounded and not prone) else 0.0
	_hip_l.rotation.x = swing
	_hip_r.rotation.x = -swing
	if aiming:
		_arm_r.rotation.x = -PI / 2.0 - aim_pitch
		_arm_l.rotation.x = -PI / 2.0 - aim_pitch + 0.12
		_arm_l.rotation.y = -0.35
		_torso.rotation.x = -aim_pitch * 0.28
	else:
		_arm_r.rotation.x = -swing * 0.7
		_arm_l.rotation.x = swing * 0.7
		_arm_l.rotation.y = 0.0
		_torso.rotation.x = 0.0

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
	AudioSys.play("shoot" if weapon != "M" else "shoot_m", -4.0)
	return true

func destroy_player() -> void:
	if is_instance_valid(_flash):
		_flash.queue_free()
	queue_free()
