extends Node3D

## 主引擎 —— 状态机是唯一有权改 state 的地方
## 状态：menu / dialog / playing / levelclear / gameover / victory
## 输入动作运行时注册；UI 全部代码构建（军事玻璃风）

var state := "menu"
var level_index := 0
var score := 0
var lives = 3 # int 或 INF
var lives_choice = 3
var continues_left := 3
var hi_score := 0
var char_id := "bill"

var camera: Camera3D
var world_env: WorldEnvironment
var rig: CameraRig
var projectiles: ProjectileSystem
var player: Player
var current_level: Level
var checkpoint := Vector3(0, 0, 26)
var soldier_scene: PackedScene

var _yaw := PI
var _pitch := 0.0
var _next_extend := 10000
var _dialog_cb: Callable
var _konami: Array = []
var _menu_player: Player
var _menu_time := 0.0

# UI
var ui: CanvasLayer
var menu_panel: PanelContainer
var controls_panel: PanelContainer
var hud: Control
var gameover_panel: PanelContainer
var victory_panel: PanelContainer
var _lbl_score: Label
var _lbl_level: Label
var _lbl_progress: Label
var _prog_fill: ColorRect
var _boss_bar: Control
var _boss_fill: ColorRect
var _lbl_boss: Label
var _cells: Array[ColorRect] = []
var _lbl_lives: Label
var _lbl_weapon: Label
var _lbl_center: Label
var _dialog_panel: PanelContainer
var _lbl_dialog: Label
var _lbl_hi: Label
var _lbl_over_text: Label
var _btn_continue: Button
var _lbl_final: Label
var _char_btns: Dictionary = {}
var _lives_btns: Dictionary = {}
# 触屏
var touch_ui: Control
var _touch_move := Vector2.ZERO
var _touch_shoot := false
var _touch_prone := false
var _touch_jump := false
var _joy_center := Vector2.ZERO
var _joy_id := -1

const KONAMI := ["ui_up", "ui_up", "ui_down", "ui_down", "ui_left", "ui_right", "ui_left", "ui_right", "key_b", "key_a"]

func _ready() -> void:
	_register_input()
	soldier_scene = load("res://assets/char/ual.glb")
	camera = Camera3D.new()
	add_child(camera)
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.1
	env.glow_bloom = 0.12
	env.background_mode = Environment.BG_SKY
	world_env.environment = env
	add_child(world_env)
	rig = CameraRig.new(camera)
	projectiles = ProjectileSystem.new()
	add_child(projectiles)
	_load_hi()
	_build_ui()
	_build_menu_diorama()
	_update_hi_label()

func _register_input() -> void:
	var defs := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"jump": [KEY_SPACE], "prone": [KEY_C, KEY_CTRL], "run": [KEY_SHIFT],
		"key_b": [KEY_B], "key_a": [KEY_A],
	}
	for action in defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in ["shoot", "aim"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("shoot", mb)
	var mb2 := InputEventMouseButton.new()
	mb2.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("aim", mb2)
	# ui_up 等方向键动作（秘籍用）——Godot 内置 ui_* 已存在则复用
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = {"ui_up": KEY_UP, "ui_down": KEY_DOWN, "ui_left": KEY_LEFT, "ui_right": KEY_RIGHT}[a]
			InputMap.action_add_event(a, ev)

# ---------------- 菜单布景 ----------------
func _build_menu_diorama() -> void:
	diorama = Node3D.new()
	diorama.name = "Diorama"
	add_child(diorama)
	var env := world_env.environment
	var sky_res := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/forest.hdr")
	sky_res.sky_material = pm
	env.sky = sky_res
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.16, 0.1)
	env.fog_density = 0.012
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.name = "MenuSun"
	diorama.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(220, 220)
	ground.mesh = plane
	ground.material_override = Util.pbr(Color(0.55, 0.62, 0.42), "jungle", 0.95, 0.0, Vector2(30, 30))
	ground.position = Vector3(0, -0.02, -10)
	diorama.add_child(ground)
	var rand := Util.seeded(42)
	for i in 26:
		var x := rand.randf_range(-55, 55)
		var z := rand.randf_range(-70, 18)
		if absf(x) < 5.0 and z > -6.0:
			continue
		Util.cyl(diorama, 0.2, 0.32, 3.0, Util.pbr(Color(1, 1, 1), "bark", 0.95, 0.0, Vector2(1, 2)), Vector3(x, 1.5, z), 7)
		var can_mat := StandardMaterial3D.new()
		can_mat.albedo_texture = load("res://assets/tex/foliage_cluster.png")
		can_mat.roughness = 1.0
		for off in [Vector3(0, 4.6, 0), Vector3(0.8, 4.0, 0.3), Vector3(-0.7, 4.1, -0.3)]:
			var can := Util.sph(diorama, 1.45, can_mat, Vector3(x, 0, z) + off, 12, 9)
			can.scale = Vector3(1.15, 0.85, 1.15)
	_menu_player = Player.new()
	diorama.add_child(_menu_player)
	_menu_player.setup(char_id)
	_menu_player.global_position = Vector3(0, 0, 14)
	_menu_player.facing = PI * 0.92
	camera.global_position = Vector3(3.4, 2.1, 20.5)
	camera.look_at(Vector3(0, 1.4, 14), Vector3.UP)

