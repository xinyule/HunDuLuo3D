extends SceneTree

## 终检诊断：打印 L4 在 x∈[22,34]、z∈[-216,-196] 区域的碰撞体（定位 lane28 超时点）
## 运行：godot --headless --path . --script res://test/final_diag.gd --fixed-fps 60

var _main: Node
var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	if _frame == 3:
		_main.start_game()
		_main._load_level(3)
		var lvl = _main.current_level
		print("L4 colliders near lane x=28, gate7 后 (z -216..-196):")
		for c in lvl.colliders:
			var cx := float(c.get("x", 0.0))
			var cz := float(c.get("z", 0.0))
			if cx > 20.0 and cx < 36.0 and cz > -216.0 and cz < -196.0:
				print("  ", c)
		print("DIAG DONE")
		quit(0)
