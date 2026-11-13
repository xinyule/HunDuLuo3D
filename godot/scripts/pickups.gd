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
var _emblems: Array = []
var _floats: Array = []

## 隐藏鹰徽存档：与主存档同一文件（progress 段 emblems_<关号> 位掩码）。
## 主线 _save_hi() 用全新 ConfigFile 整表重写、会抹掉未知键——拾取时在这里先 load 再写穿，
## 并以 static 内存掩码为会话权威（合并钩子见 内容B进度.md：_save_hi 应保留未知键）。
const EMBLEM_SAVE := "user://contra3d_save.cfg"
static var _emblem_masks: Dictionary = {}
static var _emblem_masks_loaded := false

static func _emblem_load() -> void:
	if _emblem_masks_loaded:
		return
	_emblem_masks_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(EMBLEM_SAVE) == OK:
		for i in 8:
			_emblem_masks[i] = int(cfg.get_value("progress", "emblems_%d" % i, 0))

static func _emblem_store() -> void:
	var cfg := ConfigFile.new()
	cfg.load(EMBLEM_SAVE) # 先读现档再改自己的键，不动其它段/键
	for k in _emblem_masks:
		cfg.set_value("progress", "emblems_%d" % int(k), int(_emblem_masks[k]))
	cfg.save(EMBLEM_SAVE)

func is_emblem_collected(lv: int, slot: int) -> bool:
	_emblem_load()
	return (int(_emblem_masks.get(lv, 0)) >> slot) & 1 == 1

func emblem_total(lv: int) -> int:
	_emblem_load()
	var m := int(_emblem_masks.get(lv, 0))
	var c := 0
	for i in 3:
		c += (m >> i) & 1
	return c

func setup(ctx: Dictionary) -> void:
	_ctx = ctx

func spawn_falcon(z: float, letter: String, half_width: float) -> void:
	# 内容批重做：机械金鹰——流线金身 + 深色胸甲 + 红发光核心 + 金喙红眼冠羽，
	# 双翼三段（翼根枢轴 + 中段滞后补角枢轴 + 四根扇形尖羽）+ 三片尾羽扇。
	# （曾检索 Poly Pizza 的 CC-BY 金鹰 GLB，文本通道拿不到静态直链，按派工口径走程序重拼。）
	var g := Node3D.new()
	var gold := Util.pbr(Color(0.78, 0.58, 0.14), "", 0.32, 0.85)
	var gold_dark := Util.pbr(Color(0.52, 0.38, 0.1), "", 0.45, 0.8)
	var bright := Util.pbr(Color(0.95, 0.74, 0.24), "", 0.25, 0.9)
	var body := Util.sph(g, 0.34, gold, Vector3.ZERO, 14, 10)
	body.scale = Vector3(0.95, 0.8, 1.9)
	var chest := Util.sph(g, 0.29, gold_dark, Vector3(0, -0.05, 0.2), 12, 9)
	chest.scale = Vector3(0.92, 0.78, 1.25)
	var core := Util.sph(g, 0.13, Util.glow(Color(1, 0.22, 0.12), 2.4), Vector3(0, -0.1, 0.55), 10, 8)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Util.sph(g, 0.185, gold, Vector3(0, 0.14, 0.68), 12, 9)
	var beak := Util.cyl(g, 0.012, 0.07, 0.27, bright, Vector3(0, 0.1, 0.88), 8)
	beak.rotation.x = PI / 2.0
	for sx in [-1.0, 1.0]:
		var eye := Util.sph(g, 0.03, Util.glow(Color(1, 0.25, 0.15), 2.0), Vector3(0.088 * sx, 0.19, 0.8), 6, 5)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ci in 3:
		var crest := Util.box(g, Vector3(0.05, 0.15, 0.3), gold_dark, Vector3(0, 0.3 - float(ci) * 0.02, 0.6 - float(ci) * 0.09))
		crest.rotation.x = -0.55
	for ti in 3:
		var tail := Util.box(g, Vector3(0.17, 0.035, 0.52), gold_dark, Vector3(0, -0.02, -0.78))
		tail.rotation.y = (float(ti) - 1.0) * 0.28
	var wings: Array = []
	var mids: Array = []
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.17 * sx, 0.1, 0.02)
		g.add_child(pivot)
		var inner := Util.box(pivot, Vector3(0.98, 0.055, 0.54), gold, Vector3(0.52 * sx, 0, -0.03))
		inner.rotation.y = -0.16 * sx
		var mid := Node3D.new()
		mid.position = Vector3(1.0 * sx, 0, -0.12)
		pivot.add_child(mid)
		var midw := Util.box(mid, Vector3(0.82, 0.045, 0.4), gold_dark, Vector3(0.4 * sx, 0, -0.04))
		midw.rotation.y = -0.3 * sx
		for fi in 4:
			var feather := Util.box(mid, Vector3(0.4, 0.03, 0.085), bright, Vector3((0.78 + float(fi) * 0.045) * sx, 0, 0.16 - float(fi) * 0.11))
			feather.rotation.y = (0.34 - float(fi) * 0.17) * sx
		wings.append(pivot)
		mids.append(mid)
	add_child(g)
	var target := FalconTarget.new()
	target.owner = self
	g.position = Vector3(-half_width - 7.0, 8.0, z)
	_falcons.append({"group": g, "target": target, "letter": letter, "wings": wings, "mids": mids, "t": 0.0, "speed": 6.5, "dir": 1.0, "half": half_width})

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

