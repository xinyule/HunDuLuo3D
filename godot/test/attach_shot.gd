extends SceneTree

## 挂件单独成像：隐藏 UAL 模型本体网格，只拍骨骼挂件（背心/裤/靴/枪/头巾），一帧看清谁串位
## 运行：xvfb-run godot --path . --script res://test/attach_shot.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on)

func _hide_model(n: Node) -> void:
	# 隐藏模型自带的网格（骨骼网格是 Skeleton3D 的直接 MeshInstance 子级或挂 skin 的节点）：
	# 挂件都在 BoneAttachment3D 下面——凡不在 BoneAttachment 下的 MeshInstance3D 全部隐藏
	if n is MeshInstance3D:
		(n as MeshInstance3D).visible = false
		return
	for c in n.get_children():
		if c is BoneAttachment3D:
			continue
		_hide_model(c)

func _on() -> void:
	_frame += 1
	if _frame == 30:
		_main._set_char("bill")
		_main.start_game()
		_main._advance_dialog()
		_main.ui.visible = false
		var p = _main.player
		p.invuln = 99999.0
		_hide_model(p)
		var cam: Camera3D = _main.rig.camera
		var fwd := Vector3(sin(p.facing), 0, cos(p.facing))
		var mid: Vector3 = p.global_position + Vector3(0, 0.95, 0)
		cam.global_position = mid + fwd * 3.0 + Vector3(0.2, 0.15, 0)
		cam.look_at(mid, Vector3.UP)
		_main.set_process(false)
	if _frame == 48:
		var img := root.get_texture().get_image()
		img.save_png("/home/hatch/workspace/HunDuLuo3D_work/shots/attach_only.png")
		print("ATTACH SHOT DONE")
		quit(0)
