extends SceneTree

## Boss 造型自检：独立小舞台逐只拍正面/侧面（不进游戏流程）
## 运行：xvfb-run -a godot --path . --script res://test/boss_portrait.gd --rendering-driver opengl3 --resolution 1280x720
## 可选：-- 后跟 boss id 只拍指定几只，如 -- gordea gromaides

const ALL := ["defenseWall", "finalGate", "baseCore", "gromaides", "godomuga", "guldaf", "gordea", "alienHeart"]
# 取景表：[相机距离, 相机高, 注视高]
const FRAME := {
	"defenseWall": [27.0, 5.0, 3.8],
	"finalGate": [31.0, 5.5, 4.2],
	"baseCore": [13.5, 3.8, 3.3],
	"gromaides": [14.5, 4.4, 4.1],
	"godomuga": [13.5, 3.6, 3.2],
	"guldaf": [15.0, 5.6, 5.0],
	"gordea": [13.5, 4.0, 3.7],
	"alienHeart": [23.0, 4.8, 4.2],
}

var _ids: Array = []
var _idx := 0
var _frame := 0
var _stage := 0
var _cam: Camera3D
var _boss = null # 不静态引用 Boss 类：入口脚本编译早于 autoload 注册，boss.gd 需运行时动态加载
var _prefix := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--base":
			_prefix = "base_"
		elif ALL.has(a):
			_ids.append(a)
	if _ids.is_empty():
		_ids = ALL.duplicate()
	# 灯光与天空
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.42, 0.65)
	sm.sky_horizon_color = Color(0.65, 0.72, 0.8)
	sm.ground_bottom_color = Color(0.12, 0.11, 0.1)
	sm.ground_horizon_color = Color(0.55, 0.55, 0.55)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.15
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.3
	root.add_child(fill)
	Util.box(root, Vector3(90, 0.1, 90), Util.pbr(Color(0.32, 0.32, 0.3), "concrete", 0.95, 0.0), Vector3(0, -0.05, 0))
	_cam = Camera3D.new()
	_cam.fov = 55.0
	root.add_child(_cam)
	process_frame.connect(_on_frame)

func _place_cam(side: bool) -> void:
	var f: Array = FRAME[_ids[_idx]]
	var d: float = f[0]
	if side:
		_cam.position = Vector3(d, f[1], 0)
	else:
		_cam.position = Vector3(0, f[1], d)
	_cam.look_at(Vector3(0, f[2], 0), Vector3.UP)

func _pose_for_shot() -> void:
	# 只为拍照摆姿势（不影响玩法）：幻影散开+核心显形、魔神像张口
	match _ids[_idx]:
		"godomuga":
			var phs: Array = _boss._anim_nodes["phantoms"]
			for i in phs.size():
				var a := 0.8 + float(i) * TAU / 4.0
				phs[i].position = Vector3(cos(a) * 2.6, 3.4 + sin(i * 1.7) * 0.5, 0.6 + sin(a) * 0.5)
			_boss._anim_nodes["core"].visible = true
		"gromaides":
			_boss._anim_nodes["jaw"].position.y = -1.7

func _spawn() -> void:
	_boss = load("res://scripts/boss.gd").new()
	root.add_child(_boss)
	_boss.setup(_ids[_idx], Vector3.ZERO, {})
	_pose_for_shot()
	_place_cam(false)

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("SNAP ", path)

func _on_frame() -> void:
	_frame += 1
	match _stage:
		0:
			if _frame >= 6:
				_spawn()
				_stage = 1
				_frame = 0
		1:
			if _frame >= 10:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/boss_%s%s.png" % [_prefix, _ids[_idx]])
				_place_cam(true)
				_stage = 2
				_frame = 0
		2:
			if _frame >= 6:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/boss_%s%s_side.png" % [_prefix, _ids[_idx]])
				_boss.queue_free()
				_boss = null
				_idx += 1
				_frame = 0
				if _idx >= _ids.size():
					print("BOSS PORTRAITS DONE")
					quit(0)
				else:
					_stage = 0
