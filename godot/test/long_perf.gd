extends SceneTree

## 第二线 L5（840m 最长关）性能专项：建关耗时 + 实走帧处理耗时抽样
## 口径说明：headless dummy 渲染下测的是脚本+物理的帧处理成本（非 GPU 帧率），如实标注
## 1.1.0 适配：_load_level 改为异步分阶段协程，build_ms 口径=从发起加载到 dialog 落地（生成
## 全程，含逐阶段让帧）——即玩家真实等待时长；阶段内部的逐帧拆分使墙钟略高于旧同步口径。
## 运行：godot --headless --path . --script res://test/long_perf.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := "boot"
var _level = null
var _player = null
var _build_ms := 0
var _build_t0 := 0
var _sample_frames := 0
var _sample_ms := 0
var _max_frame_ms := 0
var _last_tick := 0
var _alerted := 0

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

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 3:
				_main._set_lives("inf")
				_main.start_game()
				_build_t0 = Time.get_ticks_msec()
				_main._load_level(4)
				_phase = "waitbuild"
			return
		"waitbuild":
			# 异步生成中：等 dialog 落地（=玩家视角的加载完成）再结算 build_ms
			if _main.state == "dialog":
				_build_ms = Time.get_ticks_msec() - _build_t0
				_main._advance_dialog()
				_level = _main.current_level
				_player = _main.player
				_player.barrier = 99999.0
				print("PERF L5 build_ms=%d enemies=%d colliders=%d level_nodes=%d" % [
					_build_ms, _level.enemies.size(), _level.colliders.size(), _count_nodes(_level)])
				# 传送到中段营地附近引战，抽样战斗中帧成本
				var y: float = _level.get_support_y(0.0, -380.0, 999.0)
				_player.global_position = Vector3(0.0, y, -380.0)
				_player.vy = 0.0
				_player.grounded = true
				_phase = "sample"
				_last_tick = Time.get_ticks_msec()
			return
		"sample":
			var now := Time.get_ticks_msec()
			var dt := now - _last_tick
			_last_tick = now
			if _sample_frames > 0:
				_sample_ms += dt
				_max_frame_ms = maxi(_max_frame_ms, dt)
			_sample_frames += 1
			# 向北缓行 + 周期开火，模拟实战负载（敌人激活/弹丸/粒子）
			_main._yaw = PI
			Input.action_press("move_forward")
			if _sample_frames % 30 < 18:
				Input.action_press("shoot")
			else:
				Input.action_release("shoot")
			_alerted = 0
			for e in _level.enemies:
				if is_instance_valid(e) and e.get("_alert") == true:
					_alerted += 1
			if _sample_frames >= 900:
				Input.action_release("move_forward")
				Input.action_release("shoot")
				var avg := float(_sample_ms) / float(maxi(1, _sample_frames - 1))
				print("PERF L5 sample_frames=%d avg_frame_ms=%.2f max_frame_ms=%d alerted=%d player_z=%.0f" % [
					_sample_frames, avg, _max_frame_ms, _alerted, _player.global_position.z])
				print("PERF RESULT: build=%dms avg_frame=%.2fms (headless 脚本+物理口径)" % [_build_ms, avg])
				quit(0)
			return
