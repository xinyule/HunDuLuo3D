extends SceneTree

## 直达截图：第1关出生点望向关卡深处（跳过菜单特写阶段，省软件渲染时间）
## 运行：xvfb-run godot --path . --script res://test/shot3.gd --rendering-driver opengl3 --resolution 1280x720

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
	print("SNAP ", path)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 5:
				_main.start_game()
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				var lv = _main.current_level
				lv._spawn_enemy("rifleman", 2.0, _main.player.global_position.z - 7.0)
				lv._spawn_enemy("runner", -2.5, _main.player.global_position.z - 9.0)
				_phase = 1
		1:
			if _frame > 45:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/chars_fight2.png")
				print("SHOT3 DONE")
				quit(0)
