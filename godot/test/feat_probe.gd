extends SceneTree

## 新功能批验收探针：逐项断言（难度/画质/飘分连杀/评级选关/图鉴/对象池/环境互动）
## 运行：godot --headless --path . --script res://test/feat_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := 0
var _wait_until := 0
var _pass := 0
var _fail := 0
var _w0 := 0.0
var _bt1 = null
var _bt2 = null
var _victim = null
var _gx := Vector3.ZERO

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
			# ---- 难度档 ----
			_main._set_difficulty("hard")
			_check(is_equal_approx(_main.projectiles.orb_speed_scale, 1.15), "难度困难: 弹速倍率 1.15")
			_main._set_difficulty("easy")
			_check(is_equal_approx(_main.projectiles.orb_speed_scale, 0.85), "难度简单: 弹速倍率 0.85")
			_main.projectiles.spawn_orb(Vector3(0, 1, 0), Vector3(0, 0, -1), 20.0, 1)
			var spd: float = _main.projectiles._orbs[0]["speed"]
			_check(is_equal_approx(spd, 17.0), "光弹实际速度已缩放 (%.1f)" % spd)
			_main.projectiles.clear_all()
			_main._set_difficulty("normal")
			_check(is_equal_approx(_main.projectiles.orb_speed_scale, 1.0), "难度普通: 弹速倍率 1.0")
			_check(_main.difficulty == "normal", "难度选择已保存")
			# ---- 画质分档 ----
			_main._set_quality("low")
			_check(_main.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "画质低: MSAA 关")
			_main._set_quality("mid")
			_check(_main.get_viewport().msaa_3d == Viewport.MSAA_2X, "画质中: MSAA 2X")
			_main._set_quality("high")
			_check(_main.get_viewport().msaa_3d == Viewport.MSAA_4X, "画质高: MSAA 4X")
			_main._set_quality("low")
			# 开局（普通难度+低画质）验证关卡侧倍率
			_main.start_game()
			_main._advance_dialog()
			_check(is_equal_approx(_main.current_level._enemy_dt_scale, 1.0), "关卡难度 dt 倍率 1.0")
			_check(is_equal_approx(_main.current_level._grass_scale, 0.45), "画质低: 草量倍率 0.45")
			_check(_main.current_level._sun.shadow_enabled == false, "画质低: 关卡阴影关")
			_main._set_quality("high")
			# ---- Boss 血条 ----
			_main.player.barrier = 9999.0
			_main.player.global_position = Vector3(0, 0, 26.0 - (_main.current_level.length - 5.0))
			_wait(45)
		1:
			_check(_main.current_level.boss_activated, "Boss 已激活")
			_check(_main._boss_bar.visible, "Boss 血条显示")
			_check(_main._lbl_boss.text == String(Data.BOSSES["defenseWall"]["name"]), "血条只报名字 (%s)" % _main._lbl_boss.text)
			_check(not _main._lbl_boss.text.contains("弱点") and not _main._lbl_obj.text.contains("弱点"), "无弱点文字")
			_w0 = _main._boss_fill.size.x
			for p in _main.current_level.boss.targets:
				if p.part_name == "turret":
					p.on_hit(200)

			_wait(6)
		2:
			_check(_main._boss_fill.size.x < _w0, "血条随伤害缩短 (%.0f→%.0f)" % [_w0, _main._boss_fill.size.x])
			# ---- 飘分 + 连杀 + 图鉴遭遇 ----
			var lv = _main.current_level
			lv._spawn_enemy("rifleman", 2.0, _main.player.global_position.z + 5.0)
			var e = lv.enemies[lv.enemies.size() - 1]
			e.on_hit(999, e.global_position + Vector3(0, 1.2, 0))
			_wait(8)
		3:
			_check(_main._combo == 1, "连杀计数 1 (实 %d)" % _main._combo)
			var saw_float := false
			for f in _main._floats:
				if (f["label"] as Label).visible and (f["label"] as Label).text == "+100":
					saw_float = true
			_check(saw_float, "击杀飘分 +100 可见")
			_check(_main.encountered.has("rifleman"), "图鉴遭遇已登记 rifleman")
			_wait(200) # 连杀窗口 3 秒（60fps×3=180 帧）后应清零
		4:
			_check(_main._combo == 0, "连杀断档清零 (实 %d)" % _main._combo)
			# ---- 评级公式 ----
			_main.lives_inf = false
			_main.lives = 5
			_main._level_time = 60.0
			_main._level_start_score = 0
			_main.score = 5000
			_check(_main._compute_rating() == "S", "评级公式: 快+满命+高分 = S (实 %s)" % _main._compute_rating())
			_main.lives = 0
			_main._level_time = 400.0
			_main.score = 100
			_check(_main._compute_rating() == "C", "评级公式: 慢+零命+低分 = C (实 %s)" % _main._compute_rating())
			# ---- 打通 Boss 走正式结算：记录通关/解锁/评级并进入下一关 ----
			_main.lives = 3
			_main._level_time = 30.0
			for p in _main.current_level.boss.targets:
				if p.part_name == "turret":
					p.on_hit(99999)
			for p in _main.current_level.boss.targets:
				if p.part_name == "core":
					p.on_hit(99999)
			_wait(280)
		5:
			_check(_main.cleared_levels.has(0), "通关已存档")
			_check(_main.unlocked_max >= 1, "下一关已解锁 (unlocked=%d)" % _main.unlocked_max)
			_check(_main.level_ratings.has(0), "评级已存档 (%s)" % String(_main.level_ratings.get(0, "")))
			_check(_main.level_index == 1, "已进入第 2 关")
			# ---- 选关直达 ----
			_main.show_menu()
			_main._start_from_level(1)
			_check(_main.level_index == 1 and _main.state == "dialog", "选关直达第 2 关")
			# ---- 图鉴 ----
			_main.show_menu()
			_main._show_codex()
			_check(_main.codex_panel.visible, "图鉴面板打开")
			_check(_main._codex_list.get_child_count() == Data.BESTIARY.size(), "图鉴条目数 = 名册数 (%d)" % _main._codex_list.get_child_count())
			var lit := false
			var grey := false
			var weak := false
			for row in _main._codex_list.get_children():
				var tx := (row as Label).text
				if tx.contains("Ledder"):
					lit = true
				if tx.contains("？？？"):
					grey = true
				if tx.contains("弱点"):
					weak = true
			_check(lit, "已遭遇 rifleman 条目点亮")
			_check(grey, "未遭遇条目置灰（？？？）")
			_check(not weak, "图鉴无弱点文字")
			# ---- 边缘箭头：转身背对推进方向时应出现，回正后应消失 ----
			_main.start_game()
			_main._advance_dialog()
			_main._yaw = 0.0 # 默认 PI 朝关卡内；转到 0 = 背对推进方向
			_wait(30)
		6:
			_check(_main._edge_arrow.visible, "背对目标时边缘箭头显示")
			var vp := _main.get_viewport().get_visible_rect().size
			var ap: Vector2 = _main._edge_arrow.position
			_check(ap.x >= -4.0 and ap.x <= vp.x and ap.y >= -4.0 and ap.y <= vp.y, "箭头钳在屏幕边缘内 (%s)" % str(ap))
			_main._yaw = PI
			_wait(30)
		7:
			_check(not _main._edge_arrow.visible, "正对目标（屏内）时箭头隐藏")
			# ---- 环境音 ----
			_check(_main._amb.playing, "环境音播放中")
			_check(_main._amb.stream != null and _main._amb.stream.resource_path.ends_with("amb_jungle.wav"), "第1关环境音=丛林 (%s)" % (_main._amb.stream.resource_path if _main._amb.stream else "null"))
			_check(_main._amb.volume_db <= -18.0, "环境音音量压在 BGM 之下 (%.0f dB)" % _main._amb.volume_db)
			_main._load_level(4)
			_check(_main._amb.stream != null and _main._amb.stream.resource_path.ends_with("amb_snow.wav"), "第5关环境音=雪原")
			_main._load_level(1)
			_check(_main._amb.stream != null and _main._amb.stream.resource_path.ends_with("amb_base.wav"), "第2关环境音=基地")
			# ---- 弹丸对象池：三轮齐射后子节点数应恒定（复用而非新建） ----
			var ps = _main.projectiles
			var w := {"color": Color(1, 0.9, 0.4), "bullet_speed": 60.0, "damage": 34, "pierce": false}
			var counts: Array = []
			for r in 3:
				for i in 24:
					ps.spawn_player_bullet(Vector3(0, 1.5, -10), Vector3(0, 0, -1), w)
					ps.spawn_orb(Vector3(0, 1.5, -10), Vector3(0, 0, -1), 12.0, 1)
				for k in 400: # 光弹寿命 6 秒=360 帧，必须推进到全部寿终
					ps.update_projectiles(1.0 / 60.0, {"targets": [], "colliders": [], "player": null, "on_player_hit": func(c): pass, "terrain_h": Callable()})
				counts.append(ps.get_child_count())
			_check(counts[1] == counts[2], "对象池热身后节点数恒定 (%s)" % str(counts))
			_check(ps._free_bullets.size() >= 24 and ps._free_orbs.size() >= 24, "空闲池已蓄水 (弹 %d / 光弹 %d)" % [ps._free_bullets.size(), ps._free_orbs.size()])
			_check(ps._bullets.is_empty() and ps._orbs.is_empty(), "弹丸寿命结束后活弹清空")
			# ---- 环境互动：油桶爆炸 + 连锁 + 范围杀伤（当前已在第 2 关基地） ----
			var blv = _main.current_level
			_check(blv.barrels.size() >= 2, "基地关油桶已登记 (%d)" % blv.barrels.size())
			_bt1 = blv.barrels[0]
			_bt2 = blv.barrels[1]
			_bt2.pos = _bt1.pos + Vector3(2.0, 0, 0) # 测试摆位：把第二桶挪到连锁半径内
			_bt2.hit_x = _bt2.pos.x
			_bt2.hit_y = _bt2.pos.y
			_bt2.hit_z = _bt2.pos.z
			blv._spawn_enemy("rifleman", _bt1.pos.x + 2.5, _bt1.pos.z)
			_victim = blv.enemies[blv.enemies.size() - 1]
			_main._advance_dialog()
			_bt1.on_hit(999)
			_wait(25)
		8:
			_check(not _bt1.alive and not _bt2.alive, "油桶爆炸+0.12s 连锁引爆")
			_check(not _victim.alive, "爆炸范围杀伤敌人")
			_check(bool(_bt1.col.get("disabled", false)), "爆后油桶碰撞失效")
			# ---- 树冠落叶 + 草让开（回第 1 关丛林） ----
			_main._load_level(0)
			_main._advance_dialog()
			var jlv = _main.current_level
			_check(jlv._tree_targets.size() > 0, "树冠目标已登记 (%d)" % jlv._tree_targets.size())
			jlv._tree_targets[0].on_hit(10)
			_check(jlv._leaf_fx.size() == 1, "树冠中弹触发落叶")
			_gx = jlv._grass_base[0].origin
			_main.player.global_position = Vector3(_gx.x, jlv.get_support_y(_gx.x, _gx.z, 999.0), _gx.z)
			_wait(20)
		9:
			var jlv2 = _main.current_level
			_check(jlv2._grass_bent.size() > 0, "穿草草株让开 (%d 株)" % jlv2._grass_bent.size())
			_main.player.global_position = Vector3(_gx.x + 80.0, jlv2.get_support_y(_gx.x + 80.0, _gx.z + 80.0, 999.0), _gx.z + 80.0)
			_wait(20)
		10:
			_check(_main.current_level._grass_bent.is_empty(), "离开后草株恢复")
			# ---- 雪地脚印（第 5 关）：先等脚印跟踪器以出生点建档，再位移 ----
			_main._load_level(4)
			_main._advance_dialog()
			_wait(6)
		11:
			_main.player.global_position += Vector3(2.0, 0, 0)
			_wait(6)
		12:
			_check(_main.current_level._footprints.size() >= 1, "雪地脚印留印 (%d)" % _main.current_level._footprints.size())
			print("FEAT RESULT: %d passed, %d failed" % [_pass, _fail])
			quit(1 if _fail > 0 else 0)
