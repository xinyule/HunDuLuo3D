extends SceneTree

## bomber 专用补拍：同 tank 方案（priority=999 钉位+钉朝向，相机相对实际落点）
var _main: Node
var _rig: Node
var _pinner: Node
var _frame := 0
var _enemy = null
var _phase := 0

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

class Pinner:
	extends Node
	var target: Node3D
	var pin := Vector3.ZERO
	func _ready() -> void:
		process_priority = 999
	func _process(_dt: float) -> void:
		if target != null and is_instance_valid(target):
			target.global_position = pin
			target.rotation.y = 0.0 # 正面朝 +z（对相机）

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	_rig = (load("res://test/cam_rig.gd") as GDScript).new()
	root.add_child(_rig)
	_pinner = Pinner.new()
	root.add_child(_pinner)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	if _frame == 5:
		_main.start_game(0)
		_main._advance_dialog()
		_main.player.invuln = 99999.0
		_main.ui.visible = false
		_rig.cam = _main.camera
		_rig.main_ref = _main
		var lvl = _main.current_level
		_enemy = lvl._spawn_enemy("bomber", -6.0, 18.0)
		_pinner.target = _enemy
		_pinner.pin = _enemy.global_position
		var ep: Vector3 = _enemy.global_position
		_main.player.global_position = Vector3(ep.x, lvl.get_support_y(ep.x, ep.z + 6.0, 999.0), ep.z + 6.0)
		_rig.pos = Vector3(ep.x + 0.8, ep.y + 1.35, ep.z + 3.0)
		_rig.look = Vector3(ep.x, ep.y + 1.05, ep.z)
		_phase = 1
	elif _phase == 1 and _frame >= 65:
		var img := root.get_texture().get_image()
		img.save_png(OUT + "final_char_bomber.png")
		print("SNAP final_char_bomber.png enemy=", _enemy.global_position)
		quit(0)
