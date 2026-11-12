class_name ProjectileSystem
extends Node3D

## 弹丸池：玩家子弹（线段-球体命中）/ 敌方红弹（慢速可躲）/ 榴弹（抛物线+爆炸）/ 圆盘
## clear() 用代际守卫，避免命中回调链中途清表导致迭代越界（JS 版实锤过的 bug，Godot 版同样防范）

var _bullets: Array = []
var _orbs: Array = []
var _grenades: Array = []
var _fx: Array = []
var _gen := 0
var _bullet_geo: SphereMesh
var _orb_geo: SphereMesh
var _mat_cache: Dictionary = {}
var _lights: Array[OmniLight3D] = []

func _init() -> void:
	_bullet_geo = SphereMesh.new()
	_bullet_geo.radius = 0.09
	_bullet_geo.height = 0.18
	_bullet_geo.radial_segments = 8
	_bullet_geo.rings = 4
	_orb_geo = SphereMesh.new()
	_orb_geo.radius = 0.15
	_orb_geo.height = 0.3
	_orb_geo.radial_segments = 10
	_orb_geo.rings = 6
	for i in 2:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 7.0
		l.light_color = Color(1, 0.6, 0.25)
		add_child(l)
		_lights.append(l)

func _mat(color: Color) -> Material:
	if not _mat_cache.has(color):
		_mat_cache[color] = Util.glow(color, 2.4)
	return _mat_cache[color]

func spawn_player_bullet(from: Vector3, dir: Vector3, w: Dictionary) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _bullet_geo
	mesh.material_override = _mat(w["color"])
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = from
	_bullets.append({
		"mesh": mesh, "pos": from, "dir": dir,
		"speed": float(w["bullet_speed"]), "damage": int(w["damage"]),
		"pierce": bool(w["pierce"]), "wave": bool(w.get("wave", false)),
		"life": 2.2, "gen": _gen,
	})

func spawn_orb(from: Vector3, dir: Vector3, speed: float, damage: int = 1) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _orb_geo
	mesh.material_override = _mat(Color(1, 0.2, 0.15))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = from
	_orbs.append({"mesh": mesh, "pos": from, "dir": dir, "speed": speed, "damage": damage, "life": 6.0, "gen": _gen, "r": 0.15})

func spawn_disc(from: Vector3, dir: Vector3, speed: float) -> void:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.09
	cm.radial_segments = 14
	mesh.mesh = cm
	mesh.material_override = Util.glow(Color(1, 0.45, 0.15), 1.6)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = from
	_orbs.append({"mesh": mesh, "pos": from, "dir": dir, "speed": speed, "damage": 1, "life": 6.0, "gen": _gen, "r": 0.42, "disc": true})

func spawn_grenade(from: Vector3, vel: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _orb_geo
	mesh.material_override = Util.pbr(Color(0.15, 0.12, 0.1), "", 0.5, 0.5)
	add_child(mesh)
	mesh.global_position = from
	_grenades.append({"mesh": mesh, "pos": from, "vel": vel, "gen": _gen})

func spawn_explosion_fx(pos: Vector3, radius: float, color: Color = Color(1, 0.55, 0.2)) -> void:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mesh.mesh = sm
	mesh.material_override = Util.glow(color, 2.2, 0.55)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.global_position = pos
	_fx.append({"mesh": mesh, "t": 0.0, "dur": 0.38, "radius": radius})
	for l in _lights:
		if l.light_energy <= 0.0:
			l.global_position = pos
			l.light_color = color
			l.light_energy = 3.2
			break
	AudioSys.play("explosion", -6.0)

func clear_all() -> void:
	_gen += 1
	for arr in [_bullets, _orbs, _grenades]:
		for p in arr:
			if is_instance_valid(p["mesh"]):
				p["mesh"].queue_free()
		arr.clear()

func _seg_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0001:
		t = clampf((c - a).dot(ab) / len2, 0.0, 1.0)
	var p := a + ab * t
	return p.distance_squared_to(c) <= r * r

func _point_in_colliders(p: Vector3, colliders: Array) -> bool:
	for c in colliders:
		if c.get("disabled", false) or c.get("no_collide", false):
			continue
		var y0 := float(c.get("y0", 0.0))
		if p.y < y0 or p.y > y0 + float(c.get("h", 6.0)):
			continue
		if c["type"] == "box":
			if absf(p.x - float(c["x"])) <= float(c["w"]) / 2.0 and absf(p.z - float(c["z"])) <= float(c["d"]) / 2.0:
				return true
		elif c["type"] == "circle":
			var dx := p.x - float(c["x"])
			var dz := p.z - float(c["z"])
			var r := float(c["r"])
			if dx * dx + dz * dz <= r * r:
				return true
	return false

func update_projectiles(dt: float, args: Dictionary) -> void:
	var targets: Array = args["targets"]
	var colliders: Array = args["colliders"]
	var player = args["player"]
	var on_player_hit: Callable = args["on_player_hit"]
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
					if not bool(b["pierce"]):
						dead = true
					break
		if not dead and _point_in_colliders(np, colliders):
			dead = true
		if dead:
			b["mesh"].queue_free()
			_bullets.remove_at(i)
		else:
			b["mesh"].global_position = np
			if bool(b["wave"]):
				var s := 1.0 + sin(Time.get_ticks_msec() * 0.03) * 0.35
				b["mesh"].scale = Vector3(s, s, s)

	# ---- 敌方弹丸/圆盘 ----
	for i in range(_orbs.size() - 1, -1, -1):
		var o: Dictionary = _orbs[i]
		if int(o["gen"]) != gen0:
			continue
		o["life"] = float(o["life"]) - dt
		var np: Vector3 = o["pos"] + o["dir"] * float(o["speed"]) * dt
		o["pos"] = np
		var dead := float(o["life"]) <= 0.0
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
		if not dead and _point_in_colliders(np, colliders):
			dead = true
		if dead:
			o["mesh"].queue_free()
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
		var boom := false
		if np.y <= 0.15:
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
			g["mesh"].queue_free()
			_grenades.remove_at(i)

	# ---- 爆炸特效 ----
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f["t"] = float(f["t"]) + dt
		var k := float(f["t"]) / float(f["dur"])
		if k >= 1.0:
			f["mesh"].queue_free()
			_fx.remove_at(i)
		else:
			var s := lerpf(0.3, float(f["radius"]), k)
			f["mesh"].scale = Vector3(s, s, s)
			var m: StandardMaterial3D = f["mesh"].material_override
			m.albedo_color.a = 0.55 * (1.0 - k)
	for l in _lights:
		if l.light_energy > 0.0:
			l.light_energy = maxf(0.0, l.light_energy - dt * 14.0)

func destroy_all() -> void:
	clear_all()
	for f in _fx:
		if is_instance_valid(f["mesh"]):
			f["mesh"].queue_free()
	_fx.clear()
