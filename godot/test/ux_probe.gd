extends SceneTree

## 1.1.0 体验项专项探针（headless）：
## ① 加载时序实证——加载界面上屏帧 < 生成开始帧 < 生成结束帧，且生成期间加载层可见、进度推进；
## ② 点击引导——游玩中未锁定指针时亮起（开始/继续两文案）、锁定后淡出。
## 运行：xvfb-run godot --path . --script res://test/ux_probe.gd --rendering-driver opengl3 --resolution 1280x720
## （必须真实显示服务器：headless 的 DisplayServer 不保存 mouse_mode、读回恒 VISIBLE，指针锁断言无从测起——微型实验实锤）

var _main: Node
var _frame := 0
var _phase := 0
var _pass := 0
var _fail := 0
var _saw_loading := false
var _saw_layer := false
var _max_fill := 0.0
var _wait := 0

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
	# 全程旁观加载状态（任何阶段都记录）
	if _main.state == "loading":
		_saw_loading = true
		if _main.load_layer.visible:
			_saw_layer = true
		_max_fill = maxf(_max_fill, _main._load_fill.size.x)
	match _phase:
		0:
			if _frame > 10:
				_check(_main.state == "menu", "启动进菜单")
				_main.start_game(4) # 第 5 关（840m 最长关）：生成耗时最久，最适合验加载界面
				_phase = 1
		1:
			if _main.state == "dialog":
				_check(_saw_loading, "进关经过 loading 状态")
				_check(_saw_layer, "生成期间加载界面可见")
				_check(_main._load_frame_shown >= 0 and _main._load_frame_shown < _main._load_frame_gen_start,
					"加载界面先上屏 (shown=%d < gen_start=%d)" % [_main._load_frame_shown, _main._load_frame_gen_start])
				_check(_main._load_frame_gen_start < _main._load_frame_gen_end,
					"生成跨多帧 (gen_start=%d < gen_end=%d)" % [_main._load_frame_gen_start, _main._load_frame_gen_end])
				_check(_max_fill >= 100.0, "生成期间进度条推进过 (max_fill=%.0f)" % _max_fill)
				_check(_main._load_fill.size.x >= 438.0, "生成结束进度 100%% (fill=%.0f)" % _main._load_fill.size.x)
				_check(not _main.load_layer.visible, "生成完毕加载界面撤下")
				_main._advance_dialog()
				_check(_main.state == "playing", "剧情后进入 playing")
				# 模拟网页版情形：剧情点击的锁定没生效（ever 标记手动清零还原该场景）
				_main._hint_ever_captured = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_phase = 2
				_wait = _frame + 25
			elif _frame > 4000:
				_check(false, "等 dialog 超时")
				_finish()
		2:
			if _frame >= _wait:
				_check(_main._hint_active, "未锁定指针时引导亮起")
				_check(_main._click_hint.visible, "引导条可见")
				_check(_main._hint_label.text == "点击画面开始战斗", "首次文案=开始战斗 (%s)" % _main._hint_label.text)
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_phase = 3
				_wait = _frame + 45
		3:
			if _frame >= _wait:
				_check(not _main._hint_active, "锁定后引导熄灭")
				_check(not _main._click_hint.visible, "锁定后引导淡出完毕")
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # 模拟 Esc 释放指针锁
				_phase = 4
				_wait = _frame + 25
		4:
			if _frame >= _wait:
				_check(_main._hint_active, "Esc 释放后引导重显")
				_check(_main._hint_label.text == "点击画面继续战斗", "重显文案=继续战斗 (%s)" % _main._hint_label.text)
				_finish()

func _finish() -> void:
	print("UXPROBE %s pass=%d fail=%d" % ["DONE" if _fail == 0 else "FAILED", _pass, _fail])
	quit(0 if _fail == 0 else 1)
