extends SceneTree

## C 线（音频与 UI）验收截图：菜单（徽标+描边标题+金条）→ 游戏内准星（平时）→ 准星（瞄准变色）
## 运行：xvfb-run godot --path . --script res://test/ui_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(snap_name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + snap_name)
	print("SNAP ", snap_name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 20:
				_snap("ui_menu.png")
				_main.start_game()
				_phase = 1
				_frame = 0
		1:
			if _frame > 30:
				_main._advance_dialog() # 进 playing
				_phase = 2
				_frame = 0
		2:
			if _frame > 40:
				_snap("ui_cross.png")
				Input.action_press("aim")
				_phase = 3
				_frame = 0
		3:
			if _frame > 12:
				_snap("ui_cross_aim.png")
				Input.action_release("aim")
				print("UI_SHOT DONE")
				quit()
