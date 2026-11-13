extends SceneTree

## 暂存验收截图：bill 正面 Jog_Fwd 两帧（验朝向/原地跑）+ Aim_Up/Down 姿势 + lance/garth 正面
## 运行：xvfb-run godot --path . --script res://test/staging_shot.gd --rendering-driver opengl3 --resolution 1280x720

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"
var _frame := 0
var _phase := 0
var _cam: Camera3D
var _cur: Node3D
var _anim: AnimationPlayer

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _load_char(nm: String) -> void:
	if _cur:
		_cur.queue_free()
	var ps: PackedScene = load("res://assets/char_staging/%s.glb" % nm)
	_cur = ps.instantiate()
	root.add_child(_cur)
	_anim = _find_anim(_cur)

func _initialize() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.42, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.8
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.4, 0.38, 0.34)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.45, 3.4) # 角色朝 +Z 时应正对镜头
	_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	root.add_child(_cam)
	_cam.current = true
	_load_char("bill")
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _seek_play(clip: String, t: float) -> void:
	if _anim:
		_anim.play(clip)
		_anim.seek(t, true)

func _side_cam() -> void:
	_cam.position = Vector3(3.4, 1.3, 0)
	_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)

func _front_cam() -> void:
	_cam.position = Vector3(0, 1.45, 3.4)
	_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame == 5:
				_seek_play("Jog_Fwd", 0.3)
			if _frame == 20:
				_snap("staging_bill_jog_a.png")
				_seek_play("Jog_Fwd", 0.62)
				_phase = 1
		1:
			if _frame == 35: # 与 A 不同时刻：腿姿应不同、人不位移
				_snap("staging_bill_jog_b.png")
				_side_cam()
				_seek_play("Pistol_Aim_Up", 0.1)
				_phase = 2
		2:
			if _frame == 50:
				_snap("staging_bill_aimup.png")
				_seek_play("Pistol_Aim_Down", 0.1)
				_phase = 3
		3:
			if _frame == 65:
				_snap("staging_bill_aimdown.png")
				_front_cam()
				_load_char("lance")
				_phase = 4
		4:
			if _frame == 73:
				_seek_play("Pistol_Aim_Neutral", 0.1)
				_phase = 5
		5:
			if _frame == 85:
				_snap("staging_lance_aim.png")
				_load_char("enemy_garth")
				_phase = 6
		6:
			if _frame == 93:
				_seek_play("Pistol_Idle", 0.4)
				_phase = 7
		7:
			if _frame == 105:
				_snap("staging_garth_idle.png")
				print("STAGING SHOTS DONE")
				quit(0)
