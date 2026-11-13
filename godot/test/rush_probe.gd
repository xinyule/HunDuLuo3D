extends SceneTree

## 1.2.0 封锁点专探针（L1）：只前进不射击必须被第一个封锁点拦停；清场后墙落；
## 回头路进已清区不重锁；继续狂奔在第二个封锁点再被拦。
## 运行：godot --headless --path . --script res://test/rush_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := "boot"
var _t := 0
var _pass := 0
var _fail := 0
var _max_dist := 0.0
var _stall_t := 0
var _last_dist := 0.0
var _lane_x := 0.0

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

func _dist() -> float:
	return _main.current_level.player_dist(_main.player)

func _drive(tx: float, tz: float) -> void:
	var p: Vector3 = _main.player.global_position
	_main._yaw = atan2(tx - p.x, tz - p.z)
	Input.action_press("move_forward")

const _LANES := [0.0, 8.0, -8.0, 16.0, -16.0, 24.0, -24.0, 32.0, -32.0, 40.0, -40.0]
var _lane_i := 0
var _prog_d := 0.0
var _prog_t := 0
var _prog_pos := Vector3.ZERO

# 向前驱动（带卡住换道：营地建筑排挡路时依次换道驻留绕行，不用探针侧作弊穿墙）
# 注：L1 河心木桥台面比河底高 1.35m、超玩家 0.55 台阶规则——须沿桥边横滑绕行
# （真人玩家同样涉水绕行，路线探针走 ±28 车道已证）；故卡住判定看任意方向位移，不只看 dist
func _drive_fwd() -> void:
	var pp: Vector3 = _main.player.global_position
	if Vector2(pp.x - _prog_pos.x, pp.z - _prog_pos.z).length() > 0.5:
		_prog_pos = pp
		_prog_t = 0
	else:
		_prog_t += 1
		if _prog_t > 200:
			_prog_t = 0
			_lane_i = (_lane_i + 1) % _LANES.size()
			_lane_x = _LANES[_lane_i]
	_drive(_lane_x, -400.0)

func _on_frame() -> void:
	_frame += 1
	var lvl = _main.current_level
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_phase = "enter"
		"enter":
			if _main.state == "dialog":
				_main._advance_dialog()
				_main.player.barrier = 99999.0
				_phase = "rush1"
				_t = 0
			elif _frame > 3000:
				_check(false, "进入 L1 超时")
				_finish()
		"rush1":
			_t += 1
			_drive_fwd()
			var d := _dist()
			_max_dist = maxf(_max_dist, d)
			var lk: Dictionary = lvl.locks[0]
			if bool(lk["active"]):
				if d > _last_dist + 0.02:
					_stall_t = 0
				else:
					_stall_t += 1
				if _stall_t > 180:
					_check(_max_dist <= float(lk["exit"]) + 2.0, "狂奔在封锁点 1 被拦停（max_dist=%.1f，墙在 %.0f）" % [_max_dist, float(lk["exit"])])
					_check(not lvl.boss_activated, "未到达 Boss（封锁有效）")
					_phase = "clear"
					_t = 0
			elif _t > 60 * 90:
				_check(false, "封锁点 1 未激活或未拦停（max_dist=%.1f）" % _max_dist)
				_finish()
			_last_dist = d
		"clear":
			Input.action_release("move_forward")
			var lk2: Dictionary = lvl.locks[0]
			for e in lk2["members"]:
				if is_instance_valid(e) and e.alive:
					e.on_hit(9999)
			_t += 1
			if bool(lk2["cleared"]):
				_check(bool(lk2["collider"]["disabled"]), "肃清后封锁墙落下（碰撞关闭）")
				_phase = "rush2"
				_t = 0
				_max_dist = 0.0
			elif _t > 300:
				_check(false, "清场后封锁未解除")
				_finish()
		"rush2":
			_t += 1
			_drive_fwd()
			var lk3: Dictionary = lvl.locks[0]
			if _dist() > float(lk3["exit"]) + 12.0:
				_check(true, "墙落后可穿过原封锁点（dist=%.1f）" % _dist())
				_phase = "back"
				_t = 0
			elif _t > 60 * 20:
				_check(false, "墙落后仍过不去（dist=%.1f）" % _dist())
				_finish()
		"back":
			_t += 1
			_drive(_lane_x, 30.0) # 回头跑出已清区
			var lk4: Dictionary = lvl.locks[0]
			if _dist() < float(lk4["entry"]) - 6.0:
				_phase = "again"
				_t = 0
			elif _t > 60 * 20:
				_check(false, "回头路超时")
				_finish()
		"again":
			_t += 1
			_drive_fwd()
			var lk5: Dictionary = lvl.locks[0]
			if _dist() > float(lk5["exit"]) + 12.0:
				_check(not bool(lk5["active"]) and bool(lk5["cleared"]), "回头路进已清区不重锁、畅通穿过")
				_phase = "rush3"
				_t = 0
				_stall_t = 0
				_last_dist = _dist()
				_max_dist = 0.0
			elif _t > 60 * 25:
				_check(false, "已清区重锁或无法穿过（active=%s dist=%.1f）" % [str(lk5["active"]), _dist()])
				_finish()
		"rush3":
			_t += 1
			_drive_fwd()
			var d2 := _dist()
			_max_dist = maxf(_max_dist, d2)
			var lk6: Dictionary = lvl.locks[1]
			if bool(lk6["active"]):
				if d2 > _last_dist + 0.02:
					_stall_t = 0
				else:
					_stall_t += 1
				if _stall_t > 180:
					_check(_max_dist <= float(lk6["exit"]) + 2.0, "狂奔在封锁点 2 再被拦停（max_dist=%.1f，墙在 %.0f）" % [_max_dist, float(lk6["exit"])])
					_finish()
			elif _t > 60 * 45:
				_check(false, "封锁点 2 未激活或未拦停（max_dist=%.1f）" % _max_dist)
				_finish()
			_last_dist = d2

func _finish() -> void:
	Input.action_release("move_forward")
	print("RUSH RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
