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
var death_pos := Vector3.ZERO # 阵亡点：原地复活的落点（主循环按地形修正高度后使用）

var _blink := false
var _walk_phase := 0.0
var _flip := 0.0
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
var _move_dir := Vector2(0, -1) # 实际行进方向（世界 XZ 单位向量）
var _move_speed := 0.0 # 实际水平速度（m/s，驱动动画选片与倍速，防滑步）
var _hip_yaw := 0.0 # 瞄准移动时髋部偏航（脚朝行进方向、上身对准星）
var _speed_scale := 1.0

static var _char_scenes: Dictionary = {} # char_id -> PackedScene（bill.glb / lance.glb，MPFB 高模）

func _init() -> void:
	hp_cells = int(Data.PLAYER["max_cells"])

func setup(char_id: String) -> void:
	_char_id = char_id
	_build_mesh()

func _mat(c: Color, rough: float = 0.8, metal: float = 0.0, tex: String = "") -> StandardMaterial3D:
	return Util.pbr(c, tex, rough, metal)

func _build_mesh() -> void:
	visual = Node3D.new()
	add_child(visual)
	# 高模自带真实贴图与造型件（头巾/子弹带等已烘进 GLB），不再覆写材质、不再拼 primitive 挂件
	if not _char_scenes.has(_char_id):
		_char_scenes[_char_id] = load("res://assets/char/" + _char_id + ".glb")
	_model = (_char_scenes[_char_id] as PackedScene).instantiate() as Node3D
	visual.add_child(_model)
	_anim = _find_anim(_model)
	if _anim:
		for n in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Pistol_Idle", "Pistol_Aim_Up", "Pistol_Aim_Neutral", "Pistol_Aim_Down", "Swim_Idle"]:
			if _anim.has_animation(n):
				_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var skel := _find_skel(_model)
	if skel:
		_aim_mod = AimModifier.new()
		skel.add_child(_aim_mod)
		_attach_rifle(skel)
	_play_clip("Idle")

	# 防护罩
	_shield = Util.sph(self, 1.3, Util.flat(Color(0.4, 0.8, 1, 0.20)), Vector3(0, 1.0, 0), 18, 12)
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	# 枪口火光改走 projectiles 的贴图面片池（spawn_muzzle_flash，带瞬时点光），旧发光球已拆除

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

