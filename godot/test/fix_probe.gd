extends SceneTree

## 1.1.0 第一线专项探针：空气墙与物品可达性
## ①逐关实测玩家横向可达边界（真实 update_player 驱动走到 stall）
## ②逐关鹰徽水平可达（实走接近到 <1.25m 算可达；塔顶徽只验水平）
## ③飞鹰落点：按巡逻半宽+绕回 overshoot 在最不利 x 掉信，验落地后玩家实走能拾取
## ④L2/L4 网格实走：逐行横穿，断言「房间内、无碰撞覆盖、却没走到」的格点为 0
## 运行：godot --headless --path . --script res://test/fix_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _pass := 0
var _fail := 0

var _jobs: Array = []
var _job_i := -1
var _job: Dictionary = {}
var _phase := "boot"
var _wait := 0

var _level = null
var _player = null
var _lv := 0

# 行走器状态
var _wk_target := Vector2.ZERO
var _wk_run := true
var _wk_frames := 0
var _wk_max := 0
var _wk_stall := 0
var _wk_last_d := 1e9
var _wk_sides := 0
var _wk_side_dir := 1.0
var _wk_max_x := 0.0
var _wk_min_x := 0.0
var _wk_visited: Dictionary = {}

var _letter_d: Dictionary = {}
var _falcon_stage := 0
var _falcon_frames := 0

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
		_jobs.append({"kind": "clamp", "lv": lv})
		_jobs.append({"kind": "emblems", "lv": lv})
		_jobs.append({"kind": "falcon", "lv": lv})
		if lv == 1 or lv == 3:
			_jobs.append({"kind": "grid", "lv": lv})

func _teleport(x: float, z: float) -> void:
	var y: float = _level.get_support_y(x, z, 999.0)
	_player.global_position = Vector3(x, y, z)
	_player.vy = 0.0
	_player.grounded = true

func _walk_begin(tx: float, tz: float, run: bool, max_frames: int, keep_visited: bool = false) -> void:
	_wk_target = Vector2(tx, tz)
	_wk_run = run
	_wk_frames = 0
	_wk_max = max_frames
	_wk_stall = 0
	_wk_last_d = 1e9
	_wk_sides = 0
	_wk_side_dir = 1.0
	_wk_max_x = _player.global_position.x
	_wk_min_x = _player.global_position.x
	if not keep_visited:
		_wk_visited.clear()

func _walk_step() -> bool:
	# 返回 true 表示行走结束（到达/stall/超时）
	var p: Vector3 = _player.global_position
	var dx := _wk_target.x - p.x
	var dz := _wk_target.y - p.z
	var dist := sqrt(dx * dx + dz * dz)
	_wk_frames += 1
	_wk_max_x = maxf(_wk_max_x, p.x)
	_wk_min_x = minf(_wk_min_x, p.x)
	_wk_visited[int(round(p.x * 0.5))] = true
	if dist < _wk_last_d - 0.005:
		_wk_last_d = dist
		_wk_stall = 0
	else:
		_wk_stall += 1
	if _wk_stall >= 30:
		if _wk_sides < 6:
			_wk_sides += 1
			_wk_side_dir = -_wk_side_dir
			_teleport(p.x, p.z + 3.0 * _wk_side_dir)
			_wk_stall = 0
			_wk_last_d = 1e9
			return false
		return true
	if _wk_frames >= _wk_max:
		return true
	var yaw := atan2(dx, dz)
	var snap := {"move": Vector2(0, -1), "jump": false, "prone": false, "run": _wk_run}
	_player.update_player(1.0 / 60.0, snap, _level, yaw, 0.0, false)
	return false

func _next_job() -> void:
	_job_i += 1
	if _job_i >= _jobs.size():
		print("FIXPROBE RESULT: %d passed, %d failed" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)
		return
	_job = _jobs[_job_i]
	_lv = int(_job["lv"])
	_phase = "setup"
	_wait = 0

func _setup_level() -> void:
	_main._load_level(_lv)
	_main._advance_dialog()
	_level = _main.current_level
	_player = _main.player
	_player.barrier = 99999.0
	_main.set_process(false)

func _on_frame() -> void:
	_frame += 1
	if _phase == "boot":
		if _frame == 30:
			_main._set_char("bill")
			_main.start_game()
			_main._advance_dialog()
			_next_job()
		return
	if _phase == "setup":
		_wait += 1
		if _wait >= 3:
			_setup_level()
			_phase = String(_job["kind"]) + "_init"
		return
	match String(_job["kind"]):
		"clamp": _do_clamp()
		"emblems": _do_emblems()
		"falcon": _do_falcon()
		"grid": _do_grid()

