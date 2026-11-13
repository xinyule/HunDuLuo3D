extends SceneTree

## POC: same Walk pose, kneepads hidden — does the big gray box persist?
var _frame := 0
var _phase := 0
var _cam: Camera3D
var _model: Node3D

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
	var ap := _find_ap(_model)
	if ap:
		ap.play("Walk")
		ap.seek(0.45, true)
		ap.pause()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	process_frame.connect(_on_frame)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null

func _hide_pads(n: Node) -> void:
	if n is MeshInstance3D and n.name.contains("KneePad"):
		n.visible = false
		print("HID ", n.name)
	for c in n.get_children():
		_hide_pads(c)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	_cam.position = Vector3(0.55, 0.62, 0.95)
	_cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
	match _phase:
		0:
			if _frame > 18:
				_snap("poc_knee2_with.png")
				_hide_pads(_model)
				_phase = 1
		1:
			if _frame > 24:
				_snap("poc_knee2_without.png")
				print("DONE")
				quit(0)
