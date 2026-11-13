extends SceneTree

## 第二线探针：加长后逐关逐路线完整性实走（final_routes 的长关版，基线按新长度重标）
## 与终检版差异：边界期望改用 level.playable_half_width()（第一线室内钳制口径）、路线长按下限断言
## 验证：①电网门未开时全宽拦人（正撞+跳跃都过不去）②边界 clamp 不出界、y 不跌穿
## ③每条路线必触发 Boss 且 Boss 未死不能越过 Boss 线 ④逐路线行进长度/用时留数值
## ⑤L3 山洞：进洞可达鹰徽、洞内是死胡同、洞顶穿入后仍只能从洞口出
## 运行：godot --headless --path . --script res://test/final_routes.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _pass := 0
var _fail := 0

var _jobs: Array = []
var _job_i := -1
var _job: Dictionary = {}
var _phase := "boot"
var _wait := 0
var _job_frames := 0
var _setup_frames := 0 # setup 门控看门狗：防门控死锁静默空转
var _from_job := 0 # 断点续跑起点（命令行 --from-job N）

var _level = null
var _player = null
var _lv := 0

# 行走追踪
var _path := 0.0
var _last_pos := Vector3.ZERO
var _min_margin := 999.0
var _max_abs_x := 0.0
var _max_z := -999.0
var _stall := 0
var _last_dist := 0.0
var _sidesteps := 0
var _lane_tx := 0.0
var _t0 := 0
# 门
var _gate_i := 0
var _gs := ""
var _gs_frames := 0
var _gate_z := 0.0
var _lock_ref: Dictionary = {} # 1.2.0：当前正在处理的封锁区
var _lock_steps := 0 # 1.2.0：封锁穿行中的绕障横移计数（与路线 _sidesteps 分开）
var _gates_blocked := 0
# Boss
var _boss_seen := false
var _trigger_dist := -1.0
var _trigger_time := -1.0
var _boss_min_z := 999.0
var _boss_frames := 0
# 边界子段
var _sub := 0
var _sub_frames := 0
# 山洞
var _cave_stage := ""
var _cave_start_z := 0.0
var _cave_min_z := 999.0
var _cave_top_y := 0.0

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	Engine.time_scale = 3.0 # 探针专用加速：本机算力下全关实走帧数过大；断言均为位置/状态型，不受倍率影响
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from-job="):
			_from_job = int(a.trim_prefix("--from-job="))
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)
	# 作业表：每关先边界、再三条路线（左/中/右），L3 追加山洞
	for lv in Data.LEVELS.size():
		var w := float(Data.LEVELS[lv]["width"])
		_jobs.append({"kind": "boundary", "lv": lv})
		for lx in [-(w / 2.0 - 20.0), 0.0, w / 2.0 - 20.0]:
			_jobs.append({"kind": "lane", "lv": lv, "lane_x": lx})
		if lv == 2:
			_jobs.append({"kind": "cave", "lv": lv})

func _steer(tx: float, tz: float) -> void:
	var p: Vector3 = _player.global_position
	var dx := tx - p.x
	var dz := tz - p.z
	if dx * dx + dz * dz > 0.04:
		_main._yaw = atan2(dx, dz)

func _track() -> void:
	var p: Vector3 = _player.global_position
	_path += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	var margin: float = p.y - _level.terrain_h(p.x, p.z)
	_min_margin = minf(_min_margin, margin)
	_max_abs_x = maxf(_max_abs_x, absf(p.x))
	_max_z = maxf(_max_z, p.z)

func _teleport(x: float, z: float) -> void:
	var y: float = _level.get_support_y(x, z, 999.0)
	_player.global_position = Vector3(x, y, z)
	_player.vy = 0.0
	_player.grounded = true
	_last_pos = _player.global_position

func _next_job() -> void:
	_job_i += 1
	if _job_i >= _jobs.size():
		print("LONG ROUTES RESULT: %d passed, %d failed" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)
		return
	if _job_i < _from_job:
		_next_job() # 断点续跑：跳过已验作业（-- --from-job N）
		return
	_job = _jobs[_job_i]
	_lv = int(_job["lv"])
	_phase = "setup"
	_wait = 0
	_job_frames = 0
	_setup_frames = 0