# ---------------- UI 构建 ----------------
func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.06, 0.82)
	s.border_color = Color(1, 0.7, 0.15, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 22
	s.content_margin_bottom = 22
	return s

func _btn(text: String, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 46)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.85, 0.45, 0.08, 0.92) if accent else Color(0.14, 0.17, 0.15, 0.95)
	normal.set_corner_radius_all(8)
	normal.border_color = Color(1, 0.75, 0.3, 0.8) if accent else Color(1, 1, 1, 0.25)
	normal.set_border_width_all(1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 0.55, 0.1, 1) if accent else Color(0.2, 0.24, 0.21, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", Color(1, 0.98, 0.94))
	b.add_theme_font_size_override("font_size", 18)
	return b

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _toggle_btn(text: String, group: Dictionary, key) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(52, 40)
	group[key] = b
	return b

func _refresh_toggles() -> void:
	for k in _char_btns:
		(_char_btns[k] as Button).button_pressed = String(k) == char_id
	for k in _lives_btns:
		(_lives_btns[k] as Button).button_pressed = str(k) == str(lives_choice)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	# ---- 主菜单 ----
	menu_panel = PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_panel.add_child(mv)
	var title := _label("魂斗罗 3D", 52, Color(1, 0.72, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(title)
	var sub := _label("CONTRA 3D · 原作复原 · GTA式越肩视角", 15, Color(0.75, 0.8, 0.72))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(sub)
	var char_row := HBoxContainer.new()
	char_row.alignment = BoxContainer.ALIGNMENT_CENTER
	char_row.add_theme_constant_override("separation", 8)
	char_row.add_child(_label("角色", 16, Color(1, 0.8, 0.35)))
	var b_bill := _toggle_btn("比尔·雷泽", _char_btns, "bill")
	b_bill.custom_minimum_size = Vector2(130, 40)
	b_bill.pressed.connect(func(): _set_char("bill"))
	char_row.add_child(b_bill)
	var b_lance := _toggle_btn("兰斯·比恩", _char_btns, "lance")
	b_lance.custom_minimum_size = Vector2(130, 40)
	b_lance.pressed.connect(func(): _set_char("lance"))
	char_row.add_child(b_lance)
	mv.add_child(char_row)
	var lives_row := HBoxContainer.new()
	lives_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lives_row.add_theme_constant_override("separation", 8)
	lives_row.add_child(_label("命数", 16, Color(1, 0.8, 0.35)))
	for v in [3, 5, 10, 30]:
		var lb := _toggle_btn(str(v), _lives_btns, v)
		lb.pressed.connect(_set_lives.bind(v))
		lives_row.add_child(lb)
	var lb_inf := _toggle_btn("∞", _lives_btns, "inf")
	lb_inf.pressed.connect(func(): _set_lives("inf"))
	lives_row.add_child(lb_inf)
	mv.add_child(lives_row)
	var btn_start := _btn("开始游戏", true)
	btn_start.pressed.connect(func(): start_game())
	mv.add_child(btn_start)
	var btn_ctrl := _btn("操作说明")
	btn_ctrl.pressed.connect(func(): controls_panel.visible = true)
	mv.add_child(btn_ctrl)
	_lbl_hi = _label("最高分: 0", 13, Color(0.65, 0.7, 0.62))
	_lbl_hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_lbl_hi)
	var hint := _label("WASD移动 | 鼠标镜头 | 左键射击 | 右键瞄准 | 空格跳 | C趴下 | Shift疾跑 | M音乐\n秘籍 ↑↑↓↓←→←→BA = 30命 · 命尽可续关3次 · 打飞鹰换枪 S/M/F/L", 12, Color(0.55, 0.6, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(hint)
	_wrap_center(menu_panel)
	# ---- 操作说明 ----
	controls_panel = PanelContainer.new()
	controls_panel.add_theme_stylebox_override("panel", _panel_style())
	controls_panel.set_anchors_preset(Control.PRESET_CENTER)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	controls_panel.add_child(cv)
	cv.add_child(_label("操作说明", 24, Color(1, 0.72, 0.2)))
	cv.add_child(_label("W A S D — 移动（相对镜头）\n鼠标 — 越肩镜头（点击画面锁定）\n左键 — 射击（按准星，可瞄高低）\n右键 — 瞄准（镜头收紧）\n空格 — 跳跃（翻跟头跳，空中可开火）\nC / Ctrl — 趴下（躲高弹道）\nShift — 疾跑\n飞鹰 — 打下红隼徽章掉武器胶囊：S散射 M机枪 F火球 L激光 R加速 B防护罩\n手机 — 左摇杆移动 · 右侧射击/跳/趴按钮 · 拖屏转镜头", 15, Color(0.85, 0.88, 0.82)))
	var btn_back := _btn("返回")
	btn_back.pressed.connect(func(): controls_panel.visible = false)
	cv.add_child(btn_back)
	controls_panel.visible = false
	_wrap_center(controls_panel)
	_build_hud()
	_build_end_panels()
	_build_touch()
	_refresh_toggles()

func _wrap_center(p: Control) -> void:
	# 用全屏 CenterContainer 兜底居中——比手算锚点偏移可靠（实测教训）
	# ⚠️ 包装层必须 IGNORE：全屏容器默认 STOP 会把所有点击吃掉（v3.0.0 菜单点不动的根因）
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(cc)
	cc.add_child(p)

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	# 准星
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8, -16)
	hud.add_child(cross)
	# 左上分数
	_lbl_score = _label("分数: 0", 19, Color(1, 0.85, 0.3))
	_lbl_score.position = Vector2(24, 16)
	hud.add_child(_lbl_score)
	# 顶部中央：关卡与进度、Boss 条
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-160, 12)
	top.custom_minimum_size = Vector2(320, 60)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	hud.add_child(top)
	_lbl_level = _label("第1关: 丛林", 16, Color(1, 1, 1))
	_lbl_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_lbl_level)
	var prog_bg := ColorRect.new()
	prog_bg.color = Color(0, 0, 0, 0.55)
	prog_bg.custom_minimum_size = Vector2(320, 8)
	top.add_child(prog_bg)
	_prog_fill = ColorRect.new()
	_prog_fill.color = Color(1, 0.62, 0.15)
	_prog_fill.custom_minimum_size = Vector2(2, 8)
	prog_bg.add_child(_prog_fill)
	_lbl_progress = _label("0m / 190m", 12, Color(0.8, 0.82, 0.78))
	_lbl_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_lbl_progress)
	_boss_bar = VBoxContainer.new()
	_lbl_boss = _label("BOSS", 13, Color(1, 0.4, 0.3))
	_lbl_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar.add_child(_lbl_boss)
	var bb := ColorRect.new()
	bb.color = Color(0.1, 0, 0, 0.6)
	bb.custom_minimum_size = Vector2(320, 10)
	_boss_bar.add_child(bb)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(1, 0.25, 0.2)
	_boss_fill.custom_minimum_size = Vector2(318, 10)
	bb.add_child(_boss_fill)
	_boss_bar.visible = false
	top.add_child(_boss_bar)
	# 左下：格血 + 命数
	var bl := HBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(24, -56)
	bl.add_theme_constant_override("separation", 6)
	hud.add_child(bl)
	for i in 3:
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(34, 16)
		cell.color = Color(0.9, 0.2, 0.15)
		bl.add_child(cell)
		_cells.append(cell)
	_lbl_lives = _label("命 ×3", 17, Color(1, 0.85, 0.3))
	bl.add_child(_lbl_lives)
	# 右下：武器
	_lbl_weapon = _label("N · 步枪", 16, Color(1, 0.75, 0.35))
	_lbl_weapon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_lbl_weapon.position = Vector2(-190, -52)
	_lbl_weapon.custom_minimum_size = Vector2(170, 24)
	_lbl_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_lbl_weapon)
	# 中央消息
	_lbl_center = _label("", 27, Color(1, 0.7, 0.25))
	_lbl_center.set_anchors_preset(Control.PRESET_CENTER)
	_lbl_center.position = Vector2(-300, -90)
	_lbl_center.custom_minimum_size = Vector2(600, 40)
	_lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_center.modulate.a = 0.0
	hud.add_child(_lbl_center)
	# 剧情框
	_dialog_panel = PanelContainer.new()
	_dialog_panel.add_theme_stylebox_override("panel", _panel_style())
	_dialog_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog_panel.position = Vector2(-320, -170)
	_dialog_panel.custom_minimum_size = Vector2(640, 90)
	_lbl_dialog = _label("", 16, Color(0.92, 0.94, 0.9))
	_lbl_dialog.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_panel.add_child(_lbl_dialog)
	_dialog_panel.visible = false
	_dialog_panel.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and _dialog_cb.is_valid():
			_dialog_cb.call())
	hud.add_child(_dialog_panel)
	hud.visible = false

