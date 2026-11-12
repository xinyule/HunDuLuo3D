extends SceneTree

## 无头冒烟：驱动主场景走完 菜单→开局→移动→射击→击杀→电网门→Boss→过关→阵亡续关 全流程
## 运行：godot --headless --path . --script res://test/smoke.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := 0
var _wait_until := 0
var _pass := 0
var _fail := 0
var _score_before := 0

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

func _wait(frames: int) -> void:
	_wait_until = _frame + frames
	_phase += 1

func _on_frame() -> void:
	_frame += 1
	if _frame < _wait_until:
		return
	match _phase:
		0:
			_check(_main.state == "menu", "启动进菜单")
			_main._set_char("lance")
			_check(_main.char_id == "lance", "角色切换兰斯")
			_main._set_char("bill")
			_main._set_lives("inf")
			_check(_main.lives_choice == "inf", "命数可选∞")
			_main._set_lives(3)
			_main.start_game()
			_check(_main.state == "dialog", "开局剧情 dialog")
			_main._advance_dialog()
			_check(_main.state == "playing", "进入 playing")
			_check(_main.player != null and _main.current_level != null, "玩家与关卡已建")
			_main.player.barrier = 9999.0
			Input.action_press("move_forward")
			_wait(200)
		1:
			Input.action_release("move_forward")
			var dist: float = _main.current_level.player_dist(_main.player)
			_check(dist > 12.0, "前进推进 %.1fm" % dist)
			_check(_main.current_level.enemies.size() > 0, "分段刷怪已触发 (%d)" % _main.current_level.enemies.size())
			_main.player.fire_timer = 0.0
			_check(_main.player.try_shoot(_main.projectiles, _main.player.global_position + Vector3(0, 1.2, -30)), "射击成功")
			# 直接击杀一名敌人验证计分链
			var e = _main.current_level._spawn_enemy("rifleman", 0.0, _main.player.global_position.z - 8.0)
			_score_before = _main.score
			e.on_hit(9999)
			_check(not e.alive and _main.score > _score_before, "击杀计分 +%d" % (_main.score - _score_before))
			_wait(100)
		2:
			# 第二关电网门
			_main._load_level(1)
			_main._advance_dialog()
			_check(_main.current_level.sensors.size() == 3, "基地电网门×3")
			var s = _main.current_level.sensors[0]
			s.on_hit(9999)
			_check(not s.alive, "感应器可击毁")
			_wait(30)
		3:
			# 回第一关打 Boss
			_main._load_level(0)
			_main._advance_dialog()
			_main.player.barrier = 9999.0
			_main.player.global_position = Vector3(0, 0, -(190.0 - 5.0) + 26.0)
			_wait(40)
		4:
			_check(_main.current_level.boss_activated, "Boss 竞技场触发")
			var boss = _main.current_level.boss
			for p in boss.targets:
				if p.part_name == "turret":
					p.on_hit(99999)
			var core = null
			for p in boss.targets:
				if p.is_core:
					core = p
			_check(core != null and core.vulnerable, "双塔毁后核心可伤")
			core.on_hit(99999)
			_check(not boss.alive, "Boss 击败")
			_wait(320)
		5:
			_check(_main.level_index == 1, "过关进入第2关 (idx=%d)" % _main.level_index)
			# 阵亡与复活
			_main._advance_dialog()
			_main.lives = 3
			_main.lives_inf = false
			_main.player.barrier = 0.0
			_main.player.invuln = 0.0
			_main.player.take_damage(1)
			_main.player.invuln = 0.0
			_main.player.take_damage(1)
			_main.player.invuln = 0.0
			_main.player.take_damage(1)
			_check(not _main.player.alive, "三格血耗尽阵亡")
			_wait(140)
		6:
			_check(_main.lives == 2 and _main.player.alive, "扣命复活 (lives=%d)" % _main.lives)
			# 命尽 → 失败 → 续关
			_main.lives = 1
			_main.player.invuln = 0.0
			_main.player.take_damage(1)
			_main.player.invuln = 0.0
			_main.player.take_damage(1)
			_main.player.invuln = 0.0
			_main.player.take_damage(1)
			_wait(140)
		7:
			_check(_main.state == "gameover", "命尽进失败画面 (state=%s)" % _main.state)
			_main._continue_game()
			_check(_main.continues_left == 2 and _main.state == "dialog", "续关重开本关")
			_main._advance_dialog()
			_check(_main.state == "playing" and _main.player.alive, "续关后可玩")
			print("SMOKE RESULT: %d passed, %d failed" % [_pass, _fail])
			quit(1 if _fail > 0 else 0)