## 隐藏鹰徽：深铜圆盘 + 金环 + 鹰形浮雕（身/头/喙/三段翼/尾羽），自旋浮动，走近拾取
func spawn_emblem(pos: Vector3, lv: int, slot: int) -> void:
	var g := Node3D.new()
	var bronze := Util.pbr(Color(0.45, 0.3, 0.12), "", 0.42, 0.85)
	var gold := Util.pbr(Color(0.85, 0.63, 0.13), "", 0.3, 0.9)
	var bright := Util.pbr(Color(0.98, 0.8, 0.3), "", 0.22, 0.95)
	var ring := Util.cyl(g, 0.5, 0.5, 0.05, gold, Vector3.ZERO, 20)
	ring.rotation.x = PI / 2.0
	var disc := Util.cyl(g, 0.46, 0.46, 0.1, bronze, Vector3.ZERO, 20)
	disc.rotation.x = PI / 2.0
	Util.box(g, Vector3(0.16, 0.34, 0.07), bright, Vector3(0, -0.02, 0.07))
	Util.sph(g, 0.085, bright, Vector3(0, 0.22, 0.07), 8, 6)
	var beak := Util.cyl(g, 0.01, 0.04, 0.11, bright, Vector3(0, 0.2, 0.13), 6)
	beak.rotation.x = PI / 2.0
	for sx in [-1.0, 1.0]:
		var w1 := Util.box(g, Vector3(0.3, 0.09, 0.06), bright, Vector3(0.22 * sx, 0.1, 0.07))
		w1.rotation.z = 0.5 * sx
		var w2 := Util.box(g, Vector3(0.26, 0.07, 0.06), bright, Vector3(0.36 * sx, 0.2, 0.07))
		w2.rotation.z = 0.85 * sx
		var w3 := Util.box(g, Vector3(0.2, 0.055, 0.06), bright, Vector3(0.46 * sx, 0.3, 0.07))
		w3.rotation.z = 1.15 * sx
	for ti in 3:
		var tf := Util.box(g, Vector3(0.09, 0.17, 0.06), bright, Vector3((float(ti) - 1.0) * 0.08, -0.26, 0.07))
		tf.rotation.z = (float(ti) - 1.0) * 0.3
	Util.sph(g, 0.12, gold, Vector3(0, 0, -0.07), 8, 6)
	var halo_m := StandardMaterial3D.new()
	halo_m.albedo_color = Color(1, 0.85, 0.3, 0.16)
	halo_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var halo := MeshInstance3D.new()
	var hp := PlaneMesh.new()
	hp.size = Vector2(1.7, 1.7)
	halo.mesh = hp
	halo.material_override = halo_m
	halo.position = Vector3(0, -0.55, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(halo)
	add_child(g)
	g.position = pos
	_emblems.append({"group": g, "lv": lv, "slot": slot, "t": randf() * 6.0, "base_y": pos.y})

func _collect_emblem(i: int) -> void:
	var e: Dictionary = _emblems[i]
	var lv := int(e["lv"])
	var slot := int(e["slot"])
	_emblem_load()
	_emblem_masks[lv] = int(_emblem_masks.get(lv, 0)) | (1 << slot)
	_emblem_store()
	_ctx["on_score"].call(300)
	AudioSys.play("pickup", -2.0)
	var lab := Label3D.new()
	lab.text = "隐藏鹰徽 %d/3" % emblem_total(lv)
	lab.font_size = 110
	lab.pixel_size = 0.008
	lab.modulate = Color(1, 0.88, 0.4)
	lab.outline_size = 10
	lab.outline_modulate = Color(0.25, 0.15, 0.02)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = (e["group"] as Node3D).global_position + Vector3(0, 0.5, 0)
	add_child(lab)
	_floats.append({"label": lab, "t": 0.0})
	(e["group"] as Node3D).queue_free()
	_emblems.remove_at(i)

func update_pickups(dt: float, player, level) -> void:
	for i in range(_falcons.size() - 1, -1, -1):
		var f: Dictionary = _falcons[i]
		f["t"] = float(f["t"]) + dt
		var g: Node3D = f["group"]
		g.position.x += float(f["speed"]) * float(f["dir"]) * dt
		g.position.y = 8.0 + sin(float(f["t"]) * 3.0) * 0.3
		for wi in f["wings"].size():
			(f["wings"][wi] as Node3D).rotation.z = sin(float(f["t"]) * 10.0) * 0.45 * (1.0 if wi == 1 else -1.0)
		if f.has("mids"):
			for mi in f["mids"].size():
				(f["mids"][mi] as Node3D).rotation.z = sin(float(f["t"]) * 10.0 - 0.55) * 0.3 * (1.0 if mi == 1 else -1.0)
		var tg: FalconTarget = f["target"]
		tg.hit_x = g.position.x
		tg.hit_y = g.position.y
		tg.hit_z = g.position.z
		if absf(g.position.x) > float(f["half"]) + 9.0:
			# 开放版：飞鹰常驻巡逻——飞出巡逻带就从另一侧绕回，不再消失
			g.position.x = -signf(g.position.x) * (float(f["half"]) + 9.0)
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

	for i in range(_emblems.size() - 1, -1, -1):
		var e: Dictionary = _emblems[i]
		var eg: Node3D = e["group"]
		e["t"] = float(e["t"]) + dt
		eg.rotation.y += dt * 1.2
		eg.position.y = float(e["base_y"]) + sin(float(e["t"]) * 2.0) * 0.13
		if player != null and player.alive:
			var pp: Vector3 = player.global_position
			var dx := eg.position.x - pp.x
			var dz := eg.position.z - pp.z
			if dx * dx + dz * dz < 1.7 and absf(eg.position.y - (pp.y + 0.8)) < 1.6:
				_collect_emblem(i)
	for i in range(_floats.size() - 1, -1, -1):
		var fl: Dictionary = _floats[i]
		fl["t"] = float(fl["t"]) + dt
		var lab: Label3D = fl["label"]
		lab.position.y += dt * 0.85
		if float(fl["t"]) > 0.75:
			var c := lab.modulate
			c.a = maxf(0.0, 1.15 - float(fl["t"]))
			lab.modulate = c
		if float(fl["t"]) > 1.15:
			lab.queue_free()
			_floats.remove_at(i)

func destroy_all() -> void:
	for f in _falcons:
		(f["group"] as Node3D).queue_free()
	for l in _letters:
		(l["group"] as Node3D).queue_free()
	for e in _emblems:
		(e["group"] as Node3D).queue_free()
	for fl in _floats:
		(fl["label"] as Node3D).queue_free()
	_falcons.clear()
	_letters.clear()
	_emblems.clear()
	_floats.clear()