func _build_end_panels() -> void:
	# 失败
	gameover_panel = PanelContainer.new()
	gameover_panel.add_theme_stylebox_override("panel", _panel_style())
	gameover_panel.set_anchors_preset(Control.PRESET_CENTER)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 10)
	gv.alignment = BoxContainer.ALIGNMENT_CENTER
	gameover_panel.add_child(gv)
	var t := _label("任务失败", 40, Color(1, 0.3, 0.25))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(t)
	_lbl_over_text = _label("", 15, Color(0.8, 0.82, 0.78))
	_lbl_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(_lbl_over_text)
	_btn_continue = _btn("续关 — 本关重开", true)
	_btn_continue.pressed.connect(func(): _continue_game())
	gv.add_child(_btn_continue)
	var btn_retry := _btn("重新开始")
	btn_retry.pressed.connect(func(): start_game())
	gv.add_child(btn_retry)
	var btn_menu := _btn("返回菜单")
	btn_menu.pressed.connect(func(): show_menu())
	gv.add_child(btn_menu)
	gameover_panel.visible = false
	_wrap_center(gameover_panel)
	# 胜利
	victory_panel = PanelContainer.new()
	victory_panel.add_theme_stylebox_override("panel", _panel_style())
	victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 10)
	vv.alignment = BoxContainer.ALIGNMENT_CENTER
	victory_panel.add_child(vv)
	var vt := _label("任务完成！", 40, Color(1, 0.85, 0.25))
	vt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vv.add_child(vt)
	vv.add_child(_label("天王创魔心已被摧毁，红隼覆灭，地球得救！", 15, Color(0.85, 0.88, 0.82)))
	_lbl_final = _label("最终分数: 0", 20, Color(1, 0.85, 0.3))
	_lbl_final.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vv.add_child(_lbl_final)
	var btn_again := _btn("再玩一次", true)
	btn_again.pressed.connect(func(): start_game())
	vv.add_child(btn_again)
	var btn_vmenu := _btn("返回菜单")
	btn_vmenu.pressed.connect(func(): show_menu())
	vv.add_child(btn_vmenu)
	victory_panel.visible = false
	_wrap_center(victory_panel)

