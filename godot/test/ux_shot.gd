extends SceneTree

## 1.1.0 体验项截图（xvfb）：
## ① ux_loading.png —— 单独调 _show_loading 呈现「第5关: 雪原」加载界面（静止呈现、
##    stage 0「正在生成地形」+ 进度 0%，守住 _load_layer 后截取）：生成是异步协程、
##    xvfb 软件渲染下过场不可控，活抓必与上一关剧情/HUD 残帧串扰或过冲到 100%（已两度实证），
##    故分离呈现；真实生成全程的时序/进度递增证据由 ux_probe 给出（shown<gen_start<gen_end、max_fill 352→440）；
## ② ux_click_hint.png —— 进关 playing、指针未锁定时的点击引导。
## 运行：xvfb-run godot --path . --script res://test/ux_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0
var _wait := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(snap_name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + snap_name)
	print("SNAP ", snap_name)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0: # 等菜单稳住 → 单独呈现 L5 加载界面
			if _frame > 20:
				_main._show_loading(4) # 第5关: 雪原
				_main._load_stage_lbl.text = "正在生成地形…"
				_phase = 1
				_wait = _frame + 2 # 布局+绘制两帧后截
		1:
			if _frame >= _wait:
				_snap("ux_loading.png")
				_main.load_layer.visible = false # 撤下单呈现的加载层，再正常进关截图
				_main.start_game(5) # 第6关：黄昏谷地，进关截引导
				_phase = 2
			elif _frame > 200:
				print("UXSHOT FAIL 呈现超时")
				quit(1)
		2: # 等异步生成走完到 dialog
			if _main.state == "dialog":
				_main._advance_dialog()
				_main._hint_ever_captured = false # 模拟网页版锁定未生效
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_phase = 3
				_wait = _frame + 30 # 等引导淡入+脉冲到高位
			elif _frame > 6000:
				print("UXSHOT FAIL 等 dialog 超时")
				quit(1)
		3:
			if _frame >= _wait:
				_snap("ux_click_hint.png")
				print("hint active=", _main._hint_active, " alpha=", _main._hint_alpha,
					" text=", _main._hint_label.text)
				print("UXSHOT DONE")
				quit()
