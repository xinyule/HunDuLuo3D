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
func _build_wall(big: bool) -> void:
	var s := 1.25 if big else 1.0
	var steel := _pbr(Color(0.34, 0.38, 0.43) if not big else Color(0.4, 0.26, 0.24), 0.5, 0.65, "metal")
	var dark := _pbr(Color(0.15, 0.16, 0.18), 0.65, 0.5, "metal")
	var conc := _pbr(Color(0.46, 0.45, 0.41), 0.9, 0.0, "concrete")
	# 混凝土基座 + 三段钢板墙身（分段错缝，不再是一整块板）
	Util.box(_group, Vector3(18.4 * s, 1.3, 2.4), conc, Vector3(0, 0.65, 0))
	for i in 3:
		var px := (-6.0 + float(i) * 6.0) * s
		Util.box(_group, Vector3(5.7 * s, 5.6 * s, 1.1), steel, Vector3(px, 4.1 * s, 0))
		Util.box(_group, Vector3(0.35, 5.6 * s, 0.25), dark, Vector3(px + 2.95 * s, 4.1 * s, 0.62))
	Util.box(_group, Vector3(18.4 * s, 0.75, 1.7), dark, Vector3(0, 7.2 * s, 0))
	# 顶部橙色警示灯带 + 两端信标
	Util.box(_group, Vector3(17.6 * s, 0.2, 0.12), _glow(Color(1, 0.55, 0.1), 1.6), Vector3(0, 6.72 * s, 0.6))
	for sx in [-8.6 * s, 8.6 * s]:
		Util.sph(_group, 0.17, _glow(Color(1, 0.2, 0.1), 2.4), Vector3(sx, 7.75 * s, 0), 8, 6)
	# 炮塔：墙面炮座 + 可旋转炮塔（半球罩 + 双管 + 红色传感器眼）
	var turrets: Array = []
	for sx in [-6.3 * s, 6.3 * s]:
		Util.box(_group, Vector3(3.0, 1.3, 2.0), dark, Vector3(sx, 2.1 * s, 0.75))
		var tur := Node3D.new()
		tur.position = Vector3(sx, 3.05 * s, 1.05)
		_group.add_child(tur)
		Util.cyl(tur, 0.95, 1.1, 0.55, dark, Vector3(0, -0.1, 0), 14)
		Util.sph(tur, 0.82, steel, Vector3(0, 0.28, 0), 14, 10)
		var bm := _pbr(Color(0.07, 0.07, 0.08), 0.35, 0.85)
		for bx in [-0.3, 0.3]:
			var barrel := Util.cyl(tur, 0.09, 0.09, 1.5, bm, Vector3(bx, 0.42, 0.85))
			barrel.rotation.x = PI / 2.0
		Util.sph(tur, 0.17, _glow(Color(1, 0.15, 0.1), 2.6), Vector3(0, 0.78, 0.5), 8, 6)
		turrets.append(tur)
		_add_part("turret", 300 if big else 220, tur, 1.3)
	_anim_nodes["turrets"] = turrets
	# 核心：金属舱环 + 发光红核（被炮塔护着，双塔毁后暴露）
	var housing := Util.cyl(_group, 1.5 * s, 1.5 * s, 0.55, dark, Vector3(0, 3.9 * s, 0.55), 20)
	housing.rotation.x = PI / 2.0
	var core := Util.sph(_group, 0.98 * s, _glow(Color(1, 0.13, 0.13), 3.2), Vector3(0, 3.9 * s, 0.95), 18, 14)
	var core_p := _add_part("core", 850 if big else 520, core, 1.1 * s, true)
	core_p.vulnerable = false
	_anim_nodes["core"] = core

func _build_base_core() -> void:
	var m := _pbr(Color(0.24, 0.28, 0.36), 0.55, 0.6, "metal")
	Util.box(_group, Vector3(7, 3.4, 1.6), m, Vector3(0, 1.7, 0))
	Util.box(_group, Vector3(5, 1.6, 1.4), m, Vector3(0, 4.2, 0))
	for sx in [-2.6, 2.6]:
		var pod := Node3D.new()
		pod.position = Vector3(sx, 2.6, 0.9)
		_group.add_child(pod)
		Util.sph(pod, 0.45, _pbr(Color(0.35, 0.4, 0.5), 0.4, 0.7, "metal"), Vector3.ZERO, 12, 9)
		Util.sph(pod, 0.2, _glow(Color(1, 0.65, 0.0)), Vector3(0, 0, 0.36), 8, 6)
		_add_part("pod", 150, pod, 0.62)
	var eye := Util.sph(_group, 1.15, _glow(Color(1, 0.2, 0.2), 3.0), Vector3(0, 5.4, 0.8), 18, 14)
	var eye_p := _add_part("eye", 680, eye, 1.3, true)
	_anim_nodes["eye"] = eye
	_anim_nodes["eye_part"] = eye_p

