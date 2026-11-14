extends SceneTree

## 1.2.1 性能剖析探针：L1/L5 同口径基线 + 微基准（has_los/get_support_y/_collider_at/
## _point_blocked/草弯曲 单次成本）+ 敌人普查（警觉/休眠/距离分布）。
## 帧采样口径与 test/long_perf.gd 一致（传送中段引战、北行+周期开火、process_frame 墙钟差）。
## 运行：godot --headless --path . --script res://test/perf121_probe.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := "boot"
var _level = null
var _player = null
var _lvl_idx := 0
var _sample_frames := 0
var _sample_ms := 0
var _max_frame_ms := 0
var _last_tick := 0
var _sample_target := 600
var _t0 := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

func _us_per_call(f: Callable, reps: int) -> float:
	# 预热一轮再计时，避免首次调用的懒加载污染
	f.call()
	var t0 := Time.get_ticks_usec()
	for i in reps:
		f.call()
	return float(Time.get_ticks_usec() - t0) / float(reps)

func _bench() -> void:
	var pp: Vector3 = _player.global_position
	var chest := Vector3(pp.x, _player.chest_y(), pp.z)
	# 敌人普查：警觉数 / 距离分布
	var n_alert := 0
	var n_near := 0 # <=40m（LOS 相关域）
	var n_mid := 0 # 40~110m
	var n_far := 0 # >110m（休眠步进域）
	var pairs: Array = []
	for e in _level.enemies:
		if not is_instance_valid(e):
			continue
		if bool(e.get("_alert")):
			n_alert += 1
		var d: float = e.global_position.distance_to(pp)
		if d <= 40.0:
			n_near += 1
		elif d <= 110.0:
			n_mid += 1
		else:
			n_far += 1
		if pairs.size() < 60:
			pairs.append([e.global_position + Vector3(0, 1.45, 0), chest])
	print("P121 CENSUS lvl=%d enemies=%d alert=%d near40=%d mid110=%d far=%d colliders=%d nodes=%d" % [
		_lvl_idx, _level.enemies.size(), n_alert, n_near, n_mid, n_far, _level.colliders.size(), _count_nodes(_level)])
	# has_los：固定 60 组（敌眼→玩家胸口）循环调用，距离分布即上
	var los_reps := 30
	var los_us := _us_per_call(func():
		for pr in pairs:
			_level.has_los(pr[0], pr[1])
	, los_reps) / float(maxi(1, pairs.size()))
	print("P121 BENCH has_los us/call=%.1f (pairs=%d)" % [los_us, pairs.size()])
	# get_support_y：玩家周边 24m 内撒点
	var pts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 48:
		pts.append(Vector2(pp.x + rng.randf_range(-24.0, 24.0), pp.z + rng.randf_range(-24.0, 24.0)))
	var sup_us := _us_per_call(func():
		for p in pts:
			_level.get_support_y(p.x, p.y, 999.0)
	, 60) / float(pts.size())
	print("P121 BENCH get_support_y us/call=%.1f" % sup_us)
	# _collider_at（子弹掩体判定）：玩家周边点
	var proj = _main.projectiles
	var col_us := _us_per_call(func():
		for p in pts:
			proj._collider_at(Vector3(p.x, pp.y + 1.0, p.y), _level.colliders)
	, 60) / float(pts.size())
	print("P121 BENCH collider_at us/call=%.1f" % col_us)
	# _collider_at 候选版（1.2.1 实装路径）：空间索引候选集 + 插入序取首
	var colc_us := _us_per_call(func():
		for p in pts:
			proj._collider_at_c(Vector3(p.x, pp.y + 1.0, p.y), _level.colliders_at(p.x, p.y))
	, 60) / float(pts.size())
	print("P121 BENCH collider_at_c us/call=%.1f" % colc_us)
	# 动态光 A/B（计数口径）：爆炸点光点亮数与枪口光能量/范围——GPU 光照成本无头测不了，只报机制计数
	proj.set_fx_options(true, 0.5)
	proj.spawn_explosion_fx(pp + Vector3(0, 1.0, -3.0), 1.7)
	proj.spawn_explosion_fx(pp + Vector3(2.0, 1.0, -3.0), 1.7)
	var lit_on := 0
	for l in proj._lights:
		if l.light_energy > 0.0:
			lit_on += 1
	proj.set_fx_options(false, 0.5)
	var muzzle_range_off: float = proj._muzzle_light.omni_range if proj._muzzle_light else -1.0
	proj.spawn_explosion_fx(pp + Vector3(-2.0, 1.0, -3.0), 1.7)
	var lit_off := 0
	for l in proj._lights:
		if l.light_energy > 0.0:
			lit_off += 1
	proj.spawn_muzzle_flash(pp + Vector3(0, 1.4, -1.0), Vector3(0, 0, -1), 1.0, true)
	var muzzle_off: float = proj._muzzle_light.light_energy if proj._muzzle_light else -1.0
	proj.set_fx_options(true, 0.5)
	proj.spawn_muzzle_flash(pp + Vector3(0, 1.4, -1.0), Vector3(0, 0, -1), 1.0, true)
	var muzzle_on: float = proj._muzzle_light.light_energy if proj._muzzle_light else -1.0
	print("P121 LIGHTS expl_lit on=%d off=%d muzzle_energy on=%.1f off=%.1f muzzle_range_off=%.1f" % [lit_on, lit_off, muzzle_on, muzzle_off, muzzle_range_off])
	proj.set_fx_options(bool(_main.opt_dynlight), float(_main._particle_factor())) # 恢复玩家设置再采样
	# _point_blocked（战术移动）：借第一个敌人
	if _level.enemies.size() > 0:
		var e0 = _level.enemies[0]
		var pb_us := _us_per_call(func():
			for p in pts:
				e0._point_blocked(p.x, p.y, pp.y)
		, 60) / float(pts.size())
		print("P121 BENCH point_blocked us/call=%.1f" % pb_us)
	# 草弯曲：整表扫描一次的成本
	if _level._grass_mm != null:
		var gb_us := _us_per_call(func(): _level._update_grass_bend(pp), 15)
		print("P121 BENCH grass_bend us/call=%.1f (grass=%d)" % [gb_us, _level._grass_base.size()])
	# 渲染口径（无头 dummy 驱动下多半为 0，如实记录）
	print("P121 RENDER draw_calls=%d prims=%d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])

func _begin_level(idx: int) -> void:
	_lvl_idx = idx
	_main._load_level(idx)
	_phase = "waitbuild"
	_t0 = Time.get_ticks_msec()

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_begin_level(0)
			return
		"waitbuild":
			if _main.state == "dialog":
				var build_ms := Time.get_ticks_msec() - _t0
				_main._advance_dialog()
				_level = _main.current_level
				_player = _main.player
				_player.barrier = 99999.0
				print("P121 BUILD lvl=%d build_ms=%d" % [_lvl_idx, build_ms])
				# 传送到关卡中段开阔处（L1 长 500 取 -200；L5 长 840 取 -380，与 long_perf 同点）
				var tz := -200.0 if _lvl_idx == 0 else -380.0
				var y: float = _level.get_support_y(0.0, tz, 999.0)
				_player.global_position = Vector3(0.0, y, tz)
				_player.vy = 0.0
				_player.grounded = true
				_bench()
				_sample_frames = 0
				_sample_ms = 0
				_max_frame_ms = 0
				_sample_target = 600 if _lvl_idx == 0 else 900
				_phase = "sample"
				_last_tick = Time.get_ticks_msec()
			return
		"sample":
			var now := Time.get_ticks_msec()
			var dtm := now - _last_tick
			_last_tick = now
			if _sample_frames > 0:
				_sample_ms += dtm
				_max_frame_ms = maxi(_max_frame_ms, dtm)
			_sample_frames += 1
			_main._yaw = PI
			Input.action_press("move_forward")
			if _sample_frames % 30 < 18:
				Input.action_press("shoot")
			else:
				Input.action_release("shoot")
			if _sample_frames >= _sample_target:
				Input.action_release("move_forward")
				Input.action_release("shoot")
				var avg := float(_sample_ms) / float(maxi(1, _sample_frames - 1))
				var alerted := 0
				for e in _level.enemies:
					if is_instance_valid(e) and e.get("_alert") == true:
						alerted += 1
				print("P121 SAMPLE lvl=%d frames=%d avg_frame_ms=%.2f max_frame_ms=%d alerted_end=%d player_z=%.0f" % [
					_lvl_idx, _sample_frames, avg, _max_frame_ms, alerted, _player.global_position.z])
				if _lvl_idx == 0:
					_begin_level(4)
				else:
					print("P121 DONE")
					quit(0)
			return
