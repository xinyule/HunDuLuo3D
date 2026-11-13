extends SceneTree

## 第二线探针：地形起伏与室内夹层实走验证（真实输入驱动）
## ①每处 relief：数值显著性（中心高程 vs 四向环点均值，用 _base_height 免垫干扰）
##   + 从南侧步行实走登顶/下洼（到达且脚贴地形）②夹层：台阶实走登顶 + 板下穿行不被堵
## ③全关网格悬崖扫描：可玩走廊内 3m 步进相邻高差 ≤2.0（室外排除山脊带 |x|>width/2-26）
## 运行：godot --headless --path . --script res://test/long_relief.gd --fixed-fps 60

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
var _timeout := 0

var _level = null
var _player = null
var _lv := 0
var _max_y := -999.0

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
	for lv in Data.LEVELS.size():
		var d: Dictionary = Data.LEVELS[lv]
		_jobs.append({"kind": "grid", "lv": lv})
		for rf in d.get("relief", []):
			var job := {"kind": "relief", "lv": lv, "x": float(rf[0]), "z": float(rf[1]), "r": float(rf[2]), "h": float(rf[3]), "dir": Vector2(0, 1)}
			# L5 丘 (26,-444) 南侧直线被哨所房子挡住，改从北侧接近（真实玩法同样绕行）
			if lv == 4 and float(rf[0]) == 26.0 and float(rf[1]) == -444.0:
				job["dir"] = Vector2(0, -1)
			_jobs.append(job)
		for mz in d.get("mezzanines", []):
			_jobs.append({"kind": "mezz", "lv": lv, "x": float(mz[0]), "z": float(mz[1]), "w": float(mz[2]), "d": float(mz[3]), "top": float(mz[4])})
			_jobs.append({"kind": "under", "lv": lv, "x": float(mz[0]), "z": float(mz[1]), "w": float(mz[2]), "d": float(mz[3]), "top": float(mz[4])})

func _steer(tx: float, tz: float) -> void:
	var p: Vector3 = _player.global_position
	var dx := tx - p.x
	var dz := tz - p.z
	if dx * dx + dz * dz > 0.04:
		_main._yaw = atan2(dx, dz)

func _teleport(x: float, z: float) -> void:
	var y: float = _level.get_support_y(x, z, 999.0)
	_player.global_position = Vector3(x, y, z)
	_player.vy = 0.0
	_player.grounded = true

func _next_job() -> void:
	_job_i += 1
	if _job_i >= _jobs.size():
		print("RELIEF RESULT: %d passed, %d failed" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)
		return
	_job = _jobs[_job_i]
	_lv = int(_job["lv"])
	_phase = "setup"
	_wait = 0
	_job_frames = 0

func _setup_job() -> void:
	if _level == null or _main.current_level != _level or _lv != _cur_lv:
		_main._load_level(_lv)
		_main._advance_dialog()
		_level = _main.current_level
		_cur_lv = _lv
	_player = _main.player
	_player.barrier = 99999.0
	_max_y = -999.0
	var kind := String(_job["kind"])
	match kind:
		"grid":
			_grid_scan()
			_next_job()
			return
		"relief":
			var x := float(_job["x"])
			var z := float(_job["z"])
			var r := float(_job["r"])
			var h := float(_job["h"])
			# 数值显著性（_base_height：不含营地垫；环点排除山脊带 |x|>width/2-26，免被 rim 高程污染）
			var c: float = _level._base_height(x, z)
			var rim_lim := float(Data.LEVELS[_lv]["width"]) / 2.0 - 26.0
			var ring := 0.0
			var ring_n := 0
			for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var px: float = x + dir.x * (r + 11.0)
				if absf(px) > rim_lim:
					continue
				ring += _level._base_height(px, z + dir.y * (r + 11.0))
				ring_n += 1
			ring /= float(maxi(1, ring_n))
			var delta := c - ring
			if h > 0.0:
				_check(delta >= h * 0.40, "L%d 高地 (%.0f,%.0f) 显著性 Δ=%.2f >= %.2f（环点 %d 个）" % [_lv + 1, x, z, delta, h * 0.40, ring_n])
			else:
				_check(delta <= h * 0.40, "L%d 低洼 (%.0f,%.0f) 显著性 Δ=%.2f <= %.2f（环点 %d 个）" % [_lv + 1, x, z, delta, h * 0.40, ring_n])
			var adir: Vector2 = _job.get("dir", Vector2(0, 1))
			_teleport(x + adir.x * (r + 9.0), z + adir.y * (r + 9.0))
			_timeout = int((r + 9.0) / 0.09) + 150
			print("== L%d relief walk -> (%.0f, %.0f) h=%.1f ==" % [_lv + 1, x, z, h])
		"mezz":
			var mx := float(_job["x"])
			var mz := float(_job["z"])
			_teleport(mx, mz + float(_job["d"]) / 2.0 + 7.0)
			_timeout = 500
			print("== L%d mezz climb (%.0f, %.0f) ==" % [_lv + 1, mx, mz])
		"under":
			var mx2 := float(_job["x"])
			var mz2 := float(_job["z"])
			_teleport(mx2 - float(_job["w"]) / 2.0 - 7.0, mz2)
			_timeout = 500
			print("== L%d mezz under-pass (%.0f, %.0f) ==" % [_lv + 1, mx2, mz2])
	_phase = "run"
	_wait = 3

