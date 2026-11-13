extends SceneTree

## 1.2.0 字体修复全文字面截图实证：菜单 → 剧情框 → HUD → 加载界面
## 前置：打包字体导入须 allow_system_fallback=false——本地即便有系统 CJK 也不许回退，
## 截图干净即证明打包字体自足（三端同字体数据、渲染一致）。
## 运行：xvfb-run godot --path . --script res://test/font_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0
var _wait := 0

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
			if _frame > 45:
				_snap("menu_font_check.png")
				_main.start_game()
				_phase = 1
		1:
			if _main.state == "dialog":
				_wait += 1
				if _wait > 3:
					_snap("font_dialog.png")
					_main._advance_dialog()
					_phase = 2
					_wait = 0
		2:
			_wait += 1
			if _wait > 90:
				_snap("font_hud.png")
				_main._show_loading(4) # 第 5 关（最长关）加载界面：关名+阶段+进度+提示
				_phase = 3
				_wait = 0
		3:
			_wait += 1
			if _wait > 3:
				_snap("font_loading.png")
				print("FONT_SHOT DONE")
				quit()
