extends SceneTree

## 骨骼对位探针（渲染版）：与特写完全相同的冻结条件，在截图同帧打印小腿挂件全局位置
## 运行：xvfb-run godot --path . --script res://test/bone_probe2.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0

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
		_main.player.invuln = 99999.0
		_main.set_process(false)
	if _frame == 48:
		var p = _main.player
		var pp: Vector3 = p.global_position
		var stack: Array = [p]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is BoneAttachment3D:
				var ba := n as BoneAttachment3D
				if ba.bone_name.begins_with("DEF-shin") or ba.bone_name.begins_with("DEF-thigh"):
					var rel: Vector3 = ba.global_position - pp
					print("ATTACH %s rel=(%.2f, %.2f, %.2f)" % [ba.bone_name, rel.x, rel.y, rel.z])
					for c in ba.get_children():
						if c is Node3D:
							var cr: Vector3 = (c as Node3D).global_position - pp
							print("  child %s rel=(%.2f, %.2f, %.2f)" % [c.get_class(), cr.x, cr.y, cr.z])
			for c in n.get_children():
				stack.append(c)
		print("BONE PROBE2 DONE")
		quit(0)
