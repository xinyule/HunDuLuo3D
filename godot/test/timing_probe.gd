extends SceneTree

## 跑图计时探针（调平校准专用，非回归测试）：
## combat 模式：无敌机器人沿主路线实打通关（移动/射击全走真实链路，barrier 吸收伤害不死），
##   记录每关从进入 playing 到 Boss 死亡的游戏秒数；
## routes 模式：幽灵疾跑沿指定横向车道走到 Boss 触发/电网门/推进尽头，量各路线行进长度。
## 运行：godot --headless --path . --script res://test/timing_probe.gd --fixed-fps 60
## 环境变量：PROBE_MODE=combat|routes（默认 combat）、PROBE_TS=2（Engine.time_scale，默认 2）

var _main: Node
var _frame := 0
var _mode := "combat"
var _dtg := 1.0 / 30.0 # 每帧游戏秒 = time_scale/60

# combat 状态
var _cur := -1
var _start_frame := 0
var _boss_death_frame := 0
var _results: Array = []
var _last_pos := Vector3.INF
var _path_len := 0.0
var _track_target: Object = null
var _track_hp := -1
var _track_since := 0.0
var _close_in := false
var _watch_pos := Vector3.INF
var _watch_acc := 0.0
var _watch_foes := -1
var _no_prog := 0
var _detour := Vector2.ZERO
var _detour_left := 0.0
var _detour_sign := 1.0

# routes 状态
var _r_level := 0
var _r_lane_i := 0
var _r_active := false
var _r_start := 0
var _r_last_pos := Vector3.INF
var _r_len := 0.0
var _r_last_z := 0.0
var _r_still := 0.0

const LEVEL_TIMEOUT := 1500.0 # 单关游戏秒上限（防卡死）

func _initialize() -> void:
	_mode = OS.get_environment("PROBE_MODE")
	if _mode == "":
		_mode = "combat"
	var ts := 2.0
	var ts_s := OS.get_environment("PROBE_TS")
	if ts_s != "":
		ts = float(ts_s)
	var fps := 60.0
	var fps_s := OS.get_environment("PROBE_FPS")
	if fps_s != "":
		fps = float(fps_s)
	Engine.time_scale = ts
	_dtg = ts / fps
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)
	print("PROBE START mode=%s ts=%.1f" % [_mode, ts])

func _release_keys() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "run"]:
		Input.action_release(a)

var _booted := false

func _on_frame() -> void:
	_frame += 1
	if not _booted:
		if _frame >= 3 and _main.state == "menu":
			_main.start_game()
			_booted = true
		return
	if _mode == "routes":
		_routes_step()
	else:
		_combat_step()

# ---------------- combat ----------------
func _combat_step() -> void:
	var st: String = _main.state
	if _cur == -1:
		if st == "dialog":
			var only := OS.get_environment("PROBE_ONLY")
			if only != "" and _main.level_index != int(only):
				_main._load_level(int(only))
				return
			_begin_level(_main.level_index)
		return
	if _main.level_index != _cur:
		# 已被主流程推进到下一关（dialog 待推进）
		if st == "dialog":
			_begin_level(_main.level_index)
		return
	if st == "victory":
		_finish_combat()
		return
	if st == "dialog":
		_begin_level(_cur)
		return
	if st != "playing":
		return
	var lv = _main.current_level
	var player = _main.player
	if lv == null or player == null:
		return
	# Boss 死亡时刻
	if _boss_death_frame == 0 and lv.boss_activated and lv.boss != null and not lv.boss.alive:
		_boss_death_frame = _frame
		var t := float(_frame - _start_frame) * _dtg
		_results.append([_cur + 1, t, _path_len])
		print("LEVEL TIME L%d %.1fs path=%.0fm" % [_cur + 1, t, _path_len])
		_release_keys()
		return
	if _boss_death_frame != 0:
		_release_keys()
		return
	# 超时保护
	var timeout := LEVEL_TIMEOUT
	var to_s := OS.get_environment("PROBE_TIMEOUT")
	if to_s != "":
		timeout = float(to_s)
	if float(_frame - _start_frame) * _dtg > timeout:
		print("LEVEL TIMEOUT L%d" % (_cur + 1))
		_results.append([_cur + 1, -1.0, _path_len])
		_release_keys()
		if _cur >= 7:
			_finish_combat()
		else:
			_main._load_level(_cur + 1)
			_cur = _main.level_index
			_boss_death_frame = 0
		return
	_bot_act()

