extends SceneTree

## 兵种列队（游戏场景内）：冻结主循环后手动摆相机，七人形兵种走真实 setup 生成
## 运行：xvfb-run godot --path . --script res://test/cast_lineup.gd --rendering-driver opengl3 --resolution 1280x720
var _main: Node
var _frame := 0
var _phase := 0

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"
const TYPES := ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar"]

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 40:
				_main.ui.visible = false
				_main.start_game()
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				_main.set_process(false)
				_main.set_physics_process(false)
				var lv = _main.current_level
				lv.set_process(false)
				lv.set_physics_process(false)
				var i := 0
				for t in TYPES:
					var x := -4.5 + i * 1.5
					var z := -10.0
					var e := Enemy.new()
					lv.add_child(e)
					e.setup(t, Vector3(x, lv.get_support_y(x, z, 999.0), z), lv._enemy_ctx, _main.soldier_scenes)
					if t == "akbar":
						e._model.position.y = 0.0 # 列队展示：抵消水中下潜
					i += 1
				_phase = 1
		1:
			_main.camera.position = Vector3(0, 1.6, -1.2)
			_main.camera.look_at(Vector3(0, 0.95, -10), Vector3.UP)
			if _frame > 75:
				_snap("cast_lineup.png")
				_phase = 2
		2:
			_main.camera.position = Vector3(0.8, 1.35, -6.0)
			_main.camera.look_at(Vector3(0.8, 1.0, -10), Vector3.UP)
			if _frame > 90:
				_snap("cast_lineup_close.png")
				print("LINEUP DONE")
				quit(0)
