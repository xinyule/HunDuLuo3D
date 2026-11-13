extends SceneTree

var _main: Node
var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _probe(lv: int, pts: Array) -> void:
	_main._load_level(lv)
	_main._advance_dialog()
	var level = _main.current_level
	for p in pts:
		var x := float(p[0])
		var z := float(p[1])
		print("  L%d base(%.0f, %.0f) = %.2f  terr = %.2f" % [lv + 1, x, z, level._base_height(x, z), level.terrain_h(x, z)])

func _on_frame() -> void:
	_frame += 1
	if _frame == 3:
		_main._set_lives("inf")
		_main.start_game()
		print("== L1 hill (33,-444) r15 ==")
		_probe(0, [[33, -444], [59, -444], [7, -444], [33, -418], [33, -470], [33, -430], [20, -444], [46, -444]])
		print("== L1 hill (-25,-124) r16 ==")
		_probe(0, [[-25, -124], [-52, -124], [2, -124], [-25, -97], [-25, -151]])
		print("== L5 hill (-30,-174) r19 ==")
		_probe(4, [[-30, -174], [-60, -174], [0, -174], [-30, -144], [-30, -204]])
		print("== L5 dip (24,-748) r14 ==")
		_probe(4, [[24, -748], [49, -748], [-1, -748], [24, -723], [24, -773]])
		print("== L5 dip (-6,-534) r17 ==")
		_probe(4, [[-6, -534], [-34, -534], [22, -534], [-6, -506], [-6, -562]])
		print("== L5 cliff spot (24,-439) ==")
		_probe(4, [[24, -439], [24, -436], [24, -442], [21, -439], [27, -439], [18, -424], [26, -444]])
		print("== L6 hill (-20,-354) r15 ==")
		_probe(5, [[-20, -354], [-46, -354], [6, -354], [-20, -328], [-20, -380]])
		print("== L7 hill (24,-394) r16 ==")
		_probe(6, [[24, -394], [51, -394], [-3, -394], [24, -367], [24, -421]])
		quit(0)
