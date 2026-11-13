extends SceneTree

## 挂件清单探针：打印主角所有 BoneAttachment 及其子节点的全局坐标，定位串位挂件
## 运行：godot --headless --path . --script res://test/attach_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on)

func _dump(n: Node, player_pos: Vector3) -> void:
	if n is BoneAttachment3D:
		var ba := n as BoneAttachment3D
		for c in ba.get_children():
			if c is Node3D:
				var rel: Vector3 = (c as Node3D).global_position - player_pos
				print("ATTACH bone=%s child=%s rel=(%.2f, %.2f, %.2f)" % [ba.bone_name, c.get_class(), rel.x, rel.y, rel.z])
	for c in n.get_children():
		_dump(c, player_pos)

func _on() -> void:
	_frame += 1
	if _frame == 30:
		_main._set_char("bill")
		_main.start_game()
		_main._advance_dialog()
		var p = _main.player
		_dump(p, p.global_position)
		print("ATTACH PROBE DONE")
		quit(0)
