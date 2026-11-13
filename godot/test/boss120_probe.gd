extends SceneTree

## 1.2.0 最终 Boss 可通关实证（L8 天王创魔心）：
## ① 心 HP = 4500 ② 用真实射击链（player.try_shoot 按现行射速 0.08s 门控、瞄部件命中中心）
##    先斩龙（1870）后打心，测总击杀耗时 ③ 增援：约 12s 一波、兵种随机、场上存活 ≤6
## 玩家开 barrier 无敌——只验输出侧可通关性（承伤侧由难度设计另行控制）。
## 运行：godot --headless --path . --script res://test/boss120_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := "boot"
var _sub := 0
var _fails := 0
var _fight_start := -1
var _dragon_dead_frame := -1
var _boss_dead_frame := -1
var _max_reinf := 0
var _reinf_types := {}
var _saw_reinf := false

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _check(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + label)
	if not cond:
		_fails += 1

func _part(boss, nm: String):
	for p in boss.targets:
		if p.part_name == nm:
			return p
	return null

func _on_frame() -> void:
	_frame += 1
	_sub += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game(7)
				_phase = "enter"
				_sub = 0
		"enter":
			if _main.state == "dialog":
				_main._advance_dialog()
				_phase = "to_boss"
				_sub = 0
			elif _sub > 1800:
				_check(false, "L8 进入超时")
				_finish()
		"to_boss":
			var lv = _main.current_level
			_main.player.barrier = 99999.0
			_main.player.global_position = Vector3(2.0, lv.get_support_y(2.0, lv.boss_z + 15.0, 999.0), lv.boss_z + 15.0)
			_phase = "wait_act"
			_sub = 0
		"wait_act":
			_main.player.barrier = 99999.0
			if _main.current_level.boss_activated:
				var boss = _main.current_level.boss
				var heart = _part(boss, "heart")
				_check(heart != null and heart.max_hp == 4500, "创魔心 HP=4500 (实测 %d)" % (heart.max_hp if heart else -1))
				_fight_start = _frame
				_phase = "fight"
				_sub = 0
			elif _sub > 900:
				_check(false, "Boss 未触发")
				_finish()
		"fight":
			_main.player.barrier = 99999.0
			var lv = _main.current_level
			var boss = lv.boss
			if not boss.alive:
				_boss_dead_frame = _frame
				_report()
				_finish()
				return
			# 增援观测：每帧读 Boss 的增援登记（存活上限断言）+ 记录见过的兵种
			var alive_reinf := 0
			for e in boss._reinforcements:
				if is_instance_valid(e) and e.alive:
					alive_reinf += 1
					_reinf_types[String(e.type)] = true
			_max_reinf = maxi(_max_reinf, alive_reinf)
			if alive_reinf > 0:
				_saw_reinf = true
			# 目标选择（模拟玩家）：先清挡路/贴近的增援，再打 Boss 部件（龙→心）
			var tgt: Vector3 = Vector3.INF
			var near_e = null
			var near_d := 26.0
			for e in lv.enemies:
				if e.alive and e.targetable:
					var d: float = e.global_position.distance_to(_main.player.global_position)
					if d < near_d:
						near_d = d
						near_e = e
			if near_e != null:
				tgt = Vector3(near_e.hit_x, near_e.hit_y, near_e.hit_z)
			else:
				var dragon = _part(boss, "dragon")
				var heart = _part(boss, "heart")
				var p = dragon if (dragon != null and dragon.alive) else heart
				if p != null:
					tgt = Vector3(p.hit_x, p.hit_y, p.hit_z)
			if tgt != Vector3.INF:
				_main.player.try_shoot(_main.projectiles, tgt)
			var dragon2 = _part(boss, "dragon")
			if _dragon_dead_frame < 0 and dragon2 != null and not dragon2.alive:
				_dragon_dead_frame = _frame
			if _frame - _fight_start > 60 * 300: # 300 秒还打不死 = 不可通关
				_check(false, "300 秒未击杀 Boss（不可通关）")
				_report()
				_finish()

func _report() -> void:
	var t_dragon := (_dragon_dead_frame - _fight_start) / 60.0 if _dragon_dead_frame > 0 else -1.0
	var t_total := (_boss_dead_frame - _fight_start) / 60.0 if _boss_dead_frame > 0 else -1.0
	print("  龙斩杀 %.1fs / Boss 总击杀 %.1fs / 增援峰值存活 %d / 增援兵种 %s" % [t_dragon, t_total, _max_reinf, str(_reinf_types.keys())])
	_check(_boss_dead_frame > 0, "Boss 可击杀（真实射击链）")
	_check(t_total > 0.0 and t_total <= 300.0, "击杀耗时在 300s 内 (%.1fs)" % t_total)
	_check(_saw_reinf, "增援波已出现")
	_check(_max_reinf <= 6, "增援存活峰值 ≤6 (实测 %d)" % _max_reinf)
	_check(_reinf_types.size() >= 2, "增援兵种随机 ≥2 种 (实测 %s)" % str(_reinf_types.keys()))

func _finish() -> void:
	if _fails == 0:
		print("BOSS120 PASS")
		quit(0)
	else:
		print("BOSS120 FAIL x", _fails)
		quit(1)