func _begin_level(idx: int) -> void:
	_main._advance_dialog()
	_main.lives_inf = true
	_main.lives = 99
	_main.player.barrier = 999999.0
	_cur = idx
	_start_frame = _frame
	_boss_death_frame = 0
	_path_len = 0.0
	_last_pos = Vector3.INF
	_track_target = null
	_close_in = false
	_watch_pos = Vector3.INF
	_watch_foes = -1
	_no_prog = 0
	_detour_left = 0.0
	print("LEVEL BEGIN L%d len=%d" % [idx + 1, int(_main.current_level.length)])

func _finish_combat() -> void:
	print("PROBE COMBAT DONE")
	for r in _results:
		print("RESULT L%d time=%.1f path=%.0f" % [int(r[0]), float(r[1]), float(r[2])])
	quit(0)

func _bot_act() -> void:
	var lv = _main.current_level
	var player = _main.player
	var p: Vector3 = player.global_position
	if _last_pos != Vector3.INF:
		_path_len += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	var dist: float = lv.player_dist(player)
	var target: Object = null
	var move_to := Vector2(0, -lv.length - 10.0)
	var has_move := true
	var shoot := false
	if lv.boss_activated and lv.boss != null and lv.boss.alive:
		var parts: Array = []
		var vuln: Array = []
		for pt in lv.boss.targets:
			if pt.alive and pt.targetable:
				parts.append(pt)
				if pt.vulnerable:
					vuln.append(pt)
		var cand: Array = vuln if vuln.size() > 0 else parts
		# 非核心优先（先塔/荚舱后核心）
		cand.sort_custom(func(a, b): return int(a.is_core) < int(b.is_core))
		if cand.size() > 0:
			target = cand[0]
			shoot = true
		move_to = Vector2(0, lv.boss_z + 13.0)
	else:
		# 电网门：找第一道未开的门，接近时先去感应器位、到位后射感应器
		var gate = null
		for g in lv.gates:
			if not bool(g["open"]):
				gate = g
				break
		if gate != null:
			var gd := 26.0 - float(gate["z"])
			var s = gate["sensor"]
			if dist > gd - 13.0:
				move_to = Vector2(s.hit_x, float(gate["z"]) + 10.0)
			else:
				target = s
				shoot = true
				move_to = Vector2(s.hit_x, float(gate["z"]) + 9.0)
				has_move = false
		if target == null:
			# 最近的敌人（前方优先，身后只理 22m 内）
			var best: Object = null
			var best_d := 1e9
			var fwd := Vector2(sin(_main._yaw), cos(_main._yaw))
			for e in lv.enemies:
				if not e.alive:
					continue
				var ep: Vector3 = e.global_position
				var d := p.distance_to(ep)
				if d > 48.0:
					continue
				var to := Vector2(ep.x - p.x, ep.z - p.z)
				var front := to.length() < 0.01 or to.normalized().dot(fwd) > -0.2
				if not front and d > 22.0:
					continue
				if d < best_d:
					best_d = d
					best = e
			if best != null:
				if best_d > 26.0:
					move_to = Vector2(best.global_position.x, best.global_position.z)
				else:
					target = best
					shoot = true
					has_move = false
	if _frame % 300 == 0:
		var alive_n := 0
		for e in lv.enemies:
			if e.alive:
				alive_n += 1
		print("BOT L%d t=%.0f pos=(%.0f,%.1f,%.0f) dist=%.0f tgt=%s boss=%s/%s foes=%d ci=%s mv=%s sh=%s" % [
			_cur + 1, float(_frame - _start_frame) * _dtg, p.x, p.y, p.z, dist,
			("-" if target == null else "hp%s@%.0f,%.0f" % [str(target.get("hp")), target.hit_x, target.hit_z]),
			str(lv.boss_activated), str(lv.boss.alive if lv.boss else "-"), alive_n,
			str(_close_in), str(has_move), str(shoot)])
	# 卡关检测：同一目标打了 4 秒血没掉 → 靠近到 15m
	if target != null:
		if target != _track_target:
			_track_target = target
			_track_hp = int(target.get("hp"))
			_track_since = 0.0
			_close_in = false
		else:
			_track_since += _dtg
			if int(target.get("hp")) < _track_hp:
				_track_hp = int(target.get("hp"))
				_track_since = 0.0
			elif _track_since > 4.0:
				_close_in = true
	else:
		_track_target = null
		_close_in = false
	# 防卡死绕行：每 3 秒采样——位移 <1m 且敌人数未减（射击被挡/被道具楔住）累计 3 次 → 横向绕行换角度
	_watch_acc += _dtg
	if _watch_acc >= 3.0:
		_watch_acc = 0.0
		var foes_now := 0
		for e in lv.enemies:
			if e.alive:
				foes_now += 1
		var progressed := false
		if _watch_pos != Vector3.INF:
			progressed = p.distance_to(_watch_pos) >= 1.0 or foes_now < _watch_foes
		_watch_foes = foes_now
		if progressed or lv.boss_activated:
			_no_prog = 0
		else:
			_no_prog += 1
		if _no_prog >= 3 and _detour_left <= 0.0:
			_no_prog = 0
			_detour_sign = -_detour_sign
			_detour = Vector2(p.x + 13.0 * _detour_sign, p.z - 5.0)
			_detour_left = 2.6
		_watch_pos = p
	if _detour_left > 0.0:
		_detour_left -= _dtg
		_release_keys()
		var dd := Vector2(_detour.x - p.x, _detour.y - p.z)
		if dd.length() > 1.2:
			_main._yaw = atan2(dd.x, dd.y)
			Input.action_press("move_forward")
		if dd.length() <= 1.2:
			_detour_left = 0.0
		return
	if shoot and target != null and not _close_in:
		_release_keys()
		_main._yaw = atan2(target.hit_x - p.x, target.hit_z - p.z)
		player.try_shoot(_main.projectiles, Vector3(target.hit_x, target.hit_y, target.hit_z))
		return
	# 移动（走路 7.5，不疾跑——校准基准）
	_release_keys()
	var dest := move_to
	if _close_in and target != null:
		dest = Vector2(target.hit_x, target.hit_z)
		if Vector2(p.x, p.z).distance_to(dest) < 7.0:
			_close_in = false
			_track_since = 0.0
	var d := Vector2(dest.x - p.x, dest.y - p.z)
	if has_move or _close_in:
		if d.length() > 0.9:
			_main._yaw = atan2(d.x, d.y)
			Input.action_press("move_forward")
	elif target != null:
		_main._yaw = atan2(target.hit_x - p.x, target.hit_z - p.z)
		player.try_shoot(_main.projectiles, Vector3(target.hit_x, target.hit_y, target.hit_z))