func _build_touch() -> void:
	touch_ui = Control.new()
	touch_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(touch_ui)
	var joy := Control.new()
	joy.name = "Joy"
	joy.position = Vector2(36, -196)
	joy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joy.custom_minimum_size = Vector2(150, 150)
	joy.mouse_filter = Control.MOUSE_FILTER_STOP
	touch_ui.add_child(joy)
	joy.gui_input.connect(_on_joy_input.bind(joy))
	var mk_btn := func(text: String, pos: Vector2) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(74, 74)
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		b.position = pos
		touch_ui.add_child(b)
		return b
	var shoot_b: Button = mk_btn.call("射击", Vector2(-110, -120))
	shoot_b.button_down.connect(func(): _touch_shoot = true)
	shoot_b.button_up.connect(func(): _touch_shoot = false)
	var jump_b: Button = mk_btn.call("跳", Vector2(-196, -110))
	jump_b.button_down.connect(func(): _touch_jump = true)
	var prone_b: Button = mk_btn.call("趴", Vector2(-196, -196))
	prone_b.toggled.connect(func(on): _touch_prone = on)
	prone_b.toggle_mode = true
	touch_ui.visible = false

func _on_joy_input(ev: InputEvent, joy: Control) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_joy_id = ev.index
			_joy_center = joy.global_position + Vector2(75, 75)
		elif ev.index == _joy_id:
			_joy_id = -1
			_touch_move = Vector2.ZERO
	elif ev is InputEventScreenDrag and ev.index == _joy_id:
		var drag := ev as InputEventScreenDrag
		var v: Vector2 = (drag.position + joy.global_position - _joy_center) / 55.0
		_touch_move = v.limit_length(1.0)

