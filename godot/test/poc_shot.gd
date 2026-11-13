extends SceneTree

## POC: new high-detail Bill (MPFB) in-engine stills — front/back/face/walk
## Run: xvfb-run -a godot --path . --script res://test/poc_shot.gd --rendering-driver opengl3 --resolution 1280x720

var _frame := 0
var _phase := 0
var _cam: Camera3D
var _anim: AnimationPlayer
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
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	var ps: PackedScene = load("res://assets/char/bill.glb")
	_model = ps.instantiate()
	root.add_child(_model)
	_anim = _find_ap(_model)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	root.add_child(_cam)
	_cam.current = true
	if _anim:
		_anim.play("Idle")
	process_frame.connect(_on_frame)

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null

func _aim(pos: Vector3, tgt: Vector3) -> void:
	_cam.position = pos
	_cam.look_at(tgt, Vector3.UP)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			_aim(Vector3(0, 1.2, 3.4), Vector3(0, 0.95, 0))
			if _frame > 25:
				_snap("poc_bill_front.png")
				_phase = 1
		1:
			_aim(Vector3(0, 1.2, -3.4), Vector3(0, 0.95, 0))
			if _frame > 32:
				_snap("poc_bill_back.png")
				_phase = 2
		2:
			_aim(Vector3(0.22, 1.68, 0.66), Vector3(0, 1.6, 0))
			if _frame > 39:
				_snap("poc_bill_face.png")
				_phase = 3
		3:
			if _anim:
				_anim.play("Walk")
				_anim.seek(0.45, true)
				_anim.pause()
			_aim(Vector3(1.9, 1.25, 2.6), Vector3(0, 0.9, 0))
			if _frame > 48:
				_snap("poc_bill_walk.png")
				print("POC SHOTS DONE")
				quit(0)
