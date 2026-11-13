extends SceneTree

## POC: red sphere marker at CPU-skinned kneepad center vs GPU-rendered pad
var _frame := 0
var _model: Node3D
var _skel: Skeleton3D
var _marker: MeshInstance3D

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

func _initialize() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.85
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.3)
	ground.material_override = gm
	root.add_child(ground)
	var ps: PackedScene = load("res://assets/char/bill.glb")
	_model = ps.instantiate()
	root.add_child(_model)
	_skel = _find_sk(_model)
	var ap := _find_ap(_model)
	if ap:
		ap.play("Walk")
		ap.seek(0.45, true)
		ap.pause()
	_marker = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	_marker.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.05, 0.05)
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mm
	root.add_child(_marker)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.position = Vector3(0.55, 0.62, 0.95)
	cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
	cam.current = true
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
	if _frame == 10:
		var ci := _skel.find_bone("calf_l")
		var gp: Transform3D = _skel.get_bone_global_pose(ci)
		var rest_g: Transform3D = _skel.get_bone_global_rest(ci)
		var mi := _find_mesh(_model, "KneePad_l")
		var arrs := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var skin_m: Transform3D = gp * rest_g.affine_inverse()
		var c := Vector3.ZERO
		for v in verts:
			c += skin_m * v
		c /= verts.size()
		_marker.global_position = c
		print("MARKER at ", c)
	if _frame == 14:
		var img := root.get_texture().get_image()
		img.save_png(OUT + "poc_knee3_marker.png")
		print("SNAP done")
		quit(0)
