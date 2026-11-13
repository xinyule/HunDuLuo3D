extends SceneTree

## 第二线健全性探针：逐关建关 + 数据自洽断言（长度/营地/机关/鹰徽/起伏/夹层）
## 运行：godot --headless --path . --script res://test/long_sanity.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _lv := -1
var _wait := 0
var _pass := 0
var _fail := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	if _frame == 3:
		_main._set_lives("inf")
		_main.start_game()
		_lv = 0
		_wait = 5
		return
	if _lv < 0 or _frame < _wait:
		return
	if _lv >= Data.LEVELS.size():
		print("SANITY RESULT: %d passed, %d failed" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)
		return
	_main._load_level(_lv)
	_main._advance_dialog()
	_inspect(_lv)
	_lv += 1
	_wait = _frame + 3

func _inspect(lv: int) -> void:
	var d: Dictionary = Data.LEVELS[lv]
	var level = _main.current_level
	var length := float(d["length"])
	print("== L%d %s length=%.0f ==" % [lv + 1, String(d["name"]), length])
	# 数据层断言：所有 dist 驱动的布点都必须落在关内（留 Boss 场余量）
	var max_spawn := 0.0
	for s in d["spawns"]:
		max_spawn = maxf(max_spawn, float(s[0]))
	_check(max_spawn < length - 12.0, "L%d 营地最远 dist=%.0f < length-12" % [lv + 1, max_spawn])
	for key in ["gates", "flames", "carts", "crushers", "falcons"]:
		var arr: Array = d.get(key, [])
		var mx := 0.0
		for v in arr:
			mx = maxf(mx, float(v))
		_check(mx < length - 25.0, "L%d %s 最远 %.0f < length-25（共 %d 个）" % [lv + 1, key, mx, arr.size()])
	# 鹰徽：3 枚、全在可达半宽内、z 在关内
	var es: Array = d.get("emblems", [])
	_check(es.size() == 3, "L%d 鹰徽 3 枚（实 %d）" % [lv + 1, es.size()])
	var half: float = level.playable_half_width()
	for ei in es.size():
		var ex := float(es[ei][0])
		var ez := float(es[ei][1])
		_check(absf(ex) <= half - 0.99, "L%d 鹰徽%d x=%.1f 在可达半宽 %.1f 内" % [lv + 1, ei + 1, ex, half])
		_check(ez < 20.0 and ez > -length - 4.0, "L%d 鹰徽%d z=%.1f 在关内" % [lv + 1, ei + 1, ez])
	# 建关产物计数
	print("  built: enemies=%d gates=%d flames=%d carts=%d crushers=%d colliders=%d pads=%d" % [
		level.enemies.size(), level.gates.size(), level.flames.size(), level.carts.size(), level.crushers.size(), level.colliders.size(), level._pads.size()])
	_check(level.enemies.size() >= int(d["spawns"].size()), "L%d 敌人数 %d >= 数据营地条数 %d" % [lv + 1, level.enemies.size(), int(d["spawns"].size())])
	_check(level.gates.size() == int(d.get("gates", []).size()), "L%d 电网门数与数据一致" % (lv + 1))
	# 地形抽样：全程网格无 NaN/无深渊（rim 带外）
	var bad := 0
	var steep := 0
	var z := 20.0
	while z > -length:
		var x := -half + 2.0
		while x < half - 2.0:
			var h: float = level.terrain_h(x, z)
			if is_nan(h) or h < -6.0 or h > 90.0:
				bad += 1
			x += 6.0
		z -= 6.0
	_check(bad == 0, "L%d 地形抽样无异常高度（bad=%d）" % [lv + 1, bad])
	# 起伏/夹层数据回显
	print("  relief=%d mezzanines=%d par_time=%.0fs par_score=%.0f" % [
		int(d.get("relief", []).size()), int(d.get("mezzanines", []).size()), length * 0.55, 2600.0 + length * 4.0])
