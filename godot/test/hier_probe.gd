extends SceneTree

func _dump(n: Node, depth: int) -> void:
	var s := ""
	if n is Node3D:
		var t := (n as Node3D).transform
		s = " scale=" + str(t.basis.get_scale()) + " pos=" + str(t.origin)
	if n is Skeleton3D:
		s += " bones=" + str((n as Skeleton3D).get_bone_count())
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", s)
	for c in n.get_children():
		_dump(c, depth + 1)

func _initialize() -> void:
	var ps: PackedScene = load("res://assets/char/bill.glb")
	var inst := ps.instantiate()
	_dump(inst, 0)
	quit(0)