## 挂件坐标约定（attach_diag.gd 实证）：本 rig 骨骼本地 +Y 恒指向子关节——
## 头/脊柱往上、腿往膝踝、手臂往肘腕，全是要 +Y；脸朝 +Z。别再按「-Y 朝下肢末端」写偏移。
func _bone_attach(skel: Skeleton3D, bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	return ba

static var _m4a1_scene: PackedScene = null

## Mixamo GLB 的单位缩放（≈0.01）挂在 Skeleton3D 的父节点上，骨骼挂件会被同比例压缩，
## 挂枪时按父节点缩放反向补偿，枪的实际尺寸才回到米制（集成实测教训）
static func attach_scale_comp(skel: Skeleton3D) -> float:
	var p := skel.get_parent() as Node3D
	if p:
		var s := p.transform.basis.get_scale().x
		if s > 0.0001:
			return 1.0 / s
	return 1.0

func _attach_rifle(skel: Skeleton3D) -> void:
	var hand := _bone_attach(skel, "hand_r")
	var gun := Node3D.new()
	hand.add_child(gun)
	gun.scale = Vector3.ONE * attach_scale_comp(skel)
	# 主角枪（定案）：带贴图 M4A1（nisu / OpenGameArt / CC0），原生 0.84m、枪身沿 +Z、原点近机匣
	if _m4a1_scene == null:
		_m4a1_scene = load("res://assets/weapons/m4a1.glb")
	gun.add_child(_m4a1_scene.instantiate())
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
		death_pos = global_position
		alive = false
		_cur_clip = ""
		_play_clip("Death01")
		if _anim:
			_anim.speed_scale = 1.0 # 死亡片段必须正放（后撤倒放倍速不能带进来）
		if _aim_mod:
			_aim_mod.hip_yaw = 0.0
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
	var prev_xz := Vector2(global_position.x, global_position.z)
	aim_pitch = p_aim_pitch
	if invuln > 0.0: invuln -= dt
	if barrier > 0.0: barrier = maxf(0.0, barrier - dt)
	_shield.visible = barrier > 0.0
	if fire_timer > 0.0: fire_timer -= dt
	if _recoil > 0.0: _recoil = maxf(0.0, _recoil - dt * 5.0)
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
	# 开放版边界：可活动范围收到山脊内侧（山坡爬得上，硬界在脊外，由地形隆起自然围住）
	var half_w: float = level.width / 2.0 - 14.0
	nx = clampf(nx, -half_w, half_w)
	nz = clampf(nz, -level.length + 2.0, 30.0)
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
	# 实测位移 → 行进方向与速度（动画选片/倍速按真实速度，脚步不打滑）
	if dt > 0.0001:
		var disp := Vector2(global_position.x, global_position.z) - prev_xz
		var inst := disp.length() / dt
		if inst > 0.4:
			_move_dir = disp / disp.length()
			_move_speed = lerpf(_move_speed, inst, 0.55)
		else:
			_move_speed = lerpf(_move_speed, 0.0, 0.45)
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
		if not grounded or prone:
			_hip_yaw = lerpf(_hip_yaw, 0.0, minf(1.0, _dt * 13.0))
			_aim_mod.hip_yaw = _hip_yaw
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
		_speed_scale = 1.0
		var hip_target := 0.0
		if aiming and not moving:
			clip = "Pistol_Aim_Up" if aim_pitch > 0.22 else ("Pistol_Aim_Down" if aim_pitch < -0.22 else "Pistol_Aim_Neutral")
		elif moving:
			if aiming:
				# 瞄准移动：髋朝行进方向（脚不横滑）、上身仍对准星；大角度后退用倒放近似后撤步
				var rel := wrapf(atan2(_move_dir.x, _move_dir.y) - facing, -PI, PI)
				hip_target = clampf(rel, -0.9, 0.9)
				clip = "Walk"
				var base := clampf(_move_speed / 2.1, 0.5, 2.4)
				_speed_scale = -base if absf(rel) > 2.0 else base
			elif _move_speed > 9.0:
				clip = "Sprint"
				_speed_scale = clampf(_move_speed / 6.8, 0.7, 2.2)
			elif _move_speed > 3.4:
				clip = "Jog_Fwd"
				_speed_scale = clampf(_move_speed / 4.6, 0.7, 2.2)
			else:
				clip = "Walk"
				_speed_scale = clampf(_move_speed / 2.1, 0.5, 1.8)
		_hip_yaw = lerpf(_hip_yaw, hip_target, minf(1.0, _dt * 13.0))
		if _aim_mod:
			_aim_mod.hip_yaw = _hip_yaw
	# 一次性动作片段优先：受击 > 落地
	if _hit_t > 0.0: _hit_t -= _dt
	if _land_t > 0.0: _land_t -= _dt
	if grounded and not prone:
		if _hit_t > 0.0:
			clip = "Hit_Chest"
			_speed_scale = 1.0
		elif _land_t > 0.0:
			clip = "Jump_Land"
			_speed_scale = 1.0
	_play_clip(clip)
	if _anim:
		_anim.speed_scale = _speed_scale

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
	# 开火反馈：枪口火光面片（带点光）+ 向右抛出弹壳（每开一枪一壳，散射枪按发计）
	projectiles.spawn_muzzle_flash(muzzle + base_dir * 0.3, base_dir, 1.0, true)
	projectiles.spawn_shell(muzzle - base_dir * 0.18 + right * 0.12 + Vector3(0, 0.04, 0), right)
	_recoil = 1.0 # 后坐：胸骨短暂后仰（_sync_visual 消费）
	AudioSys.play("shoot" if weapon != "M" else "shoot_m", -4.0)
	return true

func destroy_player() -> void:
	queue_free()
