extends SceneTree

## 画质设置面板真用户路径测试（1.2.1）：真实鼠标点击经 push_input 驱动面板逐项切换，
## 断言引擎侧参数真的变了（viewport scaling_3d_scale / msaa_3d、Engine.max_fps、
## 菜单太阳阴影、弹道系统光效开关与粒子 amount），预设批量套用与「自定义」标记，
## 以及存档持久化往返（改→存→扰动→读→恢复）。结束时还原测试前的存档文件。
## 运行：xvfb-run godot --path . --script res://test/settings_probe.gd --rendering-driver opengl3 --resolution 1280x720

const SAVE_PATH := "user://contra3d_save.cfg"

var _main: Node
var _frame := 0
var _phase := 0
var _phase_frame := 0
var _passed := 0
var _failed := 0
var _had_save := false
var _save_bytes := PackedByteArray()
var _click_target: Control = null

func _initialize() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(SAVE_PATH)
		# 删档起步：出厂默认断言不受历史存档干扰（结束时按快照还原）
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
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

func _press(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	root.push_input(ev)

## 发起一次完整点击（按下→隔帧→抬起），后续阶段在 _click_target==null 后断言
func _click(c: Control) -> void:
	_click_target = c
	var motion := InputEventMouseMotion.new()
	motion.position = c.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion)
	_press(c.get_global_rect().get_center(), true)

func _click_busy() -> bool:
	return _click_target != null

