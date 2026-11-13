extends SceneTree

## 1.1.0 第一线对比截图（单项）：主角瞄准侧移姿态（髋部倾斜），L1 日光下拍
## 用法：xvfb-run -a godot --path . --script res://test/fix_lean_shot.gd --rendering-driver opengl3 --resolution 1280x720 -- before|after

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0
var _mark := 0
var _tag := "before"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_tag = String(args[0])
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	if _phase == 3:
		var pl2 = _main.player
		var lv2 = _main.current_level
		var snap := {"move": Vector2(1, 0), "jump": false, "prone": false, "run": false}
		pl2.update_player(1.0 / 60.0, snap, lv2, PI, 0.0, true)
		if _frame >= _mark:
			_phase = 4
		return
	if _frame < _mark:
		return
	match _phase:
		0:
			_main._set_char("bill")
			_main.start_game()
			_main._advance_dialog()
			_mark = _frame + 15
			_phase = 1
		1:
			var lv = _main.current_level
			var pl = _main.player
			pl.invuln = 9999.0
			pl.global_position = Vector3(-14.0, lv.get_support_y(-14.0, 16.0, 999.0), 16.0)
			pl.grounded = true
			pl.vy = 0.0
			_mark = _frame + 45
			_phase = 2
		2:
			_main.set_process(false)
			_mark = _frame + 75
			_phase = 3
		4:
			var pl3 = _main.player
			print("LEAN hip_yaw=%.4f rad (%.1f deg)" % [pl3._hip_yaw, rad_to_deg(pl3._hip_yaw)])
			_snap("fix_lean_%s.png" % _tag)
			print("LEAN SHOT DONE ", _tag)
			quit(0)
