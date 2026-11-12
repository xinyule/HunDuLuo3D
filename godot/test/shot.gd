extends SceneTree

## 截图验证（Xvfb + llvmpipe 软件渲染）：菜单 / 第一关开局 / 迎敌三张
## 运行：xvfb-run godot --path . --script res://test/shot.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("SNAP ", path, " ", img.get_size())

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 40:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/menu.png")
				_main.start_game()
				_main._advance_dialog()
				_phase = 1
		1:
			if _frame > 130:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/level1_start.png")
				_main.player.global_position = Vector3(0, 0, 8)
				_phase = 2
		2:
			if _frame > 340:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/level1_combat.png")
				print("SHOTS DONE")
				quit(0)