func _on_frame() -> void:
	_frame += 1
	if _click_target != null:
		if _frame - _phase_frame >= 5:
			_press(_click_target.get_global_rect().get_center(), false)
			_click_target = null
			_phase_frame = _frame
		return
	var waited := _frame - _phase_frame
	match _phase:
		0: # 出厂默认断言 + 打开画质设置
			if _frame > 40:
				_check(is_equal_approx(root.scaling_3d_scale, 0.85), "默认渲染缩放 0.85（实际 %s）" % root.scaling_3d_scale)
				_check(root.msaa_3d == 1, "默认 MSAA 2x（实际 %d）" % root.msaa_3d)
				_check(Engine.max_fps == 60, "默认帧率上限 60（实际 %d）" % Engine.max_fps)
				_click(_find_button(_main, "画质设置"))
				_phase = 1
				_phase_frame = _frame
		1:
			if waited > 4 and not _click_busy():
				_check(_main._gfx_panel.visible, "画质设置面板打开")
				_click(_main._scale_btns[0.7])
				_phase = 2
				_phase_frame = _frame
		2: # 渲染缩放单项 → 即时生效 + 自定义
			if waited > 4 and not _click_busy():
				_check(is_equal_approx(root.scaling_3d_scale, 0.7), "点 0.7 后 scaling_3d_scale=0.7（实际 %s）" % root.scaling_3d_scale)
				_check(_main.quality_custom, "单项改动后 quality_custom=true")
				_check((_main._qual_btns["custom"] as Button).button_pressed, "预设行「自定义」点亮")
				_click(_main._scale_btns[0.85])
				_phase = 3
				_phase_frame = _frame
		3:
			if waited > 4 and not _click_busy():
				_check(is_equal_approx(root.scaling_3d_scale, 0.85), "点回 0.85 即时生效")
				_check(not _main.quality_custom, "整组回到中档后自定义自动清除")
				_click(_main._msaa_btns[0])
				_phase = 4
				_phase_frame = _frame
		4: # 抗锯齿关
			if waited > 4 and not _click_busy():
				_check(root.msaa_3d == 0, "抗锯齿关 → msaa_3d=0（实际 %d）" % root.msaa_3d)
				_click(_main._msaa_btns[2])
				_phase = 5
				_phase_frame = _frame
		5: # 抗锯齿 4 倍
			if waited > 4 and not _click_busy():
				_check(root.msaa_3d == 2, "抗锯齿 4倍 → msaa_3d=2（实际 %d）" % root.msaa_3d)
				_click(_main._msaa_btns[1])
				_phase = 6
				_phase_frame = _frame
		6: # 帧率 30
			if waited > 4 and not _click_busy():
				_check(root.msaa_3d == 1, "抗锯齿回 2倍")
				_click(_main._fps_btns[30])
				_phase = 7
				_phase_frame = _frame
		7:
			if waited > 4 and not _click_busy():
				_check(Engine.max_fps == 30, "帧率上限 30 生效（实际 %d）" % Engine.max_fps)
				_click(_main._fps_btns[0])
				_phase = 8
				_phase_frame = _frame
		8: # 帧率不限
			if waited > 4 and not _click_busy():
				_check(Engine.max_fps == 0, "帧率不限 → max_fps=0（实际 %d）" % Engine.max_fps)
				_click(_main._fps_btns[60])
				_phase = 9
				_phase_frame = _frame
		9: # 阴影关 → 菜单太阳
			if waited > 4 and not _click_busy():
				_check(Engine.max_fps == 60, "帧率回 60")
				_click(_main._shadow_btns["off"])
				_phase = 10
				_phase_frame = _frame
		10:
			if waited > 4 and not _click_busy():
				var sun = _main.diorama.get_node_or_null("MenuSun")
				_check(sun != null and not sun.shadow_enabled, "阴影关 → 菜单太阳 shadow_enabled=false")
				_click(_main._shadow_btns["mid"])
				_phase = 11
				_phase_frame = _frame
		11: # 动态光效开
			if waited > 4 and not _click_busy():
				var sun2 = _main.diorama.get_node_or_null("MenuSun")
				_check(sun2 != null and sun2.shadow_enabled, "阴影中 → 菜单太阳恢复")
				_click(_main._dyn_btns[true])
				_phase = 12
				_phase_frame = _frame
		12:
			if waited > 4 and not _click_busy():
				_check(_main.projectiles._fx_lights == true, "动态光效开 → 弹道系统 _fx_lights=true")
				_click(_main._dyn_btns[false])
				_phase = 13
				_phase_frame = _frame
		13: # 粒子高
			if waited > 4 and not _click_busy():
				_check(_main.projectiles._fx_lights == false, "动态光效关 → _fx_lights=false")
				_click(_main._part_btns["high"])
				_phase = 14
				_phase_frame = _frame
		14:
			if waited > 4 and not _click_busy():
				var e1 = _first_emitter()
				_check(e1 != null and e1.amount == int(float(e1.get_meta("base_amount"))), "粒子高 → amount=基数（实际 %s）" % (e1.amount if e1 else -1))
				_click(_main._part_btns["low"])
				_phase = 15
				_phase_frame = _frame
		15: # 粒子低 = 基数×0.25
			if waited > 4 and not _click_busy():
				var e2 = _first_emitter()
				_check(e2 != null and e2.amount == maxi(1, int(round(float(e2.get_meta("base_amount")) * 0.25))), "粒子低 → amount=基数×0.25（实际 %s）" % (e2.amount if e2 else -1))
				_click(_main._part_btns["mid"])
				_phase = 16
				_phase_frame = _frame
		16: # 远敌动画完整
			if waited > 4 and not _click_busy():
				_click(_main._far_btns["full"])
				_phase = 17
				_phase_frame = _frame
		17:
			if waited > 4 and not _click_busy():
				_check(_main.opt_far_anim == "full", "远敌动画完整 opt_far_anim=full")
				_click(_main._far_btns["simple"])
				_phase = 18
				_phase_frame = _frame
		18: # 关面板 → 点预设「高」
			if waited > 4 and not _click_busy():
				_check(_main.opt_far_anim == "simple", "远敌动画回简化")
				_click(_find_button(_main._gfx_panel, "返回"))
				_phase = 19
				_phase_frame = _frame
		19:
			if waited > 4 and not _click_busy():
				_check(not _main._gfx_panel.visible, "画质面板关闭")
				_click(_main._qual_btns["high"])
				_phase = 20
				_phase_frame = _frame
		20: # 预设高整组
			if waited > 4 and not _click_busy():
				_check(_main.opt_scale == 1.0 and _main.opt_msaa == 2 and _main.opt_fps == 0 and _main.opt_shadow == "high" and _main.opt_dynlight and _main.opt_particles == "high" and _main.opt_far_anim == "full", "预设高 = 整组高值")
				_check(not _main.quality_custom and (_main._qual_btns["high"] as Button).button_pressed, "预设高点亮、非自定义")
				_check(is_equal_approx(root.scaling_3d_scale, 1.0) and root.msaa_3d == 2 and Engine.max_fps == 0, "预设高引擎侧同步（缩放1.0/MSAA4x/不限帧）")
				_click(_main._qual_btns["mid"])
				_phase = 21
				_phase_frame = _frame
		21: # 预设中整组 = 出厂默认
			if waited > 4 and not _click_busy():
				_check(_main.opt_scale == 0.85 and _main.opt_msaa == 1 and _main.opt_fps == 60 and _main.opt_shadow == "mid" and not _main.opt_dynlight and _main.opt_particles == "mid" and _main.opt_far_anim == "simple", "预设中 = 出厂默认组")
				# 持久化往返：先造一个自定义态并保存，再扰动内存值，读档应恢复
				_main._set_opt("scale", 1.0)
				_main._save_hi()
				_main.opt_scale = 0.7
				_main.opt_msaa = 0
				_main.opt_fps = 30
				_main.quality_custom = false
				_main._load_hi()
				_check(is_equal_approx(_main.opt_scale, 1.0) and _main.opt_msaa == 1 and _main.opt_fps == 60 and _main.quality_custom, "存档往返恢复（scale/msaa/fps/自定义）")
				_restore_save()
				_done()

func _first_emitter() -> GPUParticles3D:
	for ch in _main.projectiles.get_children():
		if ch is GPUParticles3D and ch.has_meta("base_amount"):
			return ch
	return null

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_bytes)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _done() -> void:
	print("SETTINGS RESULT: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