var _cur_lv := -1

func _grid_scan() -> void:
	var d: Dictionary = Data.LEVELS[_lv]
	var length := float(d["length"])
	var width := float(d["width"])
	var half: float = _level.playable_half_width()
	var rim_x := width / 2.0 - 26.0
	var cliffs := 0
	var max_step := 0.0
	var worst := Vector2.ZERO
	var xs: Array = []
	var x := -half + 2.0
	while x <= half - 2.0:
		xs.append(x)
		x += 3.0
	var prev: Array = []
	var z := 20.0
	while z >= -length + 14.0:
		var row: Array = []
		for i in xs.size():
			var xx := float(xs[i])
			var h: float = _level.terrain_h(xx, z)
			row.append(h)
			if absf(xx) <= rim_x:
				if i > 0 and absf(float(xs[i - 1])) <= rim_x:
					var s1: float = absf(h - float(row[i - 1]))
					if s1 > max_step:
						max_step = s1
						worst = Vector2(xx, z)
					if s1 > 2.0:
						cliffs += 1
				if prev.size() == xs.size():
					var s2: float = absf(h - float(prev[i]))
					if s2 > max_step:
						max_step = s2
						worst = Vector2(xx, z)
					if s2 > 2.0:
						cliffs += 1
		prev = row
		z -= 3.0
	print("== L%d grid scan: max_step=%.2f at (%.0f, %.0f), cliffs=%d ==" % [_lv + 1, max_step, worst.x, worst.y, cliffs])
	_check(cliffs == 0, "L%d 可玩走廊网格无悬崖（max_step=%.2f）" % [_lv + 1, max_step])

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
			_setup_job()
			return
		"run":
			if _wait > 0:
				_wait -= 1
				return
			_job_frames += 1
			_run_walk()

func _arrived(tx: float, tz: float, rad: float) -> bool:
	var p: Vector3 = _player.global_position
	return Vector2(p.x - tx, p.z - tz).length() < rad

func _run_walk() -> void:
	var kind := String(_job["kind"])
	var p: Vector3 = _player.global_position
	_max_y = maxf(_max_y, p.y)
	var tx := 0.0
	var tz := 0.0
	var rad := 1.1
	match kind:
		"relief":
			tx = float(_job["x"])
			tz = float(_job["z"])
		"mezz":
			tx = float(_job["x"])
			tz = float(_job["z"]) - 1.0
			rad = 1.3
		"under":
			tx = float(_job["x"]) + float(_job["w"]) / 2.0 + 7.0
			tz = float(_job["z"])
			rad = 1.3
	_steer(tx, tz)
	Input.action_press("move_forward")
	var done := _arrived(tx, tz, rad)
	if kind == "mezz" and p.y >= float(_job["top"]) - 0.35 and absf(p.x - tx) < 2.5 and p.z < float(_job["z"]) + 2.0:
		done = true
	if done or _job_frames > _timeout:
		Input.action_release("move_forward")
		if not done:
			_check(false, "L%d %s 实走超时未到达 (pos=%.1f, %.1f, %.1f)" % [_lv + 1, kind, p.x, p.y, p.z])
		else:
			match kind:
				"relief":
					var terr: float = _level.terrain_h(p.x, p.z)
					_check(absf(p.y - terr) < 1.0, "L%d relief (%.0f,%.0f) 步行到达且贴地 (y=%.2f terr=%.2f)" % [_lv + 1, float(_job["x"]), float(_job["z"]), p.y, terr])
				"mezz":
					_check(p.y >= float(_job["top"]) - 0.35, "L%d 夹层台阶登顶 (y=%.2f top=%.1f)" % [_lv + 1, p.y, float(_job["top"])])
				"under":
					_check(_max_y < 1.2, "L%d 夹层板下穿行未被堵/未被顶上平台 (max_y=%.2f)" % [_lv + 1, _max_y])
		_next_job()
