extends SceneTree

## 挂枪近景（游戏内）：主角持 M4A1 近景 + 敌兵列队近景（复用 cast_lineup 摆位）
## 运行：xvfb-run godot --path . --script res://test/gun_shot.gd --rendering-driver opengl3 --resolution 1280x720

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"
var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 40:
				_main.ui.visible = false
				_main.start_game()
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				_main.set_process(false)
				_main.set_physics_process(false)
				var lv = _main.current_level
				lv.set_process(false)
				lv.set_physics_process(false)
				# 主角近景：相机贴到主角右前方，看清手里的枪
				var pp: Vector3 = _main.player.global_position
				_main.camera.position = pp + Vector3(1.5, 1.35, 2.0)
				_main.camera.look_at(pp + Vector3(0, 1.05, 0), Vector3.UP)
				_phase = 1
		1:
			if _frame > 55:
				_snap("gun_player_close.png")
				# 敌兵列队近景
				var lv = _main.current_level
				var i := 0
				for t in ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar"]:
					var x: float = -4.5 + i * 1.5
					var z: float = _main.player.global_position.z - 9.0
					var e = lv._spawn_enemy(t, x, z)
					if t == "akbar" and e:
						e._model.position.y = 0.0
					i += 1
				_main.camera.position = Vector3(0, 1.5, _main.player.global_position.z - 3.4)
				_main.camera.look_at(Vector3(0, 0.95, _main.player.global_position.z - 9.0), Vector3.UP)
				_phase = 2
		2:
			if _frame > 75:
				_snap("gun_enemy_lineup.png")
				print("GUN SHOTS DONE")
				quit(0)
