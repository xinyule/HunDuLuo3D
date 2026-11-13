extends SceneTree

## 终检探针：完整通关链（菜单→逐关 Boss→评级/选关解锁/图鉴/存档→胜利结算）
## 兼验：①旧存档（只有最高分+未知键）可读不报错 ②_save_hi 不抹 emblems 键
## ③图鉴 garth 键名修复回归（L4 击杀加尔斯后图鉴登记命中 BESTIARY 键）
## 运行：godot --headless --path . --script res://test/final_clear.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _pass := 0
var _fail := 0
var _phase := "boot"
var _wait := 0
var _lv := 0
var _sub_frames := 0
var _seeded_hi := 777

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok - ", label)
	else:
		_fail += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	# 预置「旧存档」：只有最高分 + 一个本版本新键（模拟老档被新版读）
	var cfg := ConfigFile.new()
	cfg.set_value("game", "hi", _seeded_hi)
	cfg.set_value("progress", "emblems_0", 5)
	cfg.save("user://contra3d_save.cfg")
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _wait_frames(n: int, next: String) -> void:
	_wait = n
	_phase = "wait"
	_next = next

var _next := ""

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_check(_main.hi_score == _seeded_hi, "旧存档最高分读入 (hi=%d)" % _main.hi_score)
				_main._set_lives("inf")
				_main.start_game()
				_phase = "enter"
				_sub_frames = 0
		"wait":
			_wait -= 1
			if _wait <= 0:
				_phase = _next
				_sub_frames = 0
		"enter":
			_sub_frames += 1
			if _main.state == "dialog":
				_main._advance_dialog()
				_wait_frames(5, "bestiary")
			elif _sub_frames > 900:
				_check(false, "L%d 进入超时 state=%s" % [_lv + 1, _main.state])
				_finish()
		"bestiary":
			_check(_main.level_index == _lv, "当前关卡 = L%d" % (_lv + 1))
			_check(_main.state == "playing", "L%d 处于 playing" % (_lv + 1))
			var lvl = _main.current_level
			_main.player.barrier = 99999.0
			if _lv == 3:
				# 图鉴修复回归：专杀一只 garth
				var g = null
				for e in lvl.enemies:
					if String(e.type) == "garth":
						g = e
						break
				_check(g != null, "L4 存在 garth 敌人")
				if g != null:
					g.on_hit(999999)
				_wait_frames(10, "bestiary_garth")
			elif lvl.enemies.size() > 0:
				var e0 = lvl.enemies[0]
				var t0 := String(e0.type)
				e0.on_hit(999999)
				_wait_frames(10, "bestiary_any")
				_pending_type = t0
			else:
				_phase = "to_boss"
				_sub_frames = 0
		"bestiary_any":
			_check(_main.encountered.has(_pending_type), "击杀登记图鉴 %s" % _pending_type)
			_phase = "to_boss"
			_sub_frames = 0
		"bestiary_garth":
			_check(_main.encountered.has("garth"), "击杀 garth 后 encountered 登记")
			_check(Data.BESTIARY.has("garth") and _main.encountered.has("garth"), "图鉴加尔斯条目可点亮（键名对齐）")
			_phase = "to_boss"
			_sub_frames = 0
		"to_boss":
			var lvl2 = _main.current_level
			_main.player.global_position = Vector3(0, lvl2.get_support_y(0.0, lvl2.boss_z + 18.0, 999.0), lvl2.boss_z + 18.0)
			_main.player.barrier = 99999.0
			_phase = "wait_boss"
			_sub_frames = 0
		"wait_boss":
			_sub_frames += 1
			if _main.current_level.boss_activated:
				_check(true, "L%d Boss 触发" % (_lv + 1))
				_phase = "kill_boss"
				_sub_frames = 0
			elif _sub_frames > 900:
				_check(false, "L%d Boss 未触发" % (_lv + 1))
				_finish()
		"kill_boss":
			_sub_frames += 1
			var boss = _main.current_level.boss
			if not boss.alive:
				_check(true, "L%d Boss 击败" % (_lv + 1))
				_phase = "wait_clear"
				_sub_frames = 0
			else:
				if _sub_frames % 15 == 0:
					for p in boss.targets:
						p.on_hit(999999)
				if _sub_frames > 3600:
					_check(false, "L%d Boss 击杀超时" % (_lv + 1))
					_finish()
		"wait_clear":
			_sub_frames += 1
			if _main.state == "levelclear":
				_check(bool(_main.cleared_levels.get(_lv, false)), "L%d cleared_levels 落记" % (_lv + 1))
				var r := String(_main.level_ratings.get(_lv, ""))
				_check(["S", "A", "B", "C"].has(r), "L%d 评级有效 (%s)" % [_lv + 1, r])
				if _lv < 7:
					_check(_main.unlocked_max >= _lv + 1, "L%d 通关解锁下一关 (unlocked=%d)" % [_lv + 1, _main.unlocked_max])
				if _lv == 0:
					var cfg2 := ConfigFile.new()
					_check(cfg2.load("user://contra3d_save.cfg") == OK, "过关后存档可读")
					_check(int(cfg2.get_value("progress", "emblems_0", 0)) == 5, "存档 emblems_0 键未被 _save_hi 抹掉")
					_check(bool(cfg2.get_value("progress", "cleared_0", false)), "存档 cleared_0 已写入")
					_check(String(cfg2.get_value("progress", "rating_0", "")) != "", "存档 rating_0 已写入")
				_phase = "wait_next"
				_sub_frames = 0
			elif _sub_frames > 1200:
				_check(false, "L%d 过关结算超时 state=%s" % [_lv + 1, _main.state])
				_finish()
		"wait_next":
			_sub_frames += 1
			if _lv >= 7:
				if _main.state == "victory":
					_check(true, "全关通关进入 victory (score=%d)" % _main.score)
					_check(_main.score > _seeded_hi, "总分高于种子最高分")
					_check(_main.hi_score == _main.score, "最高分已更新为总分 (hi=%d)" % _main.hi_score)
					var cfg3 := ConfigFile.new()
					_check(cfg3.load("user://contra3d_save.cfg") == OK, "终局存档可读")
					_check(bool(cfg3.get_value("progress", "cleared_7", false)), "存档 cleared_7 已写入")
					_check(int(cfg3.get_value("progress", "emblems_0", 0)) == 5, "终局存档 emblems_0 仍在")
					_finish()
				elif _sub_frames > 1200:
					_check(false, "victory 超时 state=%s" % _main.state)
					_finish()
			else:
				if _main.level_index == _lv + 1 and (_main.state == "dialog" or _main.state == "playing"):
					_lv += 1
					_phase = "enter"
					_sub_frames = 0
				elif _sub_frames > 1200:
					_check(false, "进入 L%d 超时 (idx=%d state=%s)" % [_lv + 2, _main.level_index, _main.state])
					_finish()

var _pending_type := ""
var _finished := false

func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("CLEAR RESULT: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
