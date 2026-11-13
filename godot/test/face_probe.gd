extends SceneTree

## 人物特写验收：正面脸部特写（五官/头巾）+ 低机位腿脚特写（裤腿/护膝/军靴）
## 运行：xvfb-run godot --path . --script res://test/face_probe.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _cam: Camera3D
var _p

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on)

func _on() -> void:
	_frame += 1
	if _frame == 30:
		_main._set_char("bill")
		_main.start_game()
		_main._advance_dialog()
		_main.ui.visible = false
		_p = _main.player
		_p.invuln = 99999.0
		_cam = _main.rig.camera
		var fwd := Vector3(sin(_p.facing), 0, cos(_p.facing))
		var head: Vector3 = _p.global_position + Vector3(0, 1.52, 0)
		_cam.global_position = head + fwd * 1.15 + Vector3(0.12, 0.02, 0)
		_cam.look_at(head + Vector3(0, -0.05, 0), Vector3.UP)
		_main.set_process(false) # 冻结主循环，镜头不被越肩机位覆盖
	if _frame == 42:
		var img := root.get_texture().get_image()
		img.save_png("/home/hatch/workspace/HunDuLuo3D_work/shots/face_close.png")
		var fwd2 := Vector3(sin(_p.facing), 0, cos(_p.facing))
		var feet: Vector3 = _p.global_position + Vector3(0, 0.35, 0)
		_cam.global_position = feet + fwd2 * 1.5 + Vector3(0.25, 0.1, 0)
		_cam.look_at(feet, Vector3.UP)
	if _frame == 54:
		var img2 := root.get_texture().get_image()
		img2.save_png("/home/hatch/workspace/HunDuLuo3D_work/shots/feet_close.png")
		print("FACE PROBE DONE")
		quit(0)
