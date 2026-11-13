extends SceneTree

## 角色视觉自检（游戏内取景）：菜单比尔/兰斯正面近景、局内迎敌、敌人死亡动画中途帧
## 运行：xvfb-run godot --path . --script res://test/shot2.gd --rendering-driver opengl3 --resolution 1280x720

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
			if _frame > 40:
				_main.ui.visible = false
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/menu_bill2.png")
				_main._set_char("lance")
				_phase = 1
		1:
			if _frame > 75:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/menu_lance2.png")
				_main._set_char("bill")
				_main.start_game()
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				var lv = _main.current_level
				lv._spawn_enemy("rifleman", 2.0, _main.player.global_position.z - 7.0)
				lv._spawn_enemy("runner", -2.5, _main.player.global_position.z - 9.0)
				_phase = 2
		2:
			if _frame > 105:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/chars_fight2.png")
				for e in _main.current_level.enemies:
					if e.type == "rifleman":
						e.on_hit(99999)
				_phase = 3
		3:
			if _frame > 118:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/enemy_death2.png")
				print("CHAR SHOTS DONE")
				quit(0)
