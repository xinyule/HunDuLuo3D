extends SceneTree

## 触控层真用户路径测试（1.2.1）：真实 InputEventScreenTouch/Drag 经视口 push_input
## 走完整 GUI 拾取链驱动 JoyStick/IconButton，断言 main 的 _touch_move/_touch_shoot/
## _touch_prone 正确、跳跃信号到达、右侧拖屏仍转镜头，并核对控件几何（尺寸/边距）。
## 运行：xvfb-run godot --path . --script res://test/touch_probe.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := 0
var _phase_frame := 0
var _passed := 0
var _failed := 0
var _start_btn: Button
var _joy: Control
var _btns := {} # kind -> IconButton
var _jump_hits := 0
var _yaw0 := 0.0
var _joy_center := Vector2.ZERO

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
		print("  ok: ", name)
	else:
		_failed += 1
		print("  FAIL: ", name)

func _find_button(n: Node, text: String) -> Button:
	if n is Button and n.text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null

func _click(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	root.push_input(ev)

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	root.push_input(ev)

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	ev.relative = rel
	root.push_input(ev)

func _next() -> void:
	_phase += 1
	_phase_frame = _frame

func _btn_center(kind: String) -> Vector2:
	return (_btns[kind] as Control).get_global_rect().get_center()

func _on_frame() -> void:
	_frame += 1
	var waited := _frame - _phase_frame
	match _phase:
		0: # 点「开始游戏」
			if _frame > 30:
				_start_btn = _find_button(_main, "开始游戏")
				if _start_btn == null:
					_check(false, "开始游戏按钮存在")
					_done()
					return
				_click(_start_btn.get_global_rect().get_center(), true)
				_next()
		1:
			if waited > 6:
				_click(_start_btn.get_global_rect().get_center(), false)
				_next()
		2: # 等开场对白（点开始后先到 dialog）
			if _main.state == "dialog":
				_touch(9, Vector2(640, 360), true)
				_next()
			elif _frame > 4000:
				_check(false, "进入对白态（实际 state=%s）" % _main.state)
				_done()
		3:
			if waited > 4:
				_touch(9, Vector2(640, 360), false)
				_next()
		4: # 等 playing
			if _main.state == "playing":
				_main.touch_ui.visible = true
				_joy = _main._touch_joy
				for ch in _main.touch_ui.get_children():
					if ch is IconButton:
						_btns[ch.kind] = ch
				_next()
			elif _frame > 9000:
				_check(false, "进入 playing（实际 state=%s）" % _main.state)
				_done()
		5: # 几何核对
			if waited > 3:
				var jr := _joy.get_global_rect()
				_check(jr.size.x >= 150.0 and jr.size.y >= 150.0, "摇杆真实尺寸≥150（实际 %s）" % jr.size)
				_check(jr.position.x >= 48.0, "摇杆左边距≥48（实际 %.0f）" % jr.position.x)
				_check(720.0 - jr.end.y >= 48.0, "摇杆下边距≥48（实际 %.0f）" % (720.0 - jr.end.y))
				_check(_btns.has("fire") and _btns.has("jump") and _btns.has("prone"), "三图标钮齐全")
				for kind in ["fire", "jump", "prone"]:
					var br := (_btns[kind] as Control).get_global_rect()
					_check(1280.0 - br.end.x >= 48.0, "%s 右边距≥48（实际 %.0f）" % [kind, 1280.0 - br.end.x])
					_check(720.0 - br.end.y >= 48.0, "%s 下边距≥48（实际 %.0f）" % [kind, 720.0 - br.end.y])
				_check((_btns["fire"] as Control).get_global_rect().size.x >= 90.0, "射击钮加大≥90")
				(_btns["jump"] as IconButton).button_down.connect(func(): _jump_hits += 1)
				_joy_center = jr.get_center()
				_touch(0, _joy_center, true)
				_next()
		6: # 摇杆向右拖满
			if waited == 2:
				_drag(0, _joy_center + Vector2(46, 0), Vector2(46, 0))
			elif waited > 5:
				_check(_main._touch_move.x > 0.8, "摇杆右拖 _touch_move.x>0.8（实际 %s）" % _main._touch_move)
				_check(absf(_main._touch_move.y) < 0.35, "摇杆右拖 y 近零")
				_next()
		7: # 摇杆向上拖满
			if waited == 2:
				_drag(0, _joy_center + Vector2(0, -46), Vector2(-46, -46))
			elif waited > 5:
				_check(_main._touch_move.y < -0.8, "摇杆上拖 _touch_move.y<-0.8（实际 %s）" % _main._touch_move)
				_touch(0, _joy_center + Vector2(0, -46), false)
				_next()
		8: # 松手回零
			if waited > 4:
				_check(_main._touch_move.length() < 0.01, "松手 _touch_move 归零（实际 %s）" % _main._touch_move)
				_touch(1, _btn_center("fire"), true)
				_next()
		9: # 射击按下/抬起
			if waited > 4:
				_check(_main._touch_shoot == true, "射击按下 _touch_shoot=true")
				_touch(1, _btn_center("fire"), false)
				_next()
		10:
			if waited > 4:
				_check(_main._touch_shoot == false, "射击抬起 _touch_shoot=false")
				_touch(2, _btn_center("jump"), true)
				_next()
		11: # 跳跃（_touch_jump 每帧被快照消费，用信号计数断言）
			if waited > 4:
				_check(_jump_hits >= 1, "跳跃钮 button_down 到达（计数 %d）" % _jump_hits)
				_touch(2, _btn_center("jump"), false)
				_touch(3, _btn_center("prone"), true)
				_next()
		12: # 趴下开关
			if waited > 4:
				_check(_main._touch_prone == true, "趴下按下 _touch_prone=true")
				_touch(3, _btn_center("prone"), false)
				_next()
		13:
			if waited == 2:
				_touch(3, _btn_center("prone"), true)
			elif waited > 5:
				_check(_main._touch_prone == false, "趴下再按 _touch_prone=false")
				_touch(3, _btn_center("prone"), false)
				_yaw0 = _main._yaw
				_touch(4, Vector2(900, 300), true)
				_next()
		14: # 右侧拖屏转镜头（摇杆空闲、异指拖动）
			if waited == 2:
				_drag(4, Vector2(840, 300), Vector2(-60, 0))
			elif waited > 5:
				_check(absf(_main._yaw - _yaw0) > 0.1, "右侧拖屏改变 _yaw（Δ=%.3f）" % (_main._yaw - _yaw0))
				_touch(4, Vector2(840, 300), false)
				_done()

func _done() -> void:
	print("TOUCH RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
