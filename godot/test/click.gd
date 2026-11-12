extends SceneTree

## 真实点击模拟测试：用视口 push_input 走完整 GUI 拾取链点「开始游戏」，
## 验证 state 离开 menu。专防全屏容器拦截点击这类问题（冒烟是直调函数、测不出来）。
## 运行：xvfb-run godot --path . --script res://test/click.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := 0
var _btn: Button

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _find_button(n: Node) -> Button:
	if n is Button and n.text == "开始游戏":
		return n
	for c in n.get_children():
		var r := _find_button(c)
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

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 30:
				_btn = _find_button(_main)
				if _btn == null:
					print("CLICKTEST FAIL: start button not found")
					quit(1)
					return
				var rect := _btn.get_global_rect()
				print("CLICKTEST button rect: ", rect, " state: ", _main.state)
				var motion := InputEventMouseMotion.new()
				motion.position = rect.get_center()
				motion.global_position = rect.get_center()
				root.push_input(motion)
				_click(rect.get_center(), true)
				_phase = 1
		1:
			if _frame > 36:
				_click(_btn.get_global_rect().get_center(), false)
				_phase = 2
		2:
			if _frame > 50:
				if _main.state != "menu":
					print("CLICKTEST PASS: click started game, state=", _main.state)
					quit(0)
				else:
					print("CLICKTEST FAIL: still in menu after click (input blocked)")
					quit(1)