var lives_inf := false
var diorama: Node3D
var _center_tw: Tween

# ---------------- 设置 ----------------
func _set_char(c: String) -> void:
	char_id = c
	_refresh_toggles()
	if state == "menu" and is_instance_valid(_menu_player):
		var pos := _menu_player.global_position
		var f := _menu_player.facing
		_menu_player.destroy_player()
		_menu_player = Player.new()
		diorama.add_child(_menu_player)
		_menu_player.setup(char_id)
		_menu_player.global_position = pos
		_menu_player.facing = f

func _set_lives(v) -> void:
	lives_choice = v
	_refresh_toggles()

func _load_hi() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://contra3d_save.cfg") == OK:
		hi_score = int(cfg.get_value("game", "hi", 0))

func _save_hi() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "hi", hi_score)
	cfg.save("user://contra3d_save.cfg")

func _update_hi_label() -> void:
	_lbl_hi.text = "最高分: %d" % hi_score

# ---------------- 游戏流程 ----------------
func show_menu() -> void:
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioSys.stop_bgm()
	_free_run()
	hud.visible = false
	gameover_panel.visible = false
	victory_panel.visible = false
	controls_panel.visible = false
	touch_ui.visible = false
	menu_panel.visible = true
	_menu_env()
	diorama.visible = true
	if not is_instance_valid(_menu_player):
		_menu_player = Player.new()
		diorama.add_child(_menu_player)
		_menu_player.setup(char_id)
		_menu_player.global_position = Vector3(0, 0, 14)
		_menu_player.facing = PI * 0.92
	_update_hi_label()

func _free_run() -> void:
	if is_instance_valid(current_level):
		current_level.destroy_level()
		current_level = null
	if is_instance_valid(player):
		player.destroy_player()
		player = null
	projectiles.clear_all()

func start_game() -> void:
	score = 0
	_next_extend = int(Data.PLAYER["extend_score"])
	lives_inf = lives_choice is String
	lives = 3 if lives_inf else int(lives_choice)
	continues_left = 3
	diorama.visible = false
	menu_panel.visible = false
	gameover_panel.visible = false
	victory_panel.visible = false
	controls_panel.visible = false
	hud.visible = true
	touch_ui.visible = DisplayServer.is_touchscreen_available()
	_load_level(0)
	AudioSys.start_bgm()

