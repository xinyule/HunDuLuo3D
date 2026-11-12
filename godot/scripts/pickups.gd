class_name PickupSystem
extends Node3D

## 飞鹰徽章 + 武器胶囊（原作系统：打下飞鹰→掉字母胶囊→换枪 M/F/L/S/R/B/+）
## 鹰徽目标与敌人共用可击接口

class FalconTarget:
	extends RefCounted
	var alive := true
	var targetable := true
	var hit_x := 0.0
	var hit_y := 0.0
	var hit_z := 0.0
	var hit_r := 0.95
	var owner: PickupSystem
	func on_hit(_dmg: int, _point: Vector3 = Vector3.ZERO) -> void:
		if owner:
			owner._falcon_hit(self)

var _ctx: Dictionary
var _falcons: Array = []
var _letters: Array = []

func setup(ctx: Dictionary) -> void:
	_ctx = ctx

func spawn_falcon(z: float, letter: String, half_width: float) -> void:
	var g := Node3D.new()
	var gold := Util.pbr(Color(0.85, 0.63, 0.13), "", 0.35, 0.85)
	var red := Util.pbr(Color(0.7, 0.12, 0.1), "", 0.5, 0.3)
	var body := Util.sph(g, 0.42, gold, Vector3.ZERO, 12, 9)
	body.scale = Vector3(1.25, 0.8, 1.6)
	Util.sph(g, 0.2, red, Vector3(0, 0.18, 0.62), 8, 6)
	var wings: Array = []
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.25 * sx, 0.1, 0)
		g.add_child(pivot)
		var wing := Util.box(pivot, Vector3(1.5, 0.07, 0.55), gold, Vector3(0.8 * sx, 0, -0.05))
		wing.rotation.y = -0.25 * sx
		wings.append(pivot)
	add_child(g)
	var target := FalconTarget.new()
	target.owner = self
	g.position = Vector3(-half_width - 7.0, 6.5, z)
	_falcons.append({"group": g, "target": target, "letter": letter, "wings": wings, "t": 0.0, "speed": 6.5, "dir": 1.0, "half": half_width})

func get_falcon_target():
	for f in _falcons:
		if f["target"].alive:
			return f["target"]
	return null

func _falcon_hit(target: FalconTarget) -> void:
	for i in _falcons.size():
		var f: Dictionary = _falcons[i]
		if f["target"] == target:
			target.alive = false
			var gp: Vector3 = f["group"].global_position
			_ctx["on_score"].call(100)
			spawn_letter(gp.x, gp.y, gp.z, f["letter"])
			f["group"].queue_free()
			_falcons.remove_at(i)
			AudioSys.play("pickup", -4.0)
			return

func spawn_letter(x: float, y: float, z: float, letter: String) -> void:
	_make_letter(Vector3(x, y, z), letter, 0.0)

func spawn_heal(x: float, z: float, ground_y: float = 0.0) -> void:
	_make_letter(Vector3(x, ground_y + 1.2, z), "+", ground_y)

func _make_letter(pos: Vector3, letter: String, floor_y: float) -> void:
	var g := Node3D.new()
	var is_heal := letter == "+"
	var cap_m := Util.pbr(Color(0.16, 0.6, 0.25) if is_heal else Color(0.75, 0.16, 0.12), "", 0.4, 0.4)
	var cap := Util.capsule(g, 0.34, 0.85, cap_m, Vector3.ZERO)
	cap.rotation.z = PI / 2.0
	if is_heal:
		var white := Util.pbr(Color(0.95, 0.95, 0.95), "", 0.5)
		Util.box(g, Vector3(0.4, 0.13, 0.1), white, Vector3(0, 0, 0.3))
		Util.box(g, Vector3(0.13, 0.4, 0.1), white, Vector3(0, 0, 0.3))
	else:
		var label := Label3D.new()
		label.text = letter
		label.font_size = 128
		label.pixel_size = 0.006
		label.modulate = Color(1, 0.95, 0.8)
		label.outline_size = 12
		label.outline_modulate = Color(0.2, 0.05, 0.02)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 0.05, 0.1)
		g.add_child(label)
	add_child(g)
	g.position = pos
	_letters.append({"group": g, "letter": letter, "vy": 0.0, "landed": false, "floor": floor_y, "t": randf() * 6.0})

func update_pickups(dt: float, player, level) -> void:
	for i in range(_falcons.size() - 1, -1, -1):
		var f: Dictionary = _falcons[i]
		f["t"] = float(f["t"]) + dt
		var g: Node3D = f["group"]
		g.position.x += float(f["speed"]) * float(f["dir"]) * dt
		g.position.y = 6.5 + sin(float(f["t"]) * 3.0) * 0.3
		for wi in f["wings"].size():
			(f["wings"][wi] as Node3D).rotation.z = sin(float(f["t"]) * 10.0) * 0.45 * (1.0 if wi == 1 else -1.0)
		var tg: FalconTarget = f["target"]
		tg.hit_x = g.position.x
		tg.hit_y = g.position.y
		tg.hit_z = g.position.z
		if absf(g.position.x) > float(f["half"]) + 9.0:
			tg.alive = false
			g.queue_free()
			_falcons.remove_at(i)
	for i in range(_letters.size() - 1, -1, -1):
		var l: Dictionary = _letters[i]
		var g: Node3D = l["group"]
		l["t"] = float(l["t"]) + dt
		if not bool(l["landed"]):
			l["vy"] = float(l["vy"]) - 12.0 * dt
			g.position.y += float(l["vy"]) * dt
			var support: float = level.get_support_y(g.position.x, g.position.z, g.position.y + 2.0)
			var floor_y := maxf(support, float(l["floor"]))
			if g.position.y <= floor_y + 0.55:
				g.position.y = floor_y + 0.55
				l["landed"] = true
		else:
			g.position.y += sin(float(l["t"]) * 2.6) * dt * 0.25
			g.rotation.y += dt * 1.8
		if player != null and player.alive:
			var pp: Vector3 = player.global_position
			var dx := g.position.x - pp.x
			var dz := g.position.z - pp.z
			if dx * dx + dz * dz < 1.7 and absf(g.position.y - (pp.y + 0.8)) < 1.6:
				_ctx["on_pickup"].call(l["letter"])
				g.queue_free()
				_letters.remove_at(i)

func destroy_all() -> void:
	for f in _falcons:
		(f["group"] as Node3D).queue_free()
	for l in _letters:
		(l["group"] as Node3D).queue_free()
	_falcons.clear()
	_letters.clear()
