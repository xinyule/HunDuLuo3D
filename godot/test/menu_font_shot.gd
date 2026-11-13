extends SceneTree

## 1.2.0 字体乱码插队诊断：主菜单整页截图（逐项核对文字渲染）
## 运行：xvfb-run godot --path . --script res://test/menu_font_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

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
		var img := root.get_texture().get_image()
		img.save_png(DIR + "menu_font_check.png")
		print("SNAP menu_font_check.png")
		quit()