func _setup_job() -> void:
	# 1.2.0 探针适配（同 1.1.0 其余探针的 dialog 门控）：_load_level 已由 _on_frame 的
	# setup 门控发起并等到 state=dialog 才进本函数，此处只推进剧情拿 playing 态。
	# 旧版在此无条件调 _load_level：加载中重试会在协程完成当帧把已建好的关卡重启，
	# _free_run 随即销毁探针正引用的 player/level，run 阶段全程操作已释放对象直至超时。
	_main._advance_dialog()
	_level = _main.current_level
	_player = _main.player
	_player.barrier = 99999.0
	_path = 0.0
	_min_margin = 999.0
	_max_abs_x = 0.0
	_max_z = -999.0
	_stall = 0
	_sidesteps = 0
	_gate_i = 0
	_gs = ""
	_boss_seen = false
	_trigger_dist = -1.0
	_boss_min_z = 999.0
	_boss_frames = 0
	_gates_blocked = 0
	_t0 = _frame
	var kind := String(_job["kind"])
	if kind == "lane":
		_lane_tx = float(_job["lane_x"])
		_teleport(_lane_tx, 24.0)
		_last_dist = _level.player_dist(_player)
		print("== L%d lane x=%.0f ==" % [_lv + 1, _lane_tx])
		# 哨塔/哨所支撑面核查（L1/L5 首条路线时）
		if _lv == 0 or _lv == 4:
			var op: Dictionary = Data.LEVELS[_lv]["outpost"]
			var tx := float(op["tx"])
			var tz := float(op["tz"])
			var s: float = _level.get_support_y(tx, tz, 999.0)
			var g: float = _level.terrain_h(tx, tz)
			_check(s > g + 3.0, "L%d 哨塔顶平台支撑存在 (support=%.2f ground=%.2f)" % [_lv + 1, s, g])
	elif kind == "boundary":
		_sub = 0
		_sub_frames = 0
		_teleport(0.0, 10.0)
		print("== L%d boundary ==" % [_lv + 1])
	elif kind == "cave":
		_cave_stage = "enter"
		_cave_min_z = 999.0
		_teleport(-33.0, -66.0)
		print("== L3 cave ==")
	_phase = "run"
	_wait = 3

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_next_job()
			return
		"setup":
			_setup_frames += 1
			if _setup_frames > 4000:
				_check(false, "L%d %s setup 门控超时（加载未落地）" % [_lv + 1, String(_job["kind"])])
				_next_job()
				return
			# dialog 门控：目标关加载完成（state=dialog 且 level_index 对版、player 有效）才 setup；
			# 非加载态一律发起（同关连跑也要重载出干净关卡态）；加载中只等，不重复调 _load_level。
			# 注：旧条件带 level_index!=_lv，同关第二个作业会因 idx 相同永不触发加载而死锁，已修。
			if _main.state == "dialog" and _main.level_index == _lv and is_instance_valid(_main.player):
				_setup_job()
			elif _main.state != "loading":
				_main._load_level(_lv)
			return
		"run":
			if _wait > 0:
				_wait -= 1
				return
			_job_frames += 1
			if _job_frames > 60 * 360:
				_check(false, "L%d %s 作业超时" % [_lv + 1, String(_job["kind"])])
				Input.action_release("move_forward")
				_next_job()
				return
			match String(_job["kind"]):
				"lane": _run_lane()
				"boundary": _run_boundary()
				"cave": _run_cave()

