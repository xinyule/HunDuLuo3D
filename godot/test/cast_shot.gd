extends SceneTree

## 全员验收图：比尔/兰斯全身+脸部特写（新 GLB 直拍）、七人形兵种列队（走 Enemy.setup 真实路径）
## 运行：xvfb-run godot --path . --script res://test/cast_shot.gd --rendering-driver opengl3 --resolution 1280x720
var _frame := 0
var _phase := 0
var _cam: Camera3D
var _holder: Node3D

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"
const TYPES := ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar"]

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
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.3)
	ground.material_override = gm
	root.add_child(ground)
	_holder = Node3D.new()
	root.add_child(_holder)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true
	_spawn_hero("res://assets/char/bill.glb")
	process_frame.connect(_on_frame)

func _spawn_hero(path: String) -> void:
	for c in _holder.get_children():
		c.queue_free()
	var ps: PackedScene = load(path)
	var m := ps.instantiate()
	_holder.add_child(m)
	var ap := _find_ap(m)
	if ap:
		ap.play("Idle")

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
		0: # 比尔全身
			_cam.position = Vector3(0.7, 1.15, 2.9)
			_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
			if _frame > 22:
				_snap("cast_bill.png")
				_phase = 1
		1: # 比尔脸部
			_cam.position = Vector3(0.35, 1.62, 0.85)
			_cam.look_at(Vector3(0, 1.52, 0), Vector3.UP)
			if _frame > 30:
				_snap("cast_bill_face.png")
				_spawn_hero("res://assets/char/lance.glb")
				_phase = 2
		2: # 兰斯全身
			_cam.position = Vector3(0.7, 1.15, 2.9)
			_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
			if _frame > 52:
				_snap("cast_lance.png")
				_phase = 3
		3: # 兰斯脸部
			_cam.position = Vector3(0.35, 1.62, 0.85)
			_cam.look_at(Vector3(0, 1.52, 0), Vector3.UP)
			if _frame > 60:
				_snap("cast_lance_face.png")
				_phase = 4
				# 列队：真实 Enemy.setup
				for c in _holder.get_children():
					c.queue_free()
				var ss: Dictionary = {}
				for tt in TYPES:
					ss[tt] = load("res://assets/char/enemy_%s.glb" % tt)
				var i := 0
				for t in TYPES:
					var e := Enemy.new()
					_holder.add_child(e)
					e.setup(t, Vector3(-4.5 + i * 1.5, 0.0, 0.0), {}, ss)
					if t == "akbar":
						e.position.y += 1.05 # 列队展示抵消水中下潜偏移
					i += 1
		4: # 列队正面 + 侧面
			_cam.position = Vector3(0, 1.35, 8.2)
			_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
			if _frame > 85:
				_snap("cast_lineup.png")
				_phase = 5
		5:
			_cam.position = Vector3(5.2, 1.7, 5.6)
			_cam.look_at(Vector3(-0.5, 0.9, 0), Vector3.UP)
			if _frame > 93:
				_snap("cast_lineup_side.png")
				print("CAST SHOTS DONE")
				quit(0)
