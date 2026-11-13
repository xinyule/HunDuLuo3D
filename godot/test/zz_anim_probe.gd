extends SceneTree

func _initialize() -> void:
	var ps: PackedScene = load("res://assets/char/ual.glb")
	var inst := ps.instantiate()
	root.add_child(inst)
	var ap := _find_ap(inst)
	if ap:
		var names := ap.get_animation_list()
		print("ANIM_COUNT ", names.size())
		for n in names:
			print("ANIM ", n)
	var sk := _find_sk(inst)
	if sk:
		print("BONE_COUNT ", sk.get_bone_count())
	quit(0)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null

func _find_sk(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_sk(c)
		if r:
			return r
	return null
