extends SceneTree

## 1.2.1 画质设置面板截图：菜单态打开面板截一帧，人工核对 7 行布局与说明文字。
## 运行：xvfb-run godot --path . --script res://test/gfx_shot.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	if _frame == 45:
		_main._gfx_panel.visible = true
	if _frame == 75:
		var img := root.get_texture().get_image()
		var path := "/home/hatch/workspace/HunDuLuo3D_work/shots/gfx_panel.png"
		img.save_png(path)
		print("SNAP ", path, " ", img.get_size())
		quit(0)
