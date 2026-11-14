class_name CameraRig
extends RefCounted

## GTA 式越肩镜头：右肩偏移、俯仰瞄准、开镜收紧、撞墙回收、阻尼平滑
## 准星射线优先命中敌人球体，否则取远点——子弹从枪口向该点收敛（保证不从敌人头顶漏过）

var camera: Camera3D
var aim_point := Vector3.ZERO
var shake := 0.0 # 受击震屏强度（主循环置 1，每帧衰减）
var _pos := Vector3(0, 3, 38)
var _dist := 5.2
var _fov := 70.0

func _init(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 600.0

func snap_to(anchor_pos: Vector3, yaw: float, pitch: float) -> void:
	var a := anchor_pos + Vector3(0, Data.CAMERA["target_height"], 0)
	_pos = _desired(a, yaw, pitch, false)
	_dist = Data.CAMERA["distance"]
	_apply(a, yaw, pitch)

func _desired(anchor: Vector3, yaw: float, pitch: float, aiming: bool) -> Vector3:
	var dist := float(Data.CAMERA["aim_distance"] if aiming else Data.CAMERA["distance"])
	_dist = dist
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(-cos(yaw), 0, sin(yaw))
	var p := anchor - f * (dist * cos(pitch)) + Vector3(0, -dist * sin(pitch) + float(Data.CAMERA["height"]), 0) + right * float(Data.CAMERA["shoulder"])
	return p

func update_rig(dt: float, args: Dictionary) -> void:
	var anchor_pos: Vector3 = args["anchor"]
	var yaw: float = args["yaw"]
	var pitch: float = args["pitch"]
	var aiming: bool = args["aiming"]
	var colliders: Array = args["colliders"]
	var col_at: Callable = args.get("colliders_at", Callable()) # 1.2.1 空间索引点查询（缺失回退全表）
	var targets: Array = args["targets"]
	var th := float(Data.CAMERA["target_height_prone"] if args.get("prone", false) else Data.CAMERA["target_height"])
	var anchor := anchor_pos + Vector3(0, th, 0)
	var desired := _desired(anchor, yaw, pitch, aiming)
	# 撞墙回收：沿锚点→期望位置步进采样，遇碰撞盒提前停
	var pad := float(Data.CAMERA["collision_pad"])
	var steps := 14
	var ok := desired
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p: Vector3 = anchor.lerp(desired, t)
		if _inside_any(p, col_at.call(p.x, p.z) if col_at.is_valid() else colliders, pad):
			ok = anchor.lerp(desired, float(i - 1) / steps)
			break
		ok = p
	var k := 1.0 - exp(-float(Data.CAMERA["smooth"]) * dt)
	_pos = _pos.lerp(ok, k)
	_apply(anchor, yaw, pitch)
	# 受击震屏：位置小幅抖动 + 轻微滚转，快速衰减（疼但不晕）
	if shake > 0.003:
		shake = maxf(0.0, shake - dt * 2.2)
		camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.13 * shake
		camera.rotation.z += randf_range(-1.0, 1.0) * 0.018 * shake
	# 准星射线
	var look_dir := (aim_point_hint(anchor, yaw, pitch) - _pos)
	_update_aim(look_dir, targets)
	# FOV 开镜收紧
	var target_fov := 58.0 if aiming else 70.0
	_fov = lerpf(_fov, target_fov, minf(1.0, dt * 10.0))
	camera.fov = _fov

func aim_point_hint(anchor: Vector3, yaw: float, pitch: float) -> Vector3:
	var f := Vector3(sin(yaw), 0, cos(yaw))
	return anchor + f * (40.0 * cos(pitch)) + Vector3(0, 40.0 * sin(pitch) + 0.3, 0)

func _apply(anchor: Vector3, yaw: float, pitch: float) -> void:
	camera.global_position = _pos
	var target := aim_point_hint(anchor, yaw, pitch)
	if (_pos - target).length() > 0.01:
		camera.look_at(target, Vector3.UP)

func _inside_any(p: Vector3, colliders: Array, pad: float) -> bool:
	for c in colliders:
		if c.get("disabled", false):
			continue
		if c["type"] != "box":
			continue
		var y0 := float(c.get("y0", 0.0))
		if p.y < y0 - pad or p.y > y0 + float(c.get("h", 6.0)) + pad:
			continue
		if absf(p.x - float(c["x"])) < float(c["w"]) / 2.0 + pad and absf(p.z - float(c["z"])) < float(c["d"]) / 2.0 + pad:
			return true
	return false

func _update_aim(look_dir: Vector3, targets: Array) -> void:
	var dir := look_dir.normalized()
	var best_t := 120.0
	var found := false
	for t in targets:
		if not t.alive or t.get("targetable") == false:
			continue
		var c := Vector3(t.hit_x, t.hit_y, t.hit_z)
		var oc := c - _pos
		var tca := oc.dot(dir)
		if tca < 0.0:
			continue
		var d2 := oc.length_squared() - tca * tca
		var r := float(t.hit_r)
		if d2 > r * r:
			continue
		var tt := tca - sqrt(maxf(0.0, r * r - d2))
		if tt < best_t:
			best_t = tt
			found = true
	if found:
		aim_point = _pos + dir * best_t
	else:
		aim_point = _pos + dir * 80.0
