extends SceneTree
func _initialize() -> void:
	var ps: PackedScene = load("res://assets/char/ual.glb")
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	var ap: AnimationPlayer = _find_ap(inst)
	if ap:
		var names := ap.get_animation_list()
		names.sort()
		print("ANIMS(", names.size(), "): ", names)
	var sk: Skeleton3D = _find_sk(inst)
	if sk:
		var bones: Array = []
		for i in sk.get_bone_count():
			bones.append(sk.get_bone_name(i))
		print("BONES(", bones.size(), "): ", bones)
	var meshes := 0
	var mats: Array = []
	_count(inst, meshes, mats)
	print("meshes: ", meshes, " materials: ", mats)
	var aabb := AABB()
	var first := true
	_aabb(inst, aabb, first)
	print("AABB: ", aabb)
	quit()
func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r = _find_ap(c)
		if r: return r
	return null
func _find_sk(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r = _find_sk(c)
		if r: return r
	return null
func _count(n: Node, meshes: int, mats: Array) -> void:
	if n is MeshInstance3D and n.mesh:
		meshes += 1
		for s in n.mesh.get_surface_count():
			var m = n.mesh.surface_get_material(s)
			mats.append(m.resource_name if m else "none")
	for c in n.get_children():
		_count(c, meshes, mats)
func _aabb(n: Node, box: AABB, first: bool) -> void:
	if n is MeshInstance3D and n.mesh:
		var b: AABB = n.global_transform * n.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	for c in n.get_children():
		_aabb(c, box, first)
