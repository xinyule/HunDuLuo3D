extends SceneTree

## 1.2.0 第一波留证：L2 基地大厅净高 ×4（34.4m）截图
## 运行：xvfb-run godot --path . --script res://test/hall_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := "boot"
var _wait := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_phase = "load"
		"load":
			if _main.state == "dialog" and _main.level_index == 1 and is_instance_valid(_main.player):
				_main._advance_dialog()
				var lvl = _main.current_level
				_main.player.global_position = Vector3(0, lvl.get_support_y(0, -40, 999.0), -40)
				_main._yaw = PI
				_phase = "settle"
			elif _main.state != "loading" and _main.level_index != 1:
				_main._load_level(1)
		"settle":
			_wait += 1
			if _wait > 40:
				var img := root.get_texture().get_image()
				img.save_png(DIR + "hall_lv2.png")
				print("SNAP hall_lv2.png")
				quit()
