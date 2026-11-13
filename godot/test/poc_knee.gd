extends SceneTree

## POC knee close-up: are the kneepads on the knees? (Idle + Walk, front close)
var _frame := 0
var _phase := 0
var _cam: Camera3D
var _anim: AnimationPlayer

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
	var model := ps.instantiate()
	root.add_child(model)
	_anim = _find_ap(model)
	if _anim:
		_anim.play("Idle")
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

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			_cam.position = Vector3(0.1, 0.62, 1.05)
			_cam.look_at(Vector3(0, 0.48, 0), Vector3.UP)
			if _frame > 20:
				_snap("poc_knee_idle.png")
				if _anim:
					_anim.play("Walk")
					_anim.seek(0.45, true)
					_anim.pause()
				_phase = 1
		1:
			_cam.position = Vector3(0.55, 0.62, 0.95)
			_cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
			if _frame > 28:
				_snap("poc_knee_walk.png")
				print("KNEE DONE")
				quit(0)
