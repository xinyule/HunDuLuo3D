extends SceneTree

## Boss 竞技场回归测试（专防 v3.0.0「屏障刷在玩家面前」软锁）：
## ① 入口线外不触发 ② 入场后屏障落在身后 ③ 能走到 Boss 跟前
## ④ 先塔后芯打通 ⑤ 击败后屏障与封路碰撞解除、能走过 Boss 位置
## 运行：xvfb-run godot --path . --script res://test/bossfight.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := 0
var _fails := 0
var _col_ref: Dictionary = {}
var _blk_ref: Dictionary = {}

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _check(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + label)
	if not cond:
		_fails += 1

func _dist() -> float:
	return 26.0 - _main.player.global_position.z

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 30:
				_main.start_game()
				_main._advance_dialog()
				_main.player.barrier = 99999.0
				# 入口线（dist=179）之外：dist=160 处不应触发
				_main.player.global_position = Vector3(0, 0, 26.0 - 160.0)
				_phase = 1
		1:
			if _frame > 70:
				_check(not _main.current_level.boss_activated, "入口线外 Boss 未触发")
				# 走进竞技场：dist=185（已越线 6 米）
				_main.player.global_position = Vector3(0, 0, 26.0 - 185.0)
				_phase = 2
		2:
			if _frame > 110:
				var lv = _main.current_level
				_check(lv.boss_activated, "入场后 Boss 触发")
				_check(lv._barrier_wall != null, "屏障已生成")
				if lv._barrier_wall:
					_check(lv._barrier_wall.global_position.z > _main.player.global_position.z, "屏障在玩家身后（不是面前）")
				_col_ref = lv._barrier_col
				_blk_ref = lv._boss_blocker
				# 走向 Boss：应能到达距 Boss 10 米内（不被屏障/封路挡住）
				_main.player.global_position = Vector3(0, 0, lv.boss_z + 10.0)
				_phase = 3
		3:
			if _frame > 150:
				_check(absf(_main.player.global_position.z - (_main.current_level.boss_z + 10.0)) < 2.0, "玩家能站到 Boss 跟前 10 米")
				var boss = _main.current_level.boss
				for p in boss.targets:
					if p.part_name == "turret":
						p.on_hit(99999)
				var core = null
				for p in boss.targets:
					if p.is_core:
						core = p
				_check(core != null and core.vulnerable, "双塔毁后核心暴露")
				core.on_hit(99999)
				_check(not boss.alive, "核心击破 Boss 死亡")
				_phase = 4
		4:
			if _frame > 200:
				# 击败后主流程会切到下一关，故查第 1 关那两个碰撞字典的引用本身
				_check(bool(_col_ref.get("disabled", false)), "击败后屏障碰撞解除")
				_check(bool(_blk_ref.get("disabled", false)), "击败后 Boss 封路解除")
				if _fails == 0:
					print("BOSSFIGHT PASS")
					quit(0)
				else:
					print("BOSSFIGHT FAIL x", _fails)
					quit(1)
