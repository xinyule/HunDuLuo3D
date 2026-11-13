extends SceneTree

## 内容B线专用截图：自由机位（给定相机位置+注视点）
## 运行：xvfb-run godot --path . --script res://test/contentb_shot.gd --rendering-driver opengl3 --resolution 800x450 -- <关号> <out名> <cx,cy,cz> <lx,ly,lz> [falcon]
## 第 8 参传 falcon 时：相机自动对准本关第一只飞鹰巡逻位（近距离侧拍）
## 机位经 cam_rig（高 process_priority 节点）在游戏相机逻辑之后写入，直接 set 会被覆盖。

var _main: Node
var _rig: Node
var _frame := 0
var _phase := 0
var _lv := 1
var _out := "contentb"
var _cam := Vector3(7.5, 3.6, 16.0)
var _look := Vector3(0, 0.8, -30.0)
var _falcon := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_lv = int(args[0])
	if args.size() > 1:
		_out = String(args[1])
	if args.size() > 2:
		var p := String(args[2]).split(",")
		_cam = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if args.size() > 3:
		var p := String(args[3]).split(",")
		_look = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if args.size() > 4:
		_falcon = String(args[4]) == "falcon"
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	_rig = (load("res://test/cam_rig.gd") as GDScript).new()
	root.add_child(_rig)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 6:
				_main.ui.visible = false
				_main.start_game(_lv - 1)
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				_rig.cam = _main.camera
				_rig.pos = _cam
				_rig.look = _look
				_rig.main_ref = _main
				_rig.follow_falcon = _falcon
				_phase = 1
		1:
			if _frame > 34:
				_phase = 2
		2:
			if _frame > 40:
				var img := root.get_texture().get_image()
				img.save_png("/home/hatch/workspace/HunDuLuo3D_work/shots/%s.png" % _out)
				print("CONTENTB SNAP ", _out, " lv", _lv)
				quit(0)