func _run_lane() -> void:
	_track()
	var p: Vector3 = _player.global_position
	var dist: float = _level.player_dist(_player)
	if p.y < -10.0:
		_check(false, "L%d lane %.0f 掉出世界 y=%.1f" % [_lv + 1, _lane_tx, p.y])
		_end_lane()
		return
	# Boss 已触发：封线测试
	if _level.boss_activated:
		if not _boss_seen:
			_boss_seen = true
			_trigger_dist = dist
			_trigger_time = float(_frame - _t0) / 60.0
			_boss_frames = 0
		_boss_frames += 1
		_boss_min_z = minf(_boss_min_z, p.z)
		_steer(0.0, _level.boss_z - 30.0)
		Input.action_press("move_forward")
		if _boss_frames >= 300:
			_check(_boss_min_z > _level.boss_z + 1.1, "L%d lane %.0f Boss 未死不能越线 (min_z=%.2f boss_z=%.2f)" % [_lv + 1, _lane_tx, _boss_min_z, _level.boss_z])
			_end_lane()
		return
	# 门处理
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
			_check(p.z > _gate_z + 0.4, "L%d lane %.0f 电网门跳跃也过不去 (z=%.2f gate_z=%.2f)" % [_lv + 1, _lane_tx, p.z, _gate_z])
			var g: Dictionary = _level.gates[_gate_i]
			(g["sensor"] as Object).on_hit(99999)
			_gs = "pass"
		return
	if _gs == "pass":
		_steer(_lane_tx, _gate_z - 30.0)
		Input.action_press("move_forward")
		if p.z < _gate_z - 2.0:
			_gs = ""
			_gate_i += 1
			_last_dist = dist
			_stall = 0
		return
	if _gs == "lockclear":
		# 1.2.0 封锁点：成员已清，等墙落下后穿过墙线恢复正常行走
		# 墙前/墙线常有营地建筑、残骸挡道（卡点未必是墙本身），沿用正常行走的横移绕障
		_steer(_lane_tx, float(_lock_ref["z"]) - 30.0)
		Input.action_press("move_forward")
		_gs_frames += 1
		if p.z < float(_lock_ref["z"]) - 2.0:
			_gs = ""
			_last_dist = dist
			_stall = 0
		elif _gs_frames > 2400:
			_check(false, "L%d lane %.0f 封锁清场后墙未落下" % [_lv + 1, _lane_tx])
			_end_lane()
		else:
			if dist - _last_dist < 0.02:
				_stall += 1
			else:
				_stall = 0
				_last_dist = dist
			if _stall > 40:
				_stall = 0
				_lock_steps += 1
				_lane_tx = clampf(_lane_tx + (6.0 if _lock_steps % 2 == 1 else -12.0), -(_level.width / 2.0 - 16.0), _level.width / 2.0 - 16.0)
		return
	# 正常行走
	_steer(_lane_tx, p.z - 40.0)
	Input.action_press("move_forward")
	if dist - _last_dist < 0.02:
		_stall += 1
	else:
		_stall = 0
		_last_dist = dist
	if _stall > 40:
		_stall = 0
		# 1.2.0：前方是否有活跃封锁墙（先于电网门判定）——清掉区内成员等墙落
		var blocked_by_lock := false
		for lk in _level.locks:
			if bool(lk["active"]) and p.z > float(lk["z"]) and p.z - float(lk["z"]) < 6.0:
				blocked_by_lock = true
				_lock_ref = lk
				break
		if blocked_by_lock:
			_check(p.z > float(_lock_ref["z"]) + 0.4, "L%d lane %.0f 封锁墙正撞拦停 (z=%.2f wall_z=%.2f)" % [_lv + 1, _lane_tx, p.z, float(_lock_ref["z"])])
			for e in _lock_ref["members"]:
				if is_instance_valid(e) and e.alive:
					e.on_hit(99999)
			_gs = "lockclear"
			_gs_frames = 0
			_lock_steps = 0
			return
		# 前方是否有未开的门
		var blocked_by_gate := false
		if _gate_i < _level.gates.size():
			var g2: Dictionary = _level.gates[_gate_i]
			if bool((g2["sensor"] as Object).alive) and p.z > float(g2["z"]) and p.z - float(g2["z"]) < 6.0:
				blocked_by_gate = true
				_gate_z = float(g2["z"])
		if blocked_by_gate:
			_check(p.z > _gate_z + 0.4, "L%d lane %.0f 电网门正撞拦停 (z=%.2f gate_z=%.2f)" % [_lv + 1, _lane_tx, p.z, _gate_z])
			_gates_blocked += 1
			_gs = "jumptest"
			_gs_frames = 0
		else:
			_sidesteps += 1
			if _sidesteps > 8:
				_check(false, "L%d lane %.0f 路线卡死于 (%.1f, %.1f) dist=%.1f" % [_lv + 1, _lane_tx, p.x, p.z, dist])
				_end_lane()
				return
			_lane_tx = clampf(_lane_tx + (6.0 if _sidesteps % 2 == 1 else -12.0), -(_level.width / 2.0 - 16.0), _level.width / 2.0 - 16.0)
			_last_dist = dist

func _end_lane() -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")
	var t := float(_frame - _t0) / 60.0
	print("  ROUTE L%d lane %.0f: path=%.1fm time=%.1fs trigger_dist=%s gates_blocked=%d/%d sidesteps=%d min_margin=%.2f" % [
		_lv + 1, float(_job["lane_x"]), _path, t,
		("%.1f" % _trigger_dist) if _trigger_dist >= 0.0 else "NONE",
		_gates_blocked, _level.gates.size(), _sidesteps, _min_margin])
	_check(_trigger_dist >= 0.0, "L%d lane %.0f 到达并触发 Boss" % [_lv + 1, float(_job["lane_x"])])
	_check(_path >= float(Data.LEVELS[_lv]["length"]) * 0.92, "L%d lane %.0f 实走路长 %.1fm 与新长度 %.0fm 匹配" % [_lv + 1, float(_job["lane_x"]), _path, float(Data.LEVELS[_lv]["length"])])
	_check(_min_margin > -1.2, "L%d lane %.0f 全程未跌穿地形 (min_margin=%.2f)" % [_lv + 1, float(_job["lane_x"]), _min_margin])
	_next_job()