# ---------------- ① 钳制实测 ----------------
var _clamp_stage := 0
var _clamp_stations: Array = []
var _clamp_results: Array = []

func _do_clamp() -> void:
	if _phase == "clamp_init":
		var len_: float = float(Data.LEVELS[_lv]["length"])
		_clamp_stations = [0.0, -len_ * 0.5, -len_ + 16.0]
		_clamp_stage = 0
		_clamp_results.clear()
		_start_clamp_station()
		_phase = "clamp_run"
		return
	if _phase == "clamp_run":
		if _walk_step():
			_clamp_results.append(_wk_max_x)
			_clamp_stage += 1
			if _clamp_stage >= _clamp_stations.size():
				var w: float = float(Data.LEVELS[_lv]["width"])
				var rh := 1e9
				for r in _clamp_results:
					rh = minf(rh, float(r))
				var msg := "L%d 可达半宽实测 %.2f（关卡半宽 %.1f）stations=%s" % [_lv + 1, rh, w / 2.0, str(_clamp_results)]
				print("  ", msg)
				_job["rh"] = rh
				_next_job()
			else:
				_start_clamp_station()

func _start_clamp_station() -> void:
	var z: float = float(_clamp_stations[_clamp_stage])
	_teleport(0.0, z)
	_walk_begin(float(Data.LEVELS[_lv]["width"]) / 2.0 + 40.0, z, true, 1500)

# ---------------- ② 鹰徽可达 ----------------
var _emb_i := 0

func _do_emblems() -> void:
	var es: Array = Data.LEVELS[_lv].get("emblems", [])
	if _phase == "emblems_init":
		_emb_i = 0
		if es.is_empty():
			_next_job()
			return
		_start_emblem(es)
		_phase = "emblems_run"
		return
	if _phase == "emblems_run":
		var e: Array = es[_emb_i]
		var ex := float(e[0])
		var ez := float(e[1])
		var p: Vector3 = _player.global_position
		var d2d := Vector2(p.x - ex, p.z - ez).length()
		if d2d < 1.25 or _walk_step():
			_check(d2d < 1.25, "L%d 鹰徽%d (%.1f, %.1f) 水平可达（止步于 %.1f）" % [_lv + 1, _emb_i + 1, ex, ez, d2d])
			_emb_i += 1
			if _emb_i >= es.size():
				_next_job()
			else:
				_start_emblem(es)

func _start_emblem(es: Array) -> void:
	var e: Array = es[_emb_i]
	_teleport(0.0, float(e[1]))
	_walk_begin(float(e[0]), float(e[1]), true, 1200)

# ---------------- ③ 飞鹰落点 ----------------
func _do_falcon() -> void:
	var pk = _level.pickups
	if _phase == "falcon_init":
		_player.barrier = 99999.0
		_teleport(0.0, 26.0)
		var half := 44.0
		if pk._falcons.size() > 0:
			half = float(pk._falcons[0]["half"])
		var drop_x: float = half + 9.0
		_job["drop_x"] = drop_x
		_job["sx"] = 1.0
		_falcon_shoot(drop_x)
		_falcon_stage = 0
		_falcon_frames = 0
		_phase = "falcon_run"
		return
	if _phase == "falcon_run":
		_falcon_frames += 1
		if _falcon_stage == 0:
			pk.update_pickups(1.0 / 60.0, _player, _level)
			if _letter_d.is_empty():
				_check(false, "L%d 飞鹰落点：掉信未登记" % (_lv + 1))
				_next_job()
				return
			if bool(_letter_d.get("landed", false)) or _falcon_frames > 900:
				var g: Node3D = _letter_d["group"]
				_job["lx"] = g.position.x
				_job["lz"] = g.position.z
				_teleport(0.0, g.position.z)
				_walk_begin(g.position.x, g.position.z, true, 1500)
				_falcon_stage = 1
		else:
			var done := _walk_step()
			pk.update_pickups(1.0 / 60.0, _player, _level)
			if not pk._letters.has(_letter_d):
				_check(true, "L%d 飞鹰落点 x=%.1f（掉信 x=%.1f）玩家实走拾取成功" % [_lv + 1, float(_job["lx"]), float(_job["drop_x"]) * float(_job["sx"])])
				if float(_job["sx"]) > 0.0:
					_job["sx"] = -1.0
					_phase = "falcon_init2"
				else:
					_next_job()
				return
			if done:
				_check(false, "L%d 飞鹰落点 x=%.1f（掉信 x=%.1f）玩家实走拾取失败" % [_lv + 1, float(_job["lx"]), float(_job["drop_x"]) * float(_job["sx"])])
				if float(_job["sx"]) > 0.0:
					_job["sx"] = -1.0
					_phase = "falcon_init2"
				else:
					_next_job()
				return
	if _phase == "falcon_init2":
		_teleport(0.0, 26.0)
		var drop_x: float = float(_job["drop_x"])
		_falcon_shoot(-drop_x)
		_falcon_stage = 0
		_falcon_frames = 0
		_phase = "falcon_run"

