extends SceneTree

## 新功能批验收截图：菜单（难度/画质/选关/图鉴入口）→ 图鉴面板 → 边缘箭头 → Boss 血条 → 击杀飘分
## 运行：xvfb-run godot --path . --script res://test/feat_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 12:
				_snap("feat_menu.png")
				_main._show_codex()
				_phase = 1
		1:
			if _frame > 18:
				_snap("feat_codex.png")
				_main.codex_panel.visible = false
				_main.start_game()
				_main._advance_dialog()
				_main._yaw = 0.0 # 背对推进方向 → 边缘箭头应出现
				_phase = 2
		2:
			if _frame > 30:
				_snap("feat_arrow.png")
				_main._yaw = PI
				_main.player.barrier = 9999.0
				_main.player.global_position = Vector3(0, 0, 26.0 - (_main.current_level.length - 5.0))
				_phase = 3
		3:
			if _frame > 90:
				_snap("feat_bossbar.png")
				var lv = _main.current_level
				lv._spawn_enemy("rifleman", _main.player.global_position.x + 1.5, _main.player.global_position.z - 6.0)
				var e = lv.enemies[lv.enemies.size() - 1]
				e.on_hit(999, e.global_position + Vector3(0, 1.2, 0))
				_phase = 4
		4:
			if _frame > 94:
				_snap("feat_float.png")
				print("FEAT SHOT DONE")
				quit(0)
