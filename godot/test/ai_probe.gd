extends SceneTree

## 1.2.0 智能 AI 行为探针：
## (a) 站立射手挨打后会进掩体，且躲掩体期间玩家直射视线可用率从高位跌到低位
## (b) 躲掩体后会自己出来（探头态）并真实开火（以受试者自身 _react_t 开火签名判定）
## (c) 丢失目标后受试者会向最后目击点移动搜索（与目击点距离显著缩短）
## 运行：godot --headless --path . --script res://test/ai_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := "boot"
var _wait := 0
var _pass := 0
var _fail := 0

var _e = null # 受试者 A（掩体/探头）
var _e_start := Vector3.ZERO
var _base_vis := 0
var _base_n := 0
var _hid_block := 0
var _hid_n := 0
var _t := 0 # 当前阶段帧计数（60 帧 = 1 模拟秒）
var _peek_seen := false
var _fire_seen := false
var _e2 = null # 受试者 B（搜索）
var _last_seen := Vector3.ZERO
var _e2_start := Vector3.ZERO
var _e2_d0 := 0.0

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _los_frac_player_to(e, h: float) -> bool:
	var lvl = _main.current_level
	var from := Vector3(_main.player.global_position.x, _main.player.chest_y(), _main.player.global_position.z)
	var to: Vector3 = e.global_position + Vector3(0, h, 0)
	return lvl.has_los(from, to)

# 密集遮挡判定（与 enemy._los_blocked_dense 同口径）：has_los 2.5m 内点采样会漏检小掩体，
# 测「直射是否被挡」须按弹道口径逐点查
func _blocked_dense(a: Vector3, b: Vector3) -> bool:
	var lvl = _main.current_level
	var n := int(ceil(a.distance_to(b) / 0.5))
	if n < 1:
		n = 1
	for i in range(n + 1):
		var p: Vector3 = a.lerp(b, float(i) / float(n))
		if lvl.terrain_h(p.x, p.z) > p.y + 0.3:
			return true
		for c in lvl.colliders:
			if c.get("disabled", false) or c.get("no_collide", false):
				continue
			var y0 := float(c.get("y0", 0.0))
			if p.y < y0 or p.y > y0 + float(c.get("h", 6.0)):
				continue
			if c["type"] == "box":
				if absf(p.x - float(c["x"])) <= float(c["w"]) / 2.0 and absf(p.z - float(c["z"])) <= float(c["d"]) / 2.0:
					return true
			elif c["type"] == "circle":
				var dx: float = p.x - float(c["x"])
				var dz: float = p.z - float(c["z"])
				var r := float(c["r"])
				if dx * dx + dz * dz <= r * r:
					return true
	return false

func _place_player(pos: Vector3) -> void:
	_main.player.global_position = pos
	_main.player.vy = 0.0
	_main.player.grounded = true
	_main.player.barrier = 99999.0