func _build_gromaides() -> void:
	var stone := _pbr(Color(0.72, 0.68, 0.6), 0.95, 0.0, "rock")
	Util.box(_group, Vector3(5.5, 3.2, 2.2), stone, Vector3(0, 1.6, 0))
	Util.box(_group, Vector3(4.2, 2.2, 2.0), stone, Vector3(0, 4.2, 0))
	var head := Node3D.new()
	head.position = Vector3(0, 6.6, 0.4)
	_group.add_child(head)
	Util.box(head, Vector3(3.4, 2.2, 2.6), stone, Vector3.ZERO)
	for hx in [-1.1, 1.1]:
		Util.cyl(head, 0.02, 0.2, 0.9, stone, Vector3(hx, 1.4, -0.2), 6)
		Util.sph(head, 0.26, _glow(Color(1, 1, 0.25)), Vector3(hx, 0.35, 1.32), 8, 6)
	var jaw := Util.box(head, Vector3(2.2, 0.5, 1.8), stone, Vector3(0, -1.25, 0.3))
	_anim_nodes["jaw"] = jaw
	var mouth := Util.sph(head, 0.62, _glow(Color(1, 0.4, 0.05), 3.0), Vector3(0, -0.55, 1.15), 12, 9)
	var mouth_p := _add_part("mouth", 720, mouth, 0.85, true)
	mouth_p.vulnerable = false
	_anim_nodes["mouth_part"] = mouth_p
	_anim_nodes["head"] = head

func _build_godomuga() -> void:
	var frame := _pbr(Color(0.24, 0.19, 0.33), 0.6, 0.5, "metal")
	Util.box(_group, Vector3(8, 6.4, 1.4), frame, Vector3(0, 3.2, 0))
	var phantoms: Array = []
	for i in 4:
		var ph := Util.sph(_group, 0.72, _glow(Color(0.73, 0.4, 1), 1.6), Vector3.ZERO, 12, 9)
		phantoms.append(ph)
	_anim_nodes["phantoms"] = phantoms
	var core := Util.sph(_group, 0.95, _glow(Color(1, 0.8, 0.2), 3.2), Vector3(0, 3.4, 1.0), 16, 12)
	core.visible = false
	var core_p := _add_part("core", 780, core, 1.1, true)
	core_p.vulnerable = false
	core_p.targetable = false
	_anim_nodes["core"] = core
	_anim_nodes["core_part"] = core_p

func _build_guldaf() -> void:
	var ship := Node3D.new()
	ship.position = Vector3(0, 6.4, 0)
	_group.add_child(ship)
	_anim_nodes["ship"] = ship
	var hull := _pbr(Color(0.44, 0.51, 0.6), 0.35, 0.85, "metal")
	var disc := Util.cyl(ship, 3.4, 3.9, 1.1, hull, Vector3.ZERO, 20)
	Util.sph(ship, 1.15, _pbr(Color(0.55, 0.62, 0.72), 0.3, 0.9, "metal"), Vector3(0, 0.85, 0), 14, 10)
	for i in 4:
		var a := float(i) / 4.0 * TAU
		Util.sph(ship, 0.28, _glow(Color(0.3, 0.9, 1)), Vector3(cos(a) * 3.4, 0, sin(a) * 3.4), 8, 6)
	for px in [-2.2, 2.2]:
		var pod := Util.sph(ship, 0.62, _pbr(Color(0.54, 0.6, 0.66), 0.4, 0.8, "metal"), Vector3(px, -0.75, 0), 10, 8)
		_add_part("pod", 200, pod, 0.8)
	var core := Util.sph(ship, 0.95, _glow(Color(1, 0.2, 0.2), 3.2), Vector3(0, -1.1, 0), 16, 12)
	_add_part("core", 820, core, 1.15, true)

