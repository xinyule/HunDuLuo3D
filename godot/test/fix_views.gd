extends SceneTree

## 1.1.0 第一线截图：room = L2 房间改后图（出生点游戏镜头，与改前同机位）；
## sky = 逐关远景（cam_rig 制高点望向关卡纵深，验天空/雾/色调区分）。
## 用法：xvfb-run -a godot --path . --script res://test/fix_views.gd --rendering-driver opengl3 --resolution 1280x720 -- room|sky

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _rig: Node
var _frame := 0
var _mode := "room"
var _phase := 0
var _mark := 0
var _lv := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = String(args[0])
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	_rig = (load("res://test/cam_rig.gd") as GDScript).new()
	root.add_child(_rig)
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	if _frame < _mark:
		return
	match _mode:
		"room":
			match _phase:
				0:
					_main._set_char("bill")
					_main.start_game()
					_main._load_level(1) # L2 基地1
					_main._advance_dialog()
					_mark = _frame + 150
					_phase = 1
				1:
					_snap("fix_l2room_after.png")
					print("ROOM DONE")
					quit(0)
		"sky":
			match _phase:
				0:
					_main._set_char("bill")
					_main.start_game()
					_main._advance_dialog()
					_phase = 1
					_mark = _frame + 1
				1:
					if _lv >= 8:
						print("SKY DONE")
						quit(0)
						return
					_main._load_level(_lv)
					_main._advance_dialog()
					var lv = _main.current_level
					_rig.cam = _main.camera
					_rig.main_ref = _main
					var gy: float = lv.get_support_y(0.0, 20.0, 999.0)
					if String(lv.data["theme"]).begins_with("base") or String(lv.data["theme"]) == "hangar":
						# 室内关：主场景内景远景（走廊纵深 + 顶面）
						_rig.pos = Vector3(10.0, gy + 3.2, 24.0)
						_rig.look = Vector3(-6.0, gy + 2.2, -80.0)
					else:
						_rig.pos = Vector3(6.0, gy + 7.0, 38.0)
						_rig.look = Vector3(-4.0, gy + 2.0, -90.0)
					_mark = _frame + 100
					_phase = 2
				2:
					_snap("fix_sky_lv%d.png" % (_lv + 1))
					_lv += 1
					_phase = 1
					_mark = _frame + 1