# ---------------- routes ----------------
func _lanes_for(lv) -> Array:
	var hw: float = lv.width / 2.0 - 20.0
	return [0.0, -hw, hw]

func _routes_step() -> void:
	var st: String = _main.state
	if not _r_active:
		if _r_level == 0 and _frame < 5:
			return
		if _r_level >= 8:
			print("PROBE ROUTES DONE")
			quit(0)
			return
		_main._load_level(_r_level)
		_main._advance_dialog()
		_main.lives_inf = true
		_main.player.barrier = 999999.0
		_r_active = true
		_r_start = _frame
		_r_len = 0.0
		_r_last_pos = Vector3.INF
		_r_still = 0.0
		_r_last_z = _main.player.global_position.z
		return
	var lv = _main.current_level
	var player = _main.player
	var p: Vector3 = player.global_position
	if _r_last_pos != Vector3.INF:
		_r_len += Vector2(p.x - _r_last_pos.x, p.z - _r_last_pos.z).length()
	_r_last_pos = p
	var lanes := _lanes_for(lv)
	var lane_x: float = lanes[_r_lane_i]
	var t := float(_frame - _r_start) * _dtg
	var end_reason := ""
	if lv.boss_activated:
		end_reason = "boss"
	elif lv.player_dist(player) >= lv.length - 10.0:
		end_reason = "dist"
	elif t > 300.0:
		end_reason = "timeout"
	else:
		if absf(p.z - _r_last_z) < 0.02:
			_r_still += _dtg
		else:
			_r_still = 0.0
		_r_last_z = p.z
		if _r_still > 4.0:
			end_reason = "blocked"
	if end_reason != "":
		_release_keys()
		print("ROUTE L%d lane=%+.0f len=%.0fm time=%.0fs end=%s" % [_r_level + 1, lane_x, _r_len, t, end_reason])
		_r_lane_i += 1
		if _r_lane_i >= lanes.size():
			_r_lane_i = 0
			_r_level += 1
		_r_active = false
		return
	# 疾跑沿车道推进（长度与速度无关，只量路径）
	_release_keys()
	var wp := Vector2(lane_x, p.z - 80.0)
	var d := Vector2(wp.x - p.x, wp.y - p.z)
	_main._yaw = atan2(d.x, d.y)
	Input.action_press("move_forward")
	Input.action_press("run")
