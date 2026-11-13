extends SceneTree

## akbar 专用补拍：他是水兵，_spawn_enemy 恒把他放到河里——先生成、等他站定，再按他实际位置取景
var _main: Node
var _rig: Node
var _frame := 0
var _enemy = null
var _phase := 0

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

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
		_rig.cam = _main.camera
		_rig.main_ref = _main
		var lvl = _main.current_level
		_enemy = lvl._spawn_enemy("akbar", 14.0, 16.0) # x=14：水域落点避开 x≈0 的桥面（否则会从桥板里冒出来）
		_phase = 1
	elif _phase == 1 and _frame >= 45:
		# 站定后按实际位置取景：玩家放他 +z 侧 7m（引他面朝 +z），相机 +z 侧 3m 低机位
		var ep: Vector3 = _enemy.global_position
		var lvl2 = _main.current_level
		_main.player.global_position = Vector3(ep.x, lvl2.get_support_y(ep.x, ep.z + 7.0, 999.0), ep.z + 7.0)
		_rig.pos = Vector3(ep.x + 0.8, ep.y + 1.3, ep.z + 3.0)
		_rig.look = Vector3(ep.x, ep.y + 0.9, ep.z)
		_phase = 2
	elif _phase == 2 and _frame >= 75:
		var img := root.get_texture().get_image()
		img.save_png(OUT + "final_char_akbar.png")
		print("SNAP final_char_akbar.png enemy=", _enemy.global_position)
		quit(0)
