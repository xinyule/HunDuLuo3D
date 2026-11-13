extends SceneTree

## 终检补测：L4 右道（x=28）单道复跑——final_routes 的 pass 状态无避障导致被随机木箱楔住，
## 本版 pass 状态补 stall→sidestep，其余逻辑与 final_routes 同口径。
## 运行：godot --headless --path . --script res://test/final_l4lane.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _pass := 0
var _fail := 0
var _phase := "boot"
var _wait := 0
var _level = null
var _player = null
var _lane_tx := 28.0
var _path := 0.0
var _last_pos := Vector3.ZERO
var _min_margin := 999.0
var _stall := 0
var _last_dist := 0.0
var _sidesteps := 0
var _gate_i := 0
var _gs := ""
var _gs_frames := 0
var _gate_z := 0.0
var _gates_blocked := 0
var _boss_seen := false
var _trigger_dist := -1.0
var _boss_min_z := 999.0
var _boss_frames := 0
var _t0 := 0
var _pass_stall := 0
var _pass_last_z := 0.0

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

func _steer(tx: float, tz: float) -> void:
	var p: Vector3 = _player.global_position
	var dx := tx - p.x
	var dz := tz - p.z
	if dx * dx + dz * dz > 0.04:
		_main._yaw = atan2(dx, dz)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_main._load_level(3)
				_main._advance_dialog()
				_level = _main.current_level
				_player = _main.player
				_player.barrier = 99999.0
				var y: float = _level.get_support_y(_lane_tx, 24.0, 999.0)
				_player.global_position = Vector3(_lane_tx, y, 24.0)
				_last_pos = _player.global_position
				_last_dist = _level.player_dist(_player)
				_t0 = _frame
				_phase = "run"
				_wait = 3
		"run":
			if _wait > 0:
				_wait -= 1
				return
			if _frame - _t0 > 60 * 600:
				_check(false, "L4 lane 28 复跑超时")
				_finish()
				return
			_run()

func _run() -> void:
	var p: Vector3 = _player.global_position
	_path += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	_min_margin = minf(_min_margin, p.y - _level.terrain_h(p.x, p.z))
	var dist: float = _level.player_dist(_player)
	if _level.boss_activated:
		if not _boss_seen:
			_boss_seen = true
			_trigger_dist = dist
			_boss_frames = 0
		_boss_frames += 1
		_boss_min_z = minf(_boss_min_z, p.z)
		_steer(0.0, _level.boss_z - 30.0)
		Input.action_press("move_forward")
		if _boss_frames >= 300:
			_check(_boss_min_z > _level.boss_z + 1.1, "L4 lane 28 Boss 未死不能越线 (min_z=%.2f boss_z=%.2f)" % [_boss_min_z, _level.boss_z])
			_end()
		return
	if _gs == "jumptest":
		_gs_frames += 1
		_steer(_lane_tx, _gate_z - 30.0)
		Input.action_press("move_forward")
		if _gs_frames % 40 == 1:
			Input.action_press("jump")
		elif _gs_frames % 40 == 3:
			Input.action_release("jump")
		if _gs_frames >= 200:
			Input.action_release("jump")
			_check(p.z > _gate_z + 0.4, "L4 lane 28 电网门跳跃也过不去 (z=%.2f gate_z=%.2f)" % [p.z, _gate_z])
			var g: Dictionary = _level.gates[_gate_i]
			(g["sensor"] as Object).on_hit(99999)
			_gs = "pass"
			_pass_stall = 0
			_pass_last_z = p.z
		return
	if _gs == "pass":
		_steer(_lane_tx, _gate_z - 30.0)
		Input.action_press("move_forward")
		if absf(p.z - _pass_last_z) < 0.02:
			_pass_stall += 1
		else:
			_pass_stall = 0
			_pass_last_z = p.z
		if _pass_stall > 40:
			_pass_stall = 0
			_sidesteps += 1
			_lane_tx = clampf(_lane_tx + 4.0, -( _level.width / 2.0 - 16.0), _level.width / 2.0 - 16.0)
			print("  pass sidestep -> lane_x=%.0f (gate %d)" % [_lane_tx, _gate_i + 1])
		if p.z < _gate_z - 2.0:
			_gs = ""
			_gate_i += 1
			_last_dist = dist
			_stall = 0
		return
	_steer(_lane_tx, p.z - 40.0)
	Input.action_press("move_forward")
	if dist - _last_dist < 0.02:
		_stall += 1
	else:
		_stall = 0
		_last_dist = dist
	if _stall > 40:
		_stall = 0
		var blocked_by_gate := false
		if _gate_i < _level.gates.size():
			var g2: Dictionary = _level.gates[_gate_i]
			if bool((g2["sensor"] as Object).alive) and p.z > float(g2["z"]) and p.z - float(g2["z"]) < 6.0:
				blocked_by_gate = true
				_gate_z = float(g2["z"])
		if blocked_by_gate:
			_check(p.z > _gate_z + 0.4, "L4 lane 28 电网门正撞拦停 (z=%.2f gate_z=%.2f)" % [p.z, _gate_z])
			_gates_blocked += 1
			_gs = "jumptest"
			_gs_frames = 0
		else:
			_sidesteps += 1
			if _sidesteps > 10:
				_check(false, "L4 lane 28 卡死于 (%.1f, %.1f)" % [p.x, p.z])
				_end()
				return
			_lane_tx = clampf(_lane_tx + (6.0 if _sidesteps % 2 == 1 else -12.0), -(_level.width / 2.0 - 16.0), _level.width / 2.0 - 16.0)
			_last_dist = dist

func _end() -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")
	var t := float(_frame - _t0) / 60.0
	print("  ROUTE L4 lane 28 (复跑): path=%.1fm time=%.1fs trigger_dist=%s gates_blocked=%d/%d sidesteps=%d min_margin=%.2f" % [
		_path, t, ("%.1f" % _trigger_dist) if _trigger_dist >= 0.0 else "NONE",
		_gates_blocked, _level.gates.size(), _sidesteps, _min_margin])
	_check(_trigger_dist >= 0.0, "L4 lane 28 到达并触发 Boss")
	_check(_min_margin > -1.2, "L4 lane 28 全程未跌穿地形 (min_margin=%.2f)" % _min_margin)
	_finish()

func _finish() -> void:
	print("L4LANE RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