func _load_level(idx: int) -> void:
	level_index = idx
	_free_run()
	var data: Dictionary = Data.LEVELS[idx]
	current_level = Level.new()
	add_child(current_level)
	current_level.setup(data, idx, {
		"projectiles": projectiles,
		"world_env": world_env,
		"soldier_scene": soldier_scene,
		"on_score": _add_score,
		"on_pickup": func(letter): if is_instance_valid(player): player.apply_pickup(letter),
		"on_checkpoint": func(pos): checkpoint = pos,
		"on_boss_activated": _on_boss_activated,
		"on_boss_defeated": _on_boss_defeated,
		"on_core_exposed": func(): _center_msg("⚠ 核心暴露！全力开火！"),
	})
	player = Player.new()
	add_child(player)
	player.setup(char_id)
	player.died.connect(_on_player_death)
	player.damaged.connect(func(): _update_hud())
	checkpoint = Vector3(0, current_level.get_support_y(0, 26, 999.0), 26)
	player.reset_player(checkpoint, false)
	_yaw = PI
	_pitch = 0.0
	rig.snap_to(player.global_position, _yaw, _pitch)
	_boss_bar.visible = false
	_show_dialog(String(data["name"]) + "\n" + String(data["story"]), func():
		state = "playing"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_update_hud()

func _show_dialog(text: String, cb: Callable) -> void:
	state = "dialog"
	_dialog_cb = cb
	_lbl_dialog.text = text + "\n（点击画面或按跳跃键继续）"
	_dialog_panel.visible = true

func _advance_dialog() -> void:
	if state != "dialog":
		return
	_dialog_panel.visible = false
	var cb := _dialog_cb
	_dialog_cb = Callable()
	if cb.is_valid():
		cb.call()

func _on_boss_activated(boss) -> void:
	var bd: Dictionary = Data.BOSSES[boss.boss_id]
	_center_msg("⚠ " + String(bd["name"]) + " ⚠\n" + String(bd.get("hint", "")))
	_boss_bar.visible = true
	_lbl_boss.text = String(Data.BOSSES[boss.boss_id]["name"])

func _on_boss_defeated() -> void:
	_boss_bar.visible = false
	await get_tree().create_timer(1.5).timeout
	if state != "playing" or not is_instance_valid(player) or not player.alive:
		return
	_add_score(1000)
	_center_msg("过关！ +1000")
	AudioSys.play("clear")
	state = "levelclear"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(1.6).timeout
	if state != "levelclear":
		return
	if level_index >= Data.LEVELS.size() - 1:
		state = "victory"
		if score > hi_score:
			hi_score = score
			_save_hi()
		_lbl_final.text = "最终分数: %d" % score
		victory_panel.visible = true
		AudioSys.stop_bgm()
	else:
		_load_level(level_index + 1)

func _on_player_death() -> void:
	_update_hud()
	await get_tree().create_timer(1.3).timeout
	if state != "playing":
		return
	if not lives_inf:
		lives -= 1
	_update_hud()
	if lives_inf or lives > 0:
		player.respawn_player(checkpoint)
		_yaw = PI
		_pitch = 0.0
		rig.snap_to(player.global_position, _yaw, _pitch)
	else:
		state = "gameover"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if score > hi_score:
			hi_score = score
			_save_hi()
		_lbl_over_text.text = "倒在 %s · 分数 %d%s" % [String(Data.LEVELS[level_index]["name"]), score, (" · 剩余续关 %d 次" % continues_left) if continues_left > 0 else ""]
		_btn_continue.visible = continues_left > 0
		gameover_panel.visible = true
		AudioSys.stop_bgm()

func _continue_game() -> void:
	if continues_left <= 0:
		return
	continues_left -= 1
	lives_inf = lives_choice is String
	lives = 3 if lives_inf else int(lives_choice)
	gameover_panel.visible = false
	_load_level(level_index)
	AudioSys.start_bgm()

func _add_score(pts: int) -> void:
	score += pts
	while score >= _next_extend:
		_next_extend += int(Data.PLAYER["extend_score"])
		if not lives_inf:
			lives += 1
			_center_msg("延长！命 +1（%d分）" % (score - int(Data.PLAYER["extend_score"])))
			AudioSys.play("pickup")
	_update_hud()

func _center_msg(text: String) -> void:
	_lbl_center.text = text
	if _center_tw and _center_tw.is_valid():
		_center_tw.kill()
	_lbl_center.modulate.a = 1.0
	_center_tw = create_tween()
	_center_tw.tween_interval(1.6)
	_center_tw.tween_property(_lbl_center, "modulate:a", 0.0, 0.6)

# ---------------- HUD ----------------
func _weapon_text() -> String:
	var w: Dictionary = Data.WEAPONS[player.weapon]
	var extra := ""
	if player.rapid:
		extra += " R"
	if player.barrier > 0.0:
		extra += " B%.0f" % player.barrier
	return "%s · %s%s" % [w["letter"], w["name"], extra]

func _update_hud() -> void:
	if not is_instance_valid(player) or current_level == null:
		return
	_lbl_score.text = "分数: %d" % score
	_lbl_level.text = String(Data.LEVELS[level_index]["name"])
	var dist := current_level.player_dist(player)
	var total := float(Data.LEVELS[level_index]["length"])
	_prog_fill.size = Vector2(maxf(2.0, 318.0 * clampf(dist / total, 0.0, 1.0)), 8)
	_lbl_progress.text = "%dm / %dm" % [int(dist), int(total)]
	for i in _cells.size():
		_cells[i].color = Color(0.9, 0.2, 0.15) if i < player.hp_cells else Color(0.3, 0.1, 0.09)
	_lbl_lives.text = "命 ×∞" if lives_inf else "命 ×%d" % lives
	_lbl_weapon.text = _weapon_text()
	if _boss_bar.visible and current_level.boss_active:
		_boss_fill.size = Vector2(maxf(0.0, 318.0 * current_level.boss_fraction), 10)

# ---------------- 输入 ----------------
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_M:
		var muted_now: bool = AudioSys.toggle_mute()
		_center_msg("音乐关" if muted_now else "音乐开")
	if state == "menu":
		if ev is InputEventKey and ev.pressed and not ev.echo:
			for a in KONAMI:
				if ev.is_action_pressed(a):
					_konami.append(a)
					if _konami.size() > KONAMI.size():
						_konami.pop_front()
					if _konami == KONAMI.slice(0, _konami.size()) and _konami.size() == KONAMI.size():
						lives_inf = false
						lives_choice = 30
						_refresh_toggles()
					break
		return
	if state == "dialog":
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventKey and ev.pressed and ev.keycode == KEY_SPACE) or (ev is InputEventScreenTouch and ev.pressed):
			_advance_dialog()
		return
	if state != "playing":
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and ev is InputEventMouseButton and ev.pressed and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= ev.relative.x * 0.0026
		_pitch = clampf(_pitch - ev.relative.y * 0.0026, float(Data.CAMERA["pitch_min"]), float(Data.CAMERA["pitch_max"]))
	elif ev is InputEventScreenDrag and ev.index != _joy_id:
		_yaw -= ev.relative.x * 0.006
		_pitch = clampf(_pitch - ev.relative.y * 0.006, float(Data.CAMERA["pitch_min"]), float(Data.CAMERA["pitch_max"]))