func _run_boundary() -> void:
	_track()
	var p: Vector3 = _player.global_position
	_sub_frames += 1
	match _sub:
		0, 1:
			_main._yaw = -PI / 2.0 if _sub == 0 else PI / 2.0
			Input.action_press("move_forward")
			if _sub_frames >= 300:
				var half: float = _level.playable_half_width()
				_check(_max_abs_x <= half + 0.05, "L%d 边界横走%s |x|<=%.1f (max=%.2f)" % [_lv + 1, "左" if _sub == 0 else "右", half, _max_abs_x])
				_sub += 1
				_sub_frames = 0
				_max_abs_x = 0.0
				_teleport(0.0, 10.0)
		2:
			_main._yaw = 0.0
			Input.action_press("move_forward")
			if _sub_frames >= 300:
				_check(_max_z <= 30.05, "L%d 边界后退 z<=30 (max=%.2f)" % [_lv + 1, _max_z])
				_check(_min_margin > -1.2, "L%d 边界行走未跌穿 (min_margin=%.2f)" % [_lv + 1, _min_margin])
				Input.action_release("move_forward")
				_next_job()

func _run_cave() -> void:
	_track()
	var p: Vector3 = _player.global_position
	_cave_min_z = minf(_cave_min_z, p.z)
	match _cave_stage:
		"enter":
			_steer(-34.5, -83.0)
			Input.action_press("move_forward")
			if Vector2(p.x + 34.5, p.z + 83.0).length() < 3.0:
				_check(true, "L3 山洞内鹰徽点可达 (pos=%.1f, %.1f)" % [p.x, p.z])
				_cave_stage = "push"
				_gs_frames = 0
				_cave_start_z = p.z
			elif _job_frames > 1500:
				_check(false, "L3 山洞进入超时 (pos=%.1f, %.1f)" % [p.x, p.z])
				Input.action_release("move_forward")
				_next_job()
		"push":
			_main._yaw = PI
			Input.action_press("move_forward")
			_gs_frames += 1
			if _gs_frames >= 240:
				_check(_cave_min_z > -96.0, "L3 山洞是死胡同：向深处顶 4s 最深 z=%.2f (起点 %.2f)" % [_cave_min_z, _cave_start_z])
				_cave_stage = "exit"
		"exit":
			_steer(-33.0, -60.0)
			Input.action_press("move_forward")
			if p.z > -68.0:
				_check(true, "L3 山洞可从洞口退出 (z=%.1f)" % p.z)
				# 洞顶穿入复核：站到洞口上方支撑面，朝洞心跳走
				_cave_top_y = _level.get_support_y(-33.0, -77.0, 999.0)
				_teleport(-33.0, -77.0)
				_cave_stage = "top"
				_gs_frames = 0
				_cave_min_z = 999.0
			elif _job_frames > 3000:
				_check(false, "L3 山洞退出超时")
				Input.action_release("move_forward")
				_next_job()
		"top":
			_steer(-33.0, -83.0)
			Input.action_press("move_forward")
			_gs_frames += 1
			if _gs_frames % 40 == 1:
				Input.action_press("jump")
			elif _gs_frames % 40 == 3:
				Input.action_release("jump")
			if _gs_frames >= 300:
				Input.action_release("jump")
				var inside: bool = p.z < -74.0 and p.z > -92.0 and absf(p.x + 33.0) < 7.0 and p.y < _cave_top_y - 2.0
				print("  CAVE TOP: end pos=(%.1f, %.1f, %.1f) top_y=%.2f inside=%s" % [p.x, p.y, p.z, _cave_top_y, str(inside)])
				if inside:
					_cave_stage = "toppush"
					_gs_frames = 0
					_cave_min_z = p.z
				else:
					_check(true, "L3 洞顶复核：未穿入（停留在洞顶上方地形，无捷径问题）")
					Input.action_release("move_forward")
					_next_job()
		"toppush":
			_main._yaw = PI
			Input.action_press("move_forward")
			_gs_frames += 1
			_cave_min_z = minf(_cave_min_z, _player.global_position.z)
			if _gs_frames >= 240:
				_check(_cave_min_z > -96.0, "L3 穿顶落洞后仍是死胡同：最深 z=%.2f" % _cave_min_z)
				Input.action_release("move_forward")
				_next_job()
