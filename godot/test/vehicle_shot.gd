extends SceneTree

## 载具近景：第 1 关空地上摆坦克 + 炮台正对镜头
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
				var pz: float = _main.player.global_position.z
				lv._spawn_enemy("tank", -2.2, pz - 8.0)
				lv._spawn_enemy("turret", 2.6, pz - 8.0)
				_main.camera.position = Vector3(0, 1.7, pz - 2.6)
				_main.camera.look_at(Vector3(0, 1.0, pz - 8.0), Vector3.UP)
				_phase = 1
		1:
			if _frame > 60:
				var img := root.get_texture().get_image()
				img.save_png("/home/hatch/workspace/HunDuLuo3D_work/shots/integ_vehicles.png")
				print("VEHICLE SNAP")
				quit(0)
