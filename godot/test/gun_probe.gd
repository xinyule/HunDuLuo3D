extends SceneTree

## 枪械/载具 GLB 结构探针：节点树 + 合并 AABB（headless，非蒙皮模型 AABB 可信）
const FILES := ["weapons/ak", "weapons/m4_low", "weapons/m24", "weapons/m4a1", "weapons/bipod", "weapons/tripod", "vehicles/tank", "vehicles/turret_cannon"]

func _initialize() -> void:
	for f in FILES:
		var ps: PackedScene = load("res://assets/%s.glb" % f)
		if ps == null:
			print("GUNPROBE ", f, " LOAD FAIL")
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		await process_frame
		await process_frame
		var aabb := AABB()
		var first := true
		var names: Array = []
		var stack: Array = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			names.append(n.name + "(" + n.get_class() + ")")
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var ab := mi.global_transform * mi.get_aabb()
				if first:
					aabb = ab
					first = false
				else:
					aabb = aabb.merge(ab)
		print("GUNPROBE ", f, " size=", aabb.size, " pos=", aabb.position)
		print("   nodes: ", ", ".join(names.slice(0, 14)))
		inst.queue_free()
	print("GUNPROBE DONE")
	quit(0)
