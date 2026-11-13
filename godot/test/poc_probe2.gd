extends SceneTree

## POC probe: in-engine positions of calf bone vs kneepad AABB at Walk seek
var _frame := 0
var _model: Node3D
var _skel: Skeleton3D

func _initialize() -> void:
	var ps: PackedScene = load("res://assets/char/bill.glb")
	_model = ps.instantiate()
	root.add_child(_model)
	_skel = _find_sk(_model)
	var ap := _find_ap(_model)
	if ap:
		ap.play("Walk")
		ap.seek(13.0/30.0, true)
		ap.pause()
	process_frame.connect(_on_frame)

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

func _find_mesh(n: Node, nm: String) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == nm:
		return n
	for c in n.get_children():
		var r := _find_mesh(c, nm)
		if r:
			return r
	return null

func _on_frame() -> void:
	_frame += 1
	if _frame == 6:
		var ci := _skel.find_bone("calf_l")
		var gp: Transform3D = _skel.get_bone_global_pose(ci)
		print("CALF_L global origin ", gp.origin, " basisX ", gp.basis.x, " basisY ", gp.basis.y, " basisZ ", gp.basis.z)
		var rest_g: Transform3D = _skel.get_bone_global_rest(ci)
		print("CALF_L rest origin ", rest_g.origin)
		for side in ["l", "r"]:
			var ci2 := _skel.find_bone("calf_" + side)
			var gp2: Transform3D = _skel.get_bone_global_pose(ci2)
			var rest2: Transform3D = _skel.get_bone_global_rest(ci2)
			var mi2 := _find_mesh(_model, "KneePad_" + side)
			if mi2:
				var arrs := mi2.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
				var skin_m: Transform3D = gp2 * rest2.affine_inverse()
				var c := Vector3.ZERO
				for v in verts:
					c += skin_m * v
				c /= verts.size()
				print("PAD_", side, " center ", c, " joint ", gp2.origin, " offset ", c - gp2.origin)
				print("PAD_", side, " skin basisY ", skin_m.basis.y, " bone basisY ", gp2.basis.y)
		quit(0)
