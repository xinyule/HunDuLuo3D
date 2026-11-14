extends SceneTree

## 1.2.1 地形 shader 降本改前/改后同机位对比截图（L1：一张平地+缓坡、一张山脊陡坡）。
## 等 dialog 落地后才动 player（long_perf 同口径；抢跑会 Nil 报错）。
## 运行：xvfb-run godot --path . --script res://test/terrain_shot.gd --rendering-driver opengl3 --resolution 1280x720 -- before|after

var _main: Node
var _frame := 0
var _phase := "boot"
var _tag := "after"
var _snap_at := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_tag = String(args[0])
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("SNAP ", path, " ", img.get_size())

func _on_frame() -> void:
	_frame += 1
	var lv = _main.current_level
	match _phase:
		"boot":
			if _frame == 3:
				_main.start_game()
				_phase = "wait"
		"wait":
			if _main.state == "dialog" and lv != null and _main.player != null:
				_main._advance_dialog()
				_main.player.barrier = 999999.0
				# 机位一：平地缓坡——站在河谷北侧看向北（丛林平地+起伏）
				var y1: float = lv.get_support_y(6.0, -120.0, 999.0)
				_main.player.global_position = Vector3(6.0, y1, -120.0)
				_main._yaw = PI
				_main._pitch = 0.12
				_snap_at = _frame + 40
				_phase = "shot1"
		"shot1":
			if _frame >= _snap_at:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/terrain_flat_%s.png" % _tag)
				# 机位二：山脊陡坡——站到西侧山脊脚下向西看坡面（陡坡岩石混合域）
				var hw: float = lv.playable_half_width()
				var y2: float = lv.get_support_y(-hw + 6.0, -160.0, 999.0)
				_main.player.global_position = Vector3(-hw + 6.0, y2, -160.0)
				_main._yaw = -PI / 2.0 # 朝 -x 看山脊
				_main._pitch = 0.05
				_snap_at = _frame + 40
				_phase = "shot2"
		"shot2":
			if _frame >= _snap_at:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/terrain_slope_%s.png" % _tag)
				print("TERRAIN SHOTS DONE tag=", _tag)
				quit(0)
