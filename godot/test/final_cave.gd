extends SceneTree

## 终检专项：L3 山洞支线复核（东口进出 / 洞内死胡同 / 洞顶穿入后仍死胡同）
## 洞口在东侧（x≈-28.7，两噪声巨石夹约 3.6m 门洞）；北/西/南三面岩墙带碰撞，顶板无碰撞。
## 运行：godot --headless --path . --script res://test/final_cave.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _pass := 0
var _fail := 0
var _phase := "boot"
var _wait := 0
var _level = null
var _player = null
var _stage := ""
var _sf := 0
var _min_x := 999.0
var _floor_y := 0.0

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

func _teleport(x: float, z: float) -> void:
	var y: float = _level.get_support_y(x, z, 999.0)
	_player.global_position = Vector3(x, y, z)
	_player.vy = 0.0
	_player.grounded = true

func _set_stage(s: String) -> void:
	_stage = s
	_sf = 0

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_phase = "load"
		"load":
			# 1.2.0 探针适配（dialog 门控，同 long_routes 口径）：旧版在 boot 里同步调
			# _load_level+读 player，异步协程下 player 为 Nil 报错且 boot 分支中断、永久卡死。
			if _main.state == "dialog" and _main.level_index == 2 and is_instance_valid(_main.player):
				_main._advance_dialog()
				_level = _main.current_level
				_player = _main.player
				_player.barrier = 99999.0
				_floor_y = _level.terrain_h(-33.0, -81.0)
				_teleport(-19.0, -81.0)
				_set_stage("enter")
				_phase = "run"
				_wait = 3
			elif _main.state != "loading" and _main.level_index != 2:
				_main._load_level(2)
		"run":
			if _wait > 0:
				_wait -= 1
				return
			_sf += 1
			_run()

func _run() -> void:
	var p: Vector3 = _player.global_position
	_min_x = minf(_min_x, p.x)
	match _stage:
		"enter":
			_steer(-34.5, -83.0)
			Input.action_press("move_forward")
			if Vector2(p.x + 34.5, p.z + 83.0).length() < 3.0:
				_check(true, "山洞东口可进入、洞内鹰徽点可达 (pos=%.1f, %.1f)" % [p.x, p.z])
				_min_x = p.x
				_set_stage("push")
			elif _sf > 1200:
				_check(false, "山洞进入超时 (pos=%.1f, %.1f)" % [p.x, p.z])
				_finish()
		"push":
			_main._yaw = -PI / 2.0 # 直西，顶西墙
			Input.action_press("move_forward")
			if _sf >= 240:
				_check(_min_x > -37.0, "洞内向西顶 4s 被西墙拦停 (min_x=%.2f，墙内面≈-36.6)" % _min_x)
				_check(p.z > -87.0 and p.z < -75.0, "顶墙期间人仍在洞内 (z=%.1f)" % p.z)
				_set_stage("exit")
		"exit":
			_steer(-19.0, -81.0)
			Input.action_press("move_forward")
			if p.x > -22.0:
				_check(true, "山洞可从东口退出 (x=%.1f)" % p.x)
				# 穿顶复核：直接置于洞室上方（顶板无碰撞），任其下落
				_player.global_position = Vector3(-33.0, _floor_y + 6.0, -81.0)
				_player.vy = 0.0
				_player.grounded = false
				_set_stage("fall")
			elif _sf > 1200:
				_check(false, "山洞退出超时 (pos=%.1f, %.1f)" % [p.x, p.z])
				_finish()
		"fall":
			Input.action_release("move_forward")
			if _sf >= 200:
				var inside: bool = absf(p.x + 33.0) < 5.0 and p.z > -87.0 and p.z < -75.0 and p.y < _floor_y + 1.2
				_check(inside, "洞顶无碰撞：从上方落下穿顶板落入洞内 (land=%.1f, %.1f, %.1f floor=%.2f)" % [p.x, p.y, p.z, _floor_y])
				_min_x = p.x
				_set_stage("toppush")
		"toppush":
			_main._yaw = -PI / 2.0
			Input.action_press("move_forward")
			if _sf >= 240:
				_check(_min_x > -37.0, "穿顶落洞后向西仍被拦停 (min_x=%.2f)——落点仍是死胡同" % _min_x)
				Input.action_release("move_forward")
				_finish()

func _finish() -> void:
	print("CAVE RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