## 把一只活飞鹰挪到指定 x/z 并走生产路径击落（_falcon_hit → spawn_letter）
func _falcon_shoot(at_x: float) -> void:
	var pk = _level.pickups
	pk.update_pickups(0.0, _player, _level) # 与生产一致：先登记关卡引用（掉信钳制依赖它）
	_letter_d = {}
	for f in pk._falcons:
		var tg = f["target"]
		if tg.alive:
			var g: Node3D = f["group"]
			g.position = Vector3(at_x, 8.0, -60.0)
			var before: int = pk._letters.size()
			pk._falcon_hit(tg)
			if pk._letters.size() > before:
				_letter_d = pk._letters[pk._letters.size() - 1]
			return

# ---------------- ④ 网格实走（仅 L2/L4） ----------------
var _grid_rows: Array = []
var _grid_row_i := 0
var _grid_fail_cells: Array = []

func _do_grid() -> void:
	var w: float = float(Data.LEVELS[_lv]["width"])
	var len_: float = float(Data.LEVELS[_lv]["length"])
	if _phase == "grid_init":
		_grid_rows.clear()
		_grid_fail_cells.clear()
		var z := 20.0
		while z >= -len_ + 12.0:
			_grid_rows.append(z)
			z -= 10.0
		_grid_row_i = 0
		_start_grid_row()
		_phase = "grid_run"
		return
	if _phase == "grid_run":
		if _walk_step():
			if _grid_leg == 0:
				# 左程到墙后接右程（visited 跨程保留，整行覆盖才算数）
				_grid_leg = 1
				var w2: float = float(Data.LEVELS[_lv]["width"])
				var z2: float = float(_grid_rows[_grid_row_i])
				_walk_begin(w2 / 2.0 + 40.0, z2, true, 2200, true)
				return
			_eval_grid_row()
			_grid_row_i += 1
			if _grid_row_i >= _grid_rows.size():
				_check(_grid_fail_cells.is_empty(), "L%d 网格实走：%d 行，空气墙格点 %d 个 %s" % [_lv + 1, _grid_rows.size(), _grid_fail_cells.size(), str(_grid_fail_cells.slice(0, 6))])
				_next_job()
			else:
				_start_grid_row()

var _grid_leg := 0

func _start_grid_row() -> void:
	var w: float = float(Data.LEVELS[_lv]["width"])
	var z: float = float(_grid_rows[_grid_row_i])
	_grid_leg = 0
	_teleport(0.0, z)
	_walk_begin(-w / 2.0 - 40.0, z, true, 2200)

func _eval_grid_row() -> void:
	var w: float = float(Data.LEVELS[_lv]["width"])
	var z: float = float(_grid_rows[_grid_row_i])
	var face := w / 2.0 + 0.6 # 基地侧墙内面
	var cx := -face + 1.0
	while cx <= face - 1.0:
		var visited: bool = _wk_visited.has(int(round(cx * 0.5)))
		if not visited and not _cell_covered(cx, z):
			_grid_fail_cells.append("(%.0f, %.0f)" % [cx, z])
		cx += 2.0

func _cell_covered(cx: float, z: float) -> bool:
	for c in _level.colliders:
		if c.get("disabled", false) or c.get("no_collide", false):
			continue
		var y0 := float(c.get("y0", 0.0))
		var top := y0 + float(c.get("h", 6.0))
		if top <= 0.55 or y0 >= 1.55:
			continue
		if c["type"] == "box":
			if absf(cx - float(c["x"])) <= float(c["w"]) / 2.0 + 0.4 and absf(z - float(c["z"])) <= float(c["d"]) / 2.0 + 0.4:
				return true
		elif c["type"] == "circle":
			var dx := cx - float(c["x"])
			var dz := z - float(c["z"])
			var r := float(c["r"]) + 0.4
			if dx * dx + dz * dz <= r * r:
				return true
	return false
