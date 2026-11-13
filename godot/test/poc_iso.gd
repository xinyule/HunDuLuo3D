extends SceneTree

## POC isolation: identify stray pale chunks — hide node groups per phase at Walk pose
## Run: xvfb-run -a godot --path . --script res://test/poc_iso.gd --rendering-driver opengl3 --resolution 1280x720

var _frame := 0
var _phase := 0
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
	var cam := Camera3D.new()
	cam.fov = 42.0
	root.add_child(cam)
	cam.position = Vector3(1.9, 1.25, 2.6)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
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

func _set_vis(substr_a: String, substr_b: String, vis: bool) -> void:
	_walk(_model, substr_a, substr_b, vis)

func _hit(nm: String, pat: String) -> bool:
	if pat == "":
		return false
	if pat.begins_with("="):
		return nm == pat.substr(1)
	return nm.contains(pat)

func _walk(n: Node, a: String, b: String, vis: bool) -> void:
	if n is MeshInstance3D:
		if _hit(n.name, a) or _hit(n.name, b):
			n.visible = vis
			print(("HIDE " if not vis else "SHOW ") + n.name)
	for c in n.get_children():
		_walk(c, a, b, vis)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 20:
				_snap("poc_iso_all.png")
				_set_vis("KneePad", "", false)
				_phase = 1
		1:
			if _frame > 26:
				_snap("poc_iso_nopads.png")
				_set_vis("=Human", "", false)
				_phase = 2
		2:
			if _frame > 32:
				_snap("poc_iso_nobody.png")
				print("ISO DONE")
				quit(0)