func _build_gordea() -> void:
	var armor := _pbr(Color(0.48, 0.23, 0.13), 0.55, 0.6, "rust")
	var dark := _pbr(Color(0.25, 0.15, 0.1), 0.7, 0.4)
	var body := Node3D.new()
	_group.add_child(body)
	_anim_nodes["body"] = body
	for sx in [-0.75, 0.75]:
		Util.box(body, Vector3(0.85, 2.6, 1.0), dark, Vector3(sx, 1.3, 0))
		Util.box(body, Vector3(0.95, 0.5, 1.3), dark, Vector3(sx, 0.25, 0.1))
	Util.box(body, Vector3(2.5, 2.4, 1.5), armor, Vector3(0, 3.9, 0))
	Util.box(body, Vector3(2.7, 0.6, 1.6), dark, Vector3(0, 5.2, 0))
	var head := Util.box(body, Vector3(1.05, 1.0, 1.05), armor, Vector3(0, 5.95, 0))
	Util.box(body, Vector3(1.1, 0.3, 1.1), _pbr(Color(0.66, 0.13, 0.13), 0.6, 0.3), Vector3(0, 6.5, 0))
	for sx in [-1.65, 1.65]:
		Util.box(body, Vector3(0.7, 2.5, 0.8), armor, Vector3(sx, 4.1, 0))
		Util.sph(body, 0.5, dark, Vector3(sx, 2.75, 0.15), 10, 8)
	var gem := Util.sph(body, 0.42, _glow(Color(1, 0.8, 0.2), 3.2), Vector3(0, 4.1, 0.82), 12, 9)
	_add_part("body", 1500, head, 3.1) # 身体以头部节点为锚、半径覆盖全身
	_add_part("gem", 700, gem, 0.62, true)

func _build_alien_heart() -> void:
	var flesh := _pbr(Color(0.48, 0.12, 0.24), 0.45, 0.0, "alien")
	var dark_f := _pbr(Color(0.3, 0.06, 0.19), 0.5, 0.0, "alien")
	Util.box(_group, Vector3(15, 8.5, 2.0), dark_f, Vector3(0, 4.25, -0.8))
	# 龙神 Java：左侧蛇颈龙头
	var dragon := Node3D.new()
	dragon.position = Vector3(-4.6, 0, 1.2)
	_group.add_child(dragon)
	_anim_nodes["dragon"] = dragon
	var neck := Util.cyl(dragon, 0.55, 0.8, 4.6, flesh, Vector3(0, 2.0, 0), 10)
	neck.rotation.z = 0.35
	var dhead := Node3D.new()
	dhead.position = Vector3(1.5, 4.4, 0.3)
	dragon.add_child(dhead)
	Util.box(dhead, Vector3(1.5, 1.0, 2.1), flesh, Vector3(0, 0, 0.4))
	for ex in [-0.4, 0.4]:
		Util.sph(dhead, 0.13, _glow(Color(1, 1, 0.3)), Vector3(ex, 0.3, 1.15), 8, 6)
	for tx in [-0.3, 0.3]:
		var tooth := Util.cyl(dhead, 0.01, 0.07, 0.4, _pbr(Color(0.9, 0.88, 0.8), 0.4), Vector3(tx, -0.6, 1.2), 5)
		tooth.rotation.x = PI
	var dragon_p := _add_part("dragon", 620, dhead, 1.35)
	_anim_nodes["dragon_part"] = dragon_p
	# 心脏：正中脉动，龙神死前无敌
	var heart := Util.sph(_group, 1.55, _glow(Color(0.85, 0.1, 0.3), 1.8), Vector3(1.8, 4.3, 0.9), 18, 14)
	heart.scale = Vector3(1, 1.18, 1)
	var heart_p := _add_part("heart", 1050, heart, 1.8, true)
	heart_p.vulnerable = false
	_anim_nodes["heart"] = heart
	_anim_nodes["heart_part"] = heart_p

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
				_fire_timer = 1.7 if dragon_alive else 1.1
				_orb_at(global_position + Vector3(-3.1, 4.6, 1.5), player, 18.0, 0.25)
				if not dragon_alive:
					_orb_at(_anim_nodes["heart"].global_position, player, 19.0, 0.2)
			if _special_timer <= 0.0:
				_special_timer = 8.0
				_ctx["spawn_minion"].call("spore", global_position.x + randf_range(-5, 5), global_position.z + 8.0)

func _orb_at(from: Vector3, player, speed: float, inacc: float, spread_x: float = 0.0) -> void:
	var target := Vector3(
		player.global_position.x + randf_range(-inacc, inacc) * 2.0,
		player.chest_y(),
		player.global_position.z + randf_range(-inacc, inacc) * 2.0)
	var dir: Vector3 = (target - from).normalized()
	if spread_x != 0.0:
		var right := Vector3(-dir.z, 0, dir.x)
		dir = (dir + right * spread_x).normalized()
	_ctx["projectiles"].spawn_orb(from, dir, speed, 1)
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
