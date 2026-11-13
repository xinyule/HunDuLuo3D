extends SceneTree

## 倾斜数值探针（无头）：L2 室内冻结主循环，直调 update_player 瞄准+右移 90 帧，
## 打印稳定后的 _hip_yaw（rad/deg）——倾斜幅度的硬证据，改前/改后各跑一次。
## 运行：godot --headless --path . --script res://test/fix_lean_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame == 20:
				_main._set_char("bill")
				_main.start_game()
				_main._load_level(1) # L2 室内（加载快）
				_main._advance_dialog()
				var lv = _main.current_level
				var pl = _main.player
				pl.global_position = Vector3(0.0, lv.get_support_y(0.0, 10.0, 999.0), 10.0)
				pl.grounded = true
				pl.vy = 0.0
				_main.set_process(false)
				_phase = 1
		1:
			var pl2 = _main.player
			var snap := {"move": Vector2(1, 0), "jump": false, "prone": false, "run": false}
			for i in 90:
				pl2.update_player(1.0 / 60.0, snap, _main.current_level, PI, 0.0, true)
			print("LEANPROBE hip_yaw=%.4f rad (%.2f deg) speed=%.2f" % [pl2._hip_yaw, rad_to_deg(pl2._hip_yaw), pl2._move_speed])
			quit(0)
