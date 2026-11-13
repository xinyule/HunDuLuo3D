extends SceneTree

## 集成验收：逐关实战截图（玩家身后越肩视角，往关卡深处看）
## 运行：xvfb-run godot --path . --script res://test/integ_shot.gd --rendering-driver opengl3 --resolution 1280x720 -- <关号1-8>

var _main: Node
var _frame := 0
var _phase := 0
var _lv := 1

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_lv = int(args[0])
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 40:
				_main.ui.visible = false
				_main.start_game(_lv - 1)
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				_phase = 1
		1:
			if _frame > 85:
				# 把玩家往关内推进一段，拍到敌人与场景纵深
				var pp: Vector3 = _main.player.global_position
				_main.camera.position = pp + Vector3(2.2, 2.0, 5.2)
				_main.camera.look_at(pp + Vector3(0, 1.0, -14), Vector3.UP)
				_phase = 2
		2:
			if _frame > 95:
				var img := root.get_texture().get_image()
				img.save_png("/home/hatch/workspace/HunDuLuo3D_work/shots/integ_lv%d.png" % _lv)
				print("INTEG SNAP lv", _lv)
				quit(0)
