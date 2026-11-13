extends SceneTree

## 挂枪数值探针 2（主场景内）：量主角/一名步枪兵的枪网格全局 AABB 与 hand_r 骨全局位
var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _report(tag: String, holder: Node) -> void:
	var skel := _find_skel(holder)
	if skel == null:
		print("ATTACH2 ", tag, " NO SKEL")
		return
	var hi := skel.find_bone("hand_r")
	var hand_pos: Vector3 = (skel.global_transform * skel.get_bone_global_pose(hi)).origin
	print("ATTACH2 ", tag, " hand=", hand_pos)
	var stack: Array = [holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.name.contains("M4A1") or mi.name.contains("AssaultRifle") or mi.name.contains("SniperRifle"):
				var ab := mi.global_transform * mi.get_aabb()
				print("ATTACH2 ", tag, " mesh=", mi.name, " size=", ab.size, " center=", ab.get_center(), " hand_d=", (ab.get_center() - hand_pos).length())

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 40:
				_main.start_game()
				_main._advance_dialog()
				_phase = 1
		1:
			if _frame > 60:
				_report("bill", _main.player)
				for e in _main.current_level.enemies:
					if e.type == "rifleman":
						_report("rifleman", e)
						break
				print("ATTACH2 DONE")
				quit(0)
