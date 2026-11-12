extends SceneTree

## Boss 墙体视觉自检：竞技场内看防御壁全貌 + 核心暴露两张
## 运行：xvfb-run godot --path . --script res://test/boss_shot.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("SNAP ", path)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 30:
				_main.start_game()
				_main._advance_dialog()
				_main.player.barrier = 99999.0
				_main.player.global_position = Vector3(0, 0, 26.0 - 196.0)
				_phase = 1
		1:
			if _frame > 90:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/boss_wall.png")
				var boss = _main.current_level.boss
				for p in boss.targets:
					if p.part_name == "turret":
						p.on_hit(99999)
				_phase = 2
		2:
			if _frame > 130:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/boss_core.png")
				print("BOSS SHOTS DONE")
				quit(0)
