extends SceneTree

## 骨骼对位探针：等动画姿态稳定后，对比每块骨头的全局姿态位置 vs 对应 BoneAttachment 的全局位置
## 运行：godot --headless --path . --script res://test/bone_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _on() -> void:
	_frame += 1
	if _frame == 30:
		_main._set_char("bill")
		_main.start_game()
		_main._advance_dialog()
	if _frame == 90:
		var p = _main.player
		var skel := _find_skel(p)
		var pp: Vector3 = p.global_position
		for bname in ["DEF-head", "DEF-hips", "DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-spine.002"]:
			var idx := skel.find_bone(bname)
			if idx < 0:
				print("BONE %s NOT FOUND" % bname)
				continue
			var gp: Vector3 = skel.get_bone_global_pose(idx).origin
			# 骨骼全局姿态是模型空间——换算到世界：用骨骼节点的全局变换
			var world: Vector3 = skel.global_transform * gp
			print("BONE %s world_rel=(%.2f, %.2f, %.2f)" % [bname, world.x - pp.x, world.y - pp.y, world.z - pp.z])
		var stack: Array = [p]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is BoneAttachment3D:
				var ba := n as BoneAttachment3D
				var rel: Vector3 = ba.global_position - pp
				print("ATTACH %s rel=(%.2f, %.2f, %.2f) bone_idx=%d" % [ba.bone_name, rel.x, rel.y, rel.z, ba.get_bone_idx()])
			for c in n.get_children():
				stack.append(c)
		print("BONE PROBE DONE")
		quit(0)