## 找受试者：站立射手、13m 内有 cover 掩体、与玩家布位点通视
func _pick_subject(exclude: Array, want_cover: bool = true) -> Object:
	var lvl = _main.current_level
	for e in lvl.enemies:
		if exclude.has(e) or not e.alive:
			continue
		if not (String(e.type) in ["rifleman", "garth", "langel", "sniper"]):
			continue
		if absf(e.global_position.y - lvl.terrain_h(e.global_position.x, e.global_position.z)) > 1.2:
			continue # 只选站在地面上的（高塔/平台岗哨下不来，不作掩体受试者）
		var has_cover := false
		for c in lvl.colliders:
			if bool(c.get("cover", false)) and not bool(c.get("disabled", false)):
				var d := Vector2(float(c["x"]) - e.global_position.x, float(c["z"]) - e.global_position.z).length()
				# 预筛与游戏 _find_cover 蹲姿口径对齐：掩体顶高出当地地面 ≥0.6m（蹲下可藏）
				var top := float(c.get("y0", 0.0)) + float(c.get("h", 6.0))
				if d > 1.0 and d < 13.0 and top - lvl.terrain_h(float(c["x"]), float(c["z"])) >= 0.6:
					has_cover = true
					break
		if want_cover and not has_cover:
			continue
		# 布位点：敌人南侧（+z，玩家来路）13m，通视；实测 _find_cover 结果须与需求一致
		# （要掩体者须能选中掩体含射程门；搜索受试者须无掩体可用，免其躲进掩体循环不出来找人）
		var sp: Vector3 = e.global_position + Vector3(0, 0, 13.0)
		sp.y = lvl.get_support_y(sp.x, sp.z, e.global_position.y + 2.0)
		var eye: Vector3 = e.global_position + Vector3(0, 1.45, 0)
		if lvl.has_los(eye, sp + Vector3(0, 1.3, 0)):
			_place_player(sp)
			if e._find_cover(_main.player) == want_cover:
				return e
	return null

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_phase = "enter"
		"enter":
			if _main.state == "dialog":
				_main._advance_dialog()
				_phase = "pick_a"
				_t = 0
			elif _frame > 3000:
				_check(false, "进入 L1 超时")
				_finish()
		"pick_a":
			_e = _pick_subject([])
			_check(_e != null, "找到掩体行为受试者")
			if _e == null:
				_finish()
				return
			_e_start = _e.global_position
			print("  subject A: %s at %s" % [String(_e.type), str(_e_start)])
			# 全场隔离：预选受试者 B 后清掉其余敌人——防任何同伴抢占掩体/抢先警戒串扰
			var keep_b = _pick_subject([_e], false) # 预留搜索受试者（无掩体可用者）
			for o in _main.current_level.enemies:
				if o != _e and o != keep_b and o.alive:
					o.on_hit(9999)
			print("  isolation: kept B = %s" % str(keep_b != null))
			# B 的选人把玩家挪走了——重新布回 A 的南侧布位点
			var sp2: Vector3 = _e.global_position + Vector3(0, 0, 13.0)
			sp2.y = _main.current_level.get_support_y(sp2.x, sp2.z, _e.global_position.y + 2.0)
			_place_player(sp2)
			_phase = "alert_a"
			_t = 0
		"alert_a":
			_t += 1
			if _e._alert:
				_phase = "base_a"
				_t = 0
			elif _t > 360:
				_check(false, "受试者 A 未警戒")
				_finish()
		"base_a": # 基线：开阔状态下玩家→敌人直视可用率（应高）
			_t += 1
			_base_n += 1
			if _los_frac_player_to(_e, 1.0):
				_base_vis += 1
			if _t >= 30:
				_check(_base_vis >= 24, "基线开阔视线可用 %d/30（应 ≥24）" % _base_vis)
				_e.on_hit(3) # 挨打触发找掩体意图
				_phase = "seek_a"
				_t = 0
		"seek_a":
			_t += 1
			if _t % 90 == 0 and _e.alive and _e._tac_state == 0:
				_e.on_hit(2) # 补刀续触（每次 65% 采纳），总伤仍远低于 hp30
			if _e._tac_state == 2:
				var moved := Vector2(_e.global_position.x - _e_start.x, _e.global_position.z - _e_start.z).length()
				_check(moved >= 1.5, "受试者 A 挨打后移动 %.1fm 进入掩体" % moved)
				_phase = "hidden_a"
				_t = 0
			elif _t > 60 * 18:
				_check(false, "受试者 A 18s 内未进入掩体（state=%d）" % _e._tac_state)
				_finish()
		"hidden_a": # 躲掩体期间直射应被挡（按弹道口径测到当下真实 hit_y——蹲姿 +0.55）
			_t += 1
			_hid_n += 1
			var chest := Vector3(_main.player.global_position.x, _main.player.chest_y(), _main.player.global_position.z)
			if _blocked_dense(chest, _e.global_position + Vector3(0, _e.hit_y - _e.global_position.y, 0)):
				_hid_block += 1
			if _e._tac_state != 2 or _t >= 50:
				_check(_hid_n >= 15 and _hid_block * 5 >= _hid_n * 4, "掩体后直射被挡 %d/%d（应 ≥80%%）" % [_hid_block, _hid_n])
				_phase = "peek_b"
				_t = 0
		"peek_b": # 应自己出来探头并开火（开火签名：探头态期间其枪口 2.2m 内有新光弹）
			_t += 1
			if _e._tac_state == 4:
				_peek_seen = true
				for o in _main.projectiles._orbs:
					var op: Vector3 = o["pos"]
					if Vector2(op.x - _e.global_position.x, op.z - _e.global_position.z).length() < 2.2 and absf(op.y - (_e.global_position.y + 1.3)) < 1.2:
						_fire_seen = true
			if _peek_seen and _fire_seen:
				_check(true, "受试者 A 掩体后自行探头并开火")
				_phase = "pick_c"
				_t = 0
			elif _t > 60 * 14:
				_check(false, "受试者 A 未探头/未开火（peek=%s fire=%s state=%d）" % [str(_peek_seen), str(_fire_seen), _e._tac_state])
				_phase = "pick_c"
				_t = 0
		"pick_c":
			_e2 = _pick_subject([_e], false)
			_check(_e2 != null, "找到搜索行为受试者")
			if _e2 == null:
				_finish()
				return
			print("  subject B: %s at %s" % [String(_e2.type), str(_e2.global_position)])
			_phase = "alert_c"
			_t = 0
		"alert_c":
			_t += 1
			if _e2._alert and _e2._seen_age < 1.0 and _e2._last_seen.distance_to(_main.player.global_position) < 6.0:
				# 把玩家挪到敌人看不见的位置：优先取高大障碍（建筑/大石）背侧点，环形扫描兜底
				var lvl = _main.current_level
				var spot := Vector3.ZERO
				var found := false
				var eye2: Vector3 = _e2.global_position + Vector3(0, 1.45, 0)
				for c in lvl.colliders:
					if bool(c.get("disabled", false)):
						continue
					var top := float(c.get("y0", 0.0)) + float(c.get("h", 6.0))
					if top - lvl.terrain_h(float(c["x"]), float(c["z"])) < 2.2:
						continue
					var cd := Vector2(float(c["x"]) - _e2.global_position.x, float(c["z"]) - _e2.global_position.z)
					if cd.length() > 45.0 or cd.length() < 3.0:
						continue
					var ext := 0.0
					if c["type"] == "circle":
						ext = float(c["r"])
					else:
						ext = maxf(float(c["w"]), float(c["d"])) * 0.5
					if ext < 1.6:
						continue # 窄障碍（塔腿之类）敌人横移一步就绕开，不算数
					var dirv := cd.normalized()
					var cand2: Vector3 = Vector3(float(c["x"]) + dirv.x * (ext + 3.0), 0, float(c["z"]) + dirv.y * (ext + 3.0))
					cand2.y = lvl.get_support_y(cand2.x, cand2.z, _e2.global_position.y + 2.0)
					# 从受试者原位与左右横移位三处眼位验挡（防横移绕障）
					var all_blocked := true
					for eoff in [Vector3.ZERO, Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
						if not _blocked_dense(eye2 + eoff, cand2 + Vector3(0, 1.3, 0)):
							all_blocked = false
							break
					if all_blocked:
						spot = cand2
						found = true
						break
				if not found:
					for r in [18.0, 22.0, 26.0, 30.0]:
						for k in 16:
							var a := float(k) / 16.0 * TAU
							var cand: Vector3 = _e2.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
							cand.y = lvl.get_support_y(cand.x, cand.z, _e2.global_position.y + 2.0)
							if _blocked_dense(eye2, cand + Vector3(0, 1.3, 0)):
								spot = cand
								found = true
								break
						if found:
							break
				_check(found, "找到无视线藏身点")
				if not found:
					_finish()
					return
				_last_seen = _e2._last_seen
				_place_player(spot)
				_e2_start = _e2.global_position
				_e2_d0 = Vector2(_e2_start.x - _last_seen.x, _e2_start.z - _last_seen.z).length()
				_phase = "search_c"
				_t = 0
			elif _t > 360:
				_check(false, "受试者 B 未警戒/未目击")
				_finish()
		"search_c":
			_t += 1
			var d1 := Vector2(_e2.global_position.x - _last_seen.x, _e2.global_position.z - _last_seen.z).length()
			if _e2_d0 - d1 >= 3.0:
				_check(true, "受试者 B 向目击点搜索推进 %.1fm（%.1f→%.1f）" % [_e2_d0 - d1, _e2_d0, d1])
				_finish()
			elif _t > 60 * 20:
				_check(false, "受试者 B 20s 内未向目击点推进（%.1f→%.1f，state=%d）" % [_e2_d0, d1, _e2._tac_state])
				_finish()

func _finish() -> void:
	print("AI PROBE RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
