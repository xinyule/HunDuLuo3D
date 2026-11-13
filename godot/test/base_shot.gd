extends SceneTree

## 基地1 结构验收截图：电网门走廊全景 + 交错偏置感应器/墙根维修道近景
## 运行：xvfb-run godot --path . --script res://test/base_shot.gd --rendering-driver opengl3 --resolution 1280x720

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
	print("SNAP ", path, " ", img.get_size())

func _on_frame() -> void:
	_frame += 1
	var lv = _main.current_level
	match _phase:
		0:
			if _frame == 3:
				_main.start_game()
			elif _frame == 5:
				_main._load_level(1)
			elif _frame == 7:
				_main._advance_dialog()
				_main.player.barrier = 999999.0
				_main._yaw = PI
				# 第一道门（dist 32）前 14m：看走廊纵深+两侧维修道
				_main.player.global_position = Vector3(6, 0, 26.0 - 18.0)
				_phase = 1
		1:
			if _frame > 110:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/base1_corridor.png")
				# 第二道门（gi=1，感应器偏另一侧）前：站到感应器对面看偏置+维修道掩体
				var g = lv.gates[1]
				_main.player.global_position = Vector3(-float(g["sensor"].hit_x) * 0.55, 0, float(g["z"]) + 13.0)
				_main._yaw = PI
				_phase = 2
		2:
			if _frame > 220:
				_snap("/home/hatch/workspace/HunDuLuo3D_work/shots/base1_sensor.png")
				print("BASE SHOTS DONE len=", lv.length, " gates=", lv.gates.size(), " sensors_x=", lv.sensors.map(func(s): return s.hit_x))
				quit(0)
