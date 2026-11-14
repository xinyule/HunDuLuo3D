extends SceneTree

## 1.2.1 触控层截图：进关后强制显示 touch_ui，在关卡场景前截一帧核对
## 摇杆（左下）与三图标钮（右下）的可见性与位置。
## 运行：xvfb-run godot --path . --script res://test/touch_shot.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := "boot"
var _snap_at := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main.start_game()
				_phase = "wait"
		"wait":
			if _main.state == "dialog" and _main.current_level != null and _main.player != null:
				_main._advance_dialog()
				_main.player.barrier = 999999.0
				_main.touch_ui.visible = true
				# 摇杆推右模拟持握姿态，摇杆头偏移也一并入镜
				_main._touch_joy.value = Vector2(0.7, 0.3)
				_main._touch_joy.queue_redraw()
				_snap_at = _frame + 45
				_phase = "shot"
		"shot":
			if _frame >= _snap_at:
				var img := root.get_texture().get_image()
				var path := "/home/hatch/workspace/HunDuLuo3D_work/shots/touch_ui.png"
				img.save_png(path)
				print("SNAP ", path, " ", img.get_size())
				quit(0)