func _build_snapshot() -> Dictionary:
	var mv := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	if _touch_move.length() > 0.1:
		mv = Vector2(_touch_move.x, _touch_move.y) # 摇杆 y 向下为正 = 后退，与 move.y 语义一致
	var jump_now := Input.is_action_just_pressed("jump") or _touch_jump
	_touch_jump = false
	return {
		"move": mv,
		"jump": jump_now,
		"prone": Input.is_action_pressed("prone") or _touch_prone,
		"run": Input.is_action_pressed("run"),
	}

# ---------------- 主循环 ----------------
func _process(dt: float) -> void:
	dt = minf(dt, 0.05) # 钳制帧步长：低帧率/卡顿设备上不快进（软件渲染实测教训）
	if state == "menu":
		_menu_time += dt
		if is_instance_valid(_menu_player):
			_menu_player.facing = PI * 0.92 + sin(_menu_time * 0.3) * 0.14
			_menu_player._sync_visual(0.0, false, false)
		return
	if state != "playing" or not is_instance_valid(player) or current_level == null:
		return
	var aiming := Input.is_action_pressed("aim")
	var shooting := Input.is_action_pressed("shoot") or _touch_shoot
	if _touch_shoot:
		aiming = true
	var snap := _build_snapshot()
	player.update_player(dt, snap, current_level, _yaw, _pitch, aiming or shooting)
	if shooting:
		player.try_shoot(projectiles, rig.aim_point)
	current_level.update_level(dt, player, camera.global_position)
	projectiles.update_projectiles(dt, {
		"targets": current_level.get_targets(),
		"colliders": current_level.colliders,
		"player": player,
		"on_player_hit": func(cells): player.take_damage(cells),
	})
	rig.update_rig(dt, {
		"anchor": player.global_position,
		"yaw": _yaw,
		"pitch": _pitch,
		"aiming": aiming,
		"prone": player.prone,
		"colliders": current_level.colliders,
		"targets": current_level.get_targets(),
	})
	_update_hud()

func _menu_env() -> void:
	var env := world_env.environment
	var sky_res := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/forest.hdr")
	sky_res.sky_material = pm
	env.sky = sky_res
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.16, 0.1)
	env.fog_density = 0.012
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	camera.global_position = Vector3(3.4, 2.1, 20.5)
	camera.look_at(Vector3(0, 1.4, 14), Vector3.UP)
