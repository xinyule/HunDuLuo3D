extends SceneTree

## 诊断：akbar 摆拍为何跑偏——打印生成后每 15 帧的敌人/玩家/相机位
var _main: Node
var _rig: Node
var _frame := 0
var _enemy = null

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	_rig = (load("res://test/cam_rig.gd") as GDScript).new()
	root.add_child(_rig)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	if _frame == 5:
		_main.start_game(0)
		_main._advance_dialog()
		_main.player.invuln = 99999.0
		_main.ui.visible = false
		var lvl = _main.current_level
		_enemy = lvl._spawn_enemy("akbar", 0.0, 16.0)
		_main.player.global_position = Vector3(0, lvl.get_support_y(0, 22, 999.0), 22.0)
		print("DIAG spawn enemy pos=", _enemy.global_position)
	if _frame > 5 and _enemy != null and is_instance_valid(_enemy):
		_enemy.global_position = Vector3(0, _enemy.global_position.y, 16.0) # 只钉 x/z，放任 y
		if _frame % 15 == 0:
			print("DIAG f=", _frame, " enemy=", _enemy.global_position, " player=", _main.player.global_position, " cam=", _main.camera.global_position)
	if _frame >= 95:
		print("DIAG DONE")
		quit(0)
