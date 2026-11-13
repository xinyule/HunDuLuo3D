extends Node3D

## 主引擎 —— 状态机是唯一有权改 state 的地方
## 状态：menu / loading / dialog / playing / levelclear / gameover / victory
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
var soldier_scenes: Dictionary = {} # 兵种 -> PackedScene（Mixamo 集成：每兵种独立 GLB）

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
var codex_panel: PanelContainer
var _codex_list: VBoxContainer
var hud: Control
var gameover_panel: PanelContainer
var victory_panel: PanelContainer
var _lbl_score: Label
var _lbl_level: Label
var _lbl_progress: Label
var _prog_fill: ColorRect
var _hurt_rect: ColorRect
var _hurt_a := 0.0
var _hitstop_end := 0 # 顿帧结束时刻（ticks ms，真实时间计）
var _hitstop_next := 0 # 下次可触发顿帧时刻（防连发叠加）
var _lbl_obj: Label
var _obj_text := ""
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
var _diff_btns: Dictionary = {}
var _qual_btns: Dictionary = {}
var _lvl_btns: Dictionary = {}
# 设置与长期进度（统一存 user://contra3d_save.cfg）
var difficulty := "normal" # easy / normal / hard
var quality := "high" # low / mid / high
var cleared_levels: Dictionary = {} # idx(int) -> true
var level_ratings: Dictionary = {} # idx(int) -> "S"/"A"/"B"/"C"（历史最佳）
var encountered: Dictionary = {} # 敌人 type(String) -> true（图鉴遭遇）
var unlocked_max := 0 # 已解锁到的最高关卡下标（通关 i 解锁 i+1）
# 击杀飘分 + 连杀（击杀经 level 的 on_kill 钩子进 _on_kill；连杀只弹字不另加分，守对标计分）
var _combo := 0
var _combo_t := 0.0
const COMBO_WINDOW := 3.0
var _float_layer: Control
var _floats: Array = []
var _edge_arrow: Label
# 每关环境音（程序合成循环，素材 gen_ambient.py 产出 amb_<theme>.wav；音量压在 BGM 之下）
var _amb: AudioStreamPlayer
var _amb_streams: Dictionary = {}
# BGM 分关变奏流缓存（bgm_<key>.wav，gen_bgm_sfx.py 产出）与 UI/登场音效小池
# （AudioSys 预加载名单固定，新音效走 main 自有播放器，见 _play_ui_sfx）
var _bgm_streams: Dictionary = {}
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_streams: Dictionary = {}
var _ui_idx := 0
var _cross: TextureRect
# 加载界面 + 点击引导（1.1.0 体验项：加载过程要让玩家看见、进关点击要有引导）
var load_layer: Control
var _load_title: Label
var _load_stage_lbl: Label
var _load_fill: ColorRect
var _load_pct: Label
var _load_tip: Label
var _loading := false # 关卡分阶段生成进行中（防重入）
var _load_frame_shown := -1 # 加载界面上屏帧号（探针时序实证用）
var _load_frame_gen_start := -1 # 生成开始帧号
var _load_frame_gen_end := -1 # 生成结束帧号
var _click_hint: Control
var _hint_label: Label
var _hint_active := false
var _hint_alpha := 0.0
var _hint_pulse := 0.0
var _hint_ever_captured := false
# 通关评级：本关计时与起始分（_load_level 时重置；续关重开本关同样重置，与既有续关语义一致）
var _level_time := 0.0
var _level_start_score := 0
var _last_rating := ""
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
	for t in Enemy.HUMANOID:
		if t == "shield":
			continue # 盾牌兵无独立 GLB（下行借步枪兵模型），跳过避免 load 不存在文件刷 ERROR
		soldier_scenes[t] = load("res://assets/char/enemy_%s.glb" % t)
	soldier_scenes["shield"] = soldier_scenes.get("rifleman") # 盾牌兵借步枪兵模型 + 大盾道具（enemy.gd 内拼装）
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
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Master" # 跟随 M 键总静音
	_amb.volume_db = -22.0 # 压在 BGM(-9) 之下，只作氛围垫
	add_child(_amb)
	for i in 3: # UI/登场音效小池（ui_click/ui_confirm/boss_intro）
		var upl := AudioStreamPlayer.new()
		upl.bus = "Master"
		add_child(upl)
		_ui_pool.append(upl)
	projectiles = ProjectileSystem.new()
	add_child(projectiles)
	# 爆炸震屏：projectiles 只报位置/半径，这里按与玩家距离衰减后驱动镜头（近爆强、远爆弱）
	projectiles.shake_hook = func(pos: Vector3, radius: float) -> void:
		if is_instance_valid(player) and is_instance_valid(rig):
			var d := pos.distance_to(player.global_position)
			var s := clampf(1.0 - d / 22.0, 0.0, 1.0) * clampf(0.4 + radius * 0.17, 0.0, 0.95)
			if s > rig.shake:
				rig.shake = s
	_load_hi()
	_apply_difficulty()
	_apply_quality()
	_build_ui()
	_build_menu_diorama()
	_apply_quality() # 布景建好后把画质（日光阴影）补应用一次
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
	pm.panorama = load("res://assets/hdri/jungle_day.hdr") # 菜单天空与第1关统一（终检：旧 forest.hdr 已退役）
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
	b.pressed.connect(func(): _play_ui_sfx("ui_click", -7.0))
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

## 菜单徽标贴图（程序绘制，无外部素材）：金环 + 猩红圆盘 + 金色五角星 + 两侧上扬翼条（红隼军徽意象）
func _make_emblem_texture() -> Texture2D:
	var w := 168
	var h := 104
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gold := Color(0.98, 0.66, 0.16, 1)
	var gold_dim := Color(0.72, 0.44, 0.1, 1)
	var crimson := Color(0.62, 0.07, 0.07, 1)
	var dark := Color(0.13, 0.05, 0.03, 1)
	var c := Vector2(w * 0.5, h * 0.52)
	# 翼条：每侧 3 根，自徽章向外上扬、逐根变短变薄（用点到线段距离判定）
	var segs: Array = []
	for side in [-1.0, 1.0]:
		for i in 3:
			var y0 := c.y - 14.0 + i * 13.0
			var a := Vector2(c.x + side * 26.0, y0)
			var b := Vector2(c.x + side * (72.0 - i * 9.0), y0 - (15.0 - i * 3.0))
			segs.append([a, b, 3.4 - i * 0.7])
	# 五角星多边形（外接圆 15、内接 6.2，尖朝上）
	var star: Array[Vector2] = []
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		var rad := 15.0 if i % 2 == 0 else 6.2
		star.append(c + Vector2(cos(ang), sin(ang)) * rad)
	var star_packed := PackedVector2Array(star)
	for y in h:
		for x in w:
			var p := Vector2(x, y)
			var d := p.distance_to(c)
			var col := Color(0, 0, 0, 0)
			for s in segs:
				var a: Vector2 = s[0]
				var b: Vector2 = s[1]
				var pa := p - a
				var ba := b - a
				var t := clampf(pa.dot(ba) / ba.length_squared(), 0.0, 1.0)
				if (a + ba * t).distance_to(p) <= float(s[2]):
					col = gold_dim
			if d <= 35.0 and d > 31.5:
				col = gold # 外金环
			elif d <= 31.5 and d > 29.5:
				col = dark # 环内描边
			elif d <= 29.5:
				col = crimson
			if Geometry2D.is_point_in_polygon(p, star_packed):
				col = gold
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## 准星贴图（程序绘制）：中心点 + 四向刻度，形状外 1px 深色描边保证亮背景可读；白色绘制、靠 modulate 变色
func _make_crosshair_texture() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ctr := s / 2
	var shape := {}
	for y in s:
		for x in s:
			var dx := x - ctr + 0.5
			var dy := y - ctr + 0.5
			var r := sqrt(dx * dx + dy * dy)
			var inside := r <= 2.1
			if not inside and ((absf(dy) <= 1.3 and absf(dx) >= 6.5 and absf(dx) <= 14.5) \
					or (absf(dx) <= 1.3 and absf(dy) >= 6.5 and absf(dy) <= 14.5)):
				inside = true
			if inside:
				shape[Vector2i(x, y)] = true
	for y in s:
		for x in s:
			if shape.has(Vector2i(x, y)):
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				var near := false
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if shape.has(Vector2i(x, y) + o):
						near = true
						break
				if near:
					img.set_pixel(x, y, Color(0, 0, 0, 0.55))
	return ImageTexture.create_from_image(img)

## 鼠标图标贴图（程序绘制）：圆角矩形轮廓 + 滚轮 + 左右键分界，白色配深色描边（与准星同法）
func _make_mouse_texture() -> Texture2D:
	var w := 36
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var shape := {}
	var c := Vector2(17.5, 23.5)
	for y in h:
		for x in w:
			var p := Vector2(x, y)
			var q := Vector2(absf(p.x - c.x), absf(p.y - c.y)) - Vector2(9.0, 15.0)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 8.0
			var inside := d <= 0.0 and d > -2.6 # 轮廓线
			if not inside and absf(p.x - c.x) <= 1.1 and p.y >= 10.0 and p.y <= 19.0:
				inside = true # 滚轮
			if not inside and d <= 0.0 and p.y >= 15.5 and p.y <= 17.5 and absf(p.x - c.x) <= 12.0:
				inside = true # 左右键分界线
			if inside:
				shape[Vector2i(x, y)] = true
	for y in h:
		for x in w:
			if shape.has(Vector2i(x, y)):
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				var near := false
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if shape.has(Vector2i(x, y) + o):
						near = true
						break
				if near:
					img.set_pixel(x, y, Color(0, 0, 0, 0.55))
	return ImageTexture.create_from_image(img)

func _toggle_btn(text: String, group: Dictionary, key) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(52, 40)
	group[key] = b
	b.pressed.connect(func(): _play_ui_sfx("ui_click", -8.0))
	return b

func _refresh_toggles() -> void:
	for k in _char_btns:
		(_char_btns[k] as Button).button_pressed = String(k) == char_id
	for k in _lives_btns:
		(_lives_btns[k] as Button).button_pressed = str(k) == str(lives_choice)
	for k in _diff_btns:
		(_diff_btns[k] as Button).button_pressed = String(k) == difficulty
	for k in _qual_btns:
		(_qual_btns[k] as Button).button_pressed = String(k) == quality

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
	# 徽标（程序绘制贴图，见 _make_emblem_texture）+ 描边标题 + 金色下划线
	var emblem := TextureRect.new()
	emblem.texture = _make_emblem_texture()
	emblem.custom_minimum_size = Vector2(126, 78)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var emblem_box := CenterContainer.new()
	emblem_box.add_child(emblem)
	mv.add_child(emblem_box)
	var title := _label("魂斗罗 3D", 52, Color(1, 0.72, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.05, 0.02, 1))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	mv.add_child(title)
	var bar_box := CenterContainer.new()
	var title_bar := ColorRect.new()
	title_bar.color = Color(0.98, 0.62, 0.14, 0.9)
	title_bar.custom_minimum_size = Vector2(300, 3)
	bar_box.add_child(title_bar)
	mv.add_child(bar_box)
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
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	diff_row.add_child(_label("难度", 16, Color(1, 0.8, 0.35)))
	for dv in [["easy", "简单"], ["normal", "普通"], ["hard", "困难"]]:
		var db := _toggle_btn(String(dv[1]), _diff_btns, String(dv[0]))
		db.custom_minimum_size = Vector2(76, 40)
		db.pressed.connect(_set_difficulty.bind(String(dv[0])))
		diff_row.add_child(db)
	mv.add_child(diff_row)
	var qual_row := HBoxContainer.new()
	qual_row.alignment = BoxContainer.ALIGNMENT_CENTER
	qual_row.add_theme_constant_override("separation", 8)
	qual_row.add_child(_label("画质", 16, Color(1, 0.8, 0.35)))
	for qv in [["low", "低"], ["mid", "中"], ["high", "高"]]:
		var qb := _toggle_btn(String(qv[1]), _qual_btns, String(qv[0]))
		qb.custom_minimum_size = Vector2(76, 40)
		qb.pressed.connect(_set_quality.bind(String(qv[0])))
		qual_row.add_child(qb)
	mv.add_child(qual_row)
	var lvl_row := HBoxContainer.new()
	lvl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lvl_row.add_theme_constant_override("separation", 6)
	lvl_row.add_child(_label("选关", 16, Color(1, 0.8, 0.35)))
	for i in Data.LEVELS.size():
		var lb2 := Button.new()
		lb2.custom_minimum_size = Vector2(52, 40)
		lb2.add_theme_font_size_override("font_size", 15)
		lb2.pressed.connect(_start_from_level.bind(i))
		_lvl_btns[i] = lb2
		lvl_row.add_child(lb2)
	mv.add_child(lvl_row)
	_refresh_level_buttons()
	var btn_start := _btn("开始游戏", true)
	btn_start.pressed.connect(func(): start_game())
	mv.add_child(btn_start)
	var btn_ctrl := _btn("操作说明")
	btn_ctrl.pressed.connect(func(): controls_panel.visible = true)
	mv.add_child(btn_ctrl)
	var btn_codex := _btn("敌人图鉴")
	btn_codex.pressed.connect(_show_codex)
	mv.add_child(btn_codex)
	_lbl_hi = _label("最高分: 0", 13, Color(0.65, 0.7, 0.62))
	_lbl_hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_lbl_hi)
	var hint := _label("WASD移动 | 鼠标镜头 | 左键射击 | 右键瞄准 | 空格跳 | C趴下 | Shift疾跑 | M音乐\n秘籍 ↑↑↓↓←→←→BA = 30命 · 命尽可续关3次 · 打飞鹰换枪 S/M/F/L", 12, Color(0.55, 0.6, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(hint)
	var ver := _label("版本 v" + Data.VERSION, 12, Color(0.45, 0.5, 0.45))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(ver)
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
	# ---- 敌人图鉴 ----
	codex_panel = PanelContainer.new()
	codex_panel.add_theme_stylebox_override("panel", _panel_style())
	codex_panel.set_anchors_preset(Control.PRESET_CENTER)
	codex_panel.custom_minimum_size = Vector2(560, 0)
	var kv := VBoxContainer.new()
	kv.add_theme_constant_override("separation", 8)
	codex_panel.add_child(kv)
	kv.add_child(_label("敌人图鉴", 24, Color(1, 0.72, 0.2)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 380)
	_codex_list = VBoxContainer.new()
	_codex_list.add_theme_constant_override("separation", 6)
	_codex_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_codex_list)
	kv.add_child(scroll)
	var btn_back2 := _btn("返回")
	btn_back2.pressed.connect(func(): codex_panel.visible = false)
	kv.add_child(btn_back2)
	codex_panel.visible = false
	_wrap_center(codex_panel)
	_build_hud()
	_build_end_panels()
	_build_touch()
	_build_loading_ui() # 最后建：绘制顺序在最上层，生成时盖住一切
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
	# 受击红闪（全屏，受伤瞬间亮起后快速衰减）+ 阶段目标标签
	_hurt_rect = ColorRect.new()
	_hurt_rect.color = Color(0.85, 0.04, 0.04, 0.0)
	_hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hurt_rect)
	_lbl_obj = _label("", 17, Color(1, 0.9, 0.55))
	_lbl_obj.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_obj.position = Vector2(-300, 86)
	_lbl_obj.custom_minimum_size = Vector2(600, 24)
	_lbl_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_obj.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_lbl_obj.add_theme_constant_override("shadow_offset_x", 1)
	_lbl_obj.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(_lbl_obj)
	# 屏幕边缘目标箭头：目标（Boss/未开的电网门/推进方向）在屏外时贴边指向
	_edge_arrow = _label("▶", 30, Color(1, 0.62, 0.15))
	_edge_arrow.visible = false
	_edge_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_edge_arrow)
	# 准星（程序生成贴图：中心点+四向刻度+深色描边；瞄准/射击时在 _process 里变橙红）
	_cross = TextureRect.new()
	_cross.texture = _make_crosshair_texture()
	_cross.custom_minimum_size = Vector2(44, 44)
	_cross.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cross.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cross.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.position = Vector2(-22, -22)
	_cross.modulate = Color(1, 1, 1, 0.85)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_cross)
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
	# 注意：不能给填充条设 custom_minimum_size.x —— Control.size 会被最小尺寸钳制，
	# 血条将永远满格（实测踩坑）；宽度由 _update_hud 直接写 size 控制。
	_boss_fill.size = Vector2(318, 10)
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
	# 击杀飘分层：全屏 Control + Label 池（位置由 _update_floats 每帧按世界坐标投影）
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_float_layer)
	for i in 14:
		var fl := _label("", 20, Color(1.0, 0.85, 0.3))
		fl.visible = false
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_float_layer.add_child(fl)
		_floats.append({"label": fl, "pos": Vector3.ZERO, "t": 99.0})
	# 点击引导（1.1.0 体验项）：位于画面中央下方，不挡准星；显隐/脉冲/淡出由 _update_click_hint 每帧驱动。
	# 半透明暗底垫在背面：沙地等亮背景上文字/图标可读（实测无底时金色字贴亮沙地几乎看不清）；
	# 底板与内容同属一个 Control 容器，便于 modulate 统一淡入淡出。
	_click_hint = Control.new()
	_click_hint.set_anchors_preset(Control.PRESET_CENTER)
	_click_hint.position = Vector2(-190, 150)
	_click_hint.custom_minimum_size = Vector2(380, 52)
	_click_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_click_hint)
	var hbg := Panel.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0, 0, 0, 0.45)
	hsb.set_corner_radius_all(10)
	hsb.content_margin_left = 12
	hsb.content_margin_right = 12
	hsb.content_margin_top = 6
	hsb.content_margin_bottom = 6
	hbg.add_theme_stylebox_override("panel", hsb)
	hbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_hint.add_child(hbg)
	var hrow := HBoxContainer.new()
	hrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	hrow.add_theme_constant_override("separation", 10)
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_hint.add_child(hrow)
	var mic := TextureRect.new()
	mic.texture = _make_mouse_texture()
	mic.custom_minimum_size = Vector2(30, 40)
	mic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(mic)
	var htxt := VBoxContainer.new()
	htxt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(htxt)
	_hint_label = _label("点击画面开始战斗", 20, Color(1, 0.85, 0.35))
	htxt.add_child(_hint_label)
	htxt.add_child(_label("点击后锁定鼠标视角 · Esc 可释放", 13, Color(0.75, 0.78, 0.74)))
	_click_hint.visible = false
	_click_hint.modulate.a = 0.0
	hud.visible = false

## 加载界面（1.1.0 体验项）：全屏盖住一切，生成期间显示关名/阶段/进度/小贴士；
## 鼠标过滤 STOP——生成中挡住下层所有点击，防重复开局
func _build_loading_ui() -> void:
	load_layer = Control.new()
	load_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(load_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.025, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_layer.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_layer.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	_load_title = _label("", 30, Color(1, 0.78, 0.3))
	_load_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_title)
	_load_stage_lbl = _label("", 17, Color(0.9, 0.92, 0.88))
	_load_stage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_stage_lbl)
	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(bar_row)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.custom_minimum_size = Vector2(440, 12)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(bar_bg)
	_load_fill = ColorRect.new()
	_load_fill.color = Color(1, 0.62, 0.15)
	_load_fill.size = Vector2(2, 12) # 宽度只写 size（设 minimum 会被钳住，同 Boss 血条教训）
	_load_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_load_fill)
	_load_pct = _label("0%", 13, Color(0.7, 0.74, 0.7))
	_load_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_pct)
	_load_tip = _label("", 13, Color(0.55, 0.6, 0.55))
	_load_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_tip)
	load_layer.visible = false

const LOAD_TIPS := [
	"提示：右键瞄准可收紧镜头，点射更准",
	"提示：C 键趴下可以躲开高处射来的子弹",
	"提示：打下飞鹰掉落的武器胶囊可以更换武器",
	"提示：油桶可以打爆，爆炸能清掉一小片敌人",
	"提示：Shift 疾跑赶路，接近敌人时记得放慢脚步",
]

func _show_loading(idx: int) -> void:
	var data: Dictionary = Data.LEVELS[idx]
	_load_title.text = String(data["name"])
	_load_stage_lbl.text = "正在准备…"
	_load_tip.text = LOAD_TIPS[idx % LOAD_TIPS.size()]
	_set_load_progress(0.0)
	load_layer.visible = true

func _set_load_progress(f: float) -> void:
	var cf := clampf(f, 0.0, 1.0)
	_load_fill.size = Vector2(maxf(2.0, 440.0 * cf), 12)
	_load_pct.text = "%d%%" % int(round(cf * 100.0))

## 点击引导显隐（每帧在主循环顶部统一更新）：仅游玩中、非触屏、指针未锁定时需要；
## 锁定成功后淡出消失；Esc 释放后重显且文案改「继续」；任何状态切换都会自动淡出不残留。
func _update_click_hint(dt: float) -> void:
	var want := false
	if state == "playing" and not DisplayServer.is_touchscreen_available():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_hint_ever_captured = true
		else:
			want = true
	if want and not _hint_active:
		_hint_label.text = "点击画面继续战斗" if _hint_ever_captured else "点击画面开始战斗"
	_hint_active = want
	_hint_alpha = clampf(_hint_alpha + (dt * 4.0 if want else -dt * 4.0), 0.0, 1.0)
	var a := _hint_alpha
	if want:
		_hint_pulse += dt
		a *= 0.78 + 0.22 * sin(_hint_pulse * 4.2)
	_click_hint.visible = _hint_alpha > 0.02
	_click_hint.modulate.a = a

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
		difficulty = String(cfg.get_value("settings", "difficulty", "normal"))
		if not ["easy", "normal", "hard"].has(difficulty):
			difficulty = "normal"
		quality = String(cfg.get_value("settings", "quality", "high"))
		if not ["low", "mid", "high"].has(quality):
			quality = "high"
		unlocked_max = int(cfg.get_value("progress", "unlocked", 0))
		for i in Data.LEVELS.size():
			if bool(cfg.get_value("progress", "cleared_%d" % i, false)):
				cleared_levels[i] = true
			var r := String(cfg.get_value("progress", "rating_%d" % i, ""))
			if r != "":
				level_ratings[i] = r
		for t in Data.ENEMIES:
			if bool(cfg.get_value("bestiary", String(t), false)):
				encountered[String(t)] = true

func _save_hi() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://contra3d_save.cfg") # 先读回现有文件再覆盖已知键：保住本函数不知道的键（如 pickups 写的 progress.emblems_*），不再整表重写抹键
	cfg.set_value("game", "hi", hi_score)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("progress", "unlocked", unlocked_max)
	for i in Data.LEVELS.size():
		if cleared_levels.has(i):
			cfg.set_value("progress", "cleared_%d" % i, true)
		if level_ratings.has(i):
			cfg.set_value("progress", "rating_%d" % i, String(level_ratings[i]))
	for t in encountered:
		cfg.set_value("bestiary", String(t), true)
	cfg.save("user://contra3d_save.cfg")

## 难度档（用户拍板口径）：只缩放敌人开火间隔与敌弹速度，绝不缩放杂兵 hp。
## Data.ENEMIES 是只读常量（探针实锤不可写），故走生成层两条通路等效实现：
## 弹速在 projectiles.spawn_orb/spawn_disc 施加 orb_speed_scale；间隔由 level 以
## dt 倍率驱动 update_enemy（间隔倍率与目标值精确对应：easy 间隔×1.25=dt×0.8、
## hard 间隔×0.8=dt×1.25；副作用：敌人行动/反应速度同向缩放，如实记录在案）。
const DIFF_ORB := {"easy": 0.85, "normal": 1.0, "hard": 1.15}
const DIFF_DT := {"easy": 0.8, "normal": 1.0, "hard": 1.25}

func _set_difficulty(d: String) -> void:
	difficulty = d
	_refresh_toggles()
	_save_hi()
	_apply_difficulty()

func _apply_difficulty() -> void:
	projectiles.orb_speed_scale = float(DIFF_ORB.get(difficulty, 1.0))

## 画质分档（默认高）：MSAA / 阴影 / 草量三项；贴图分辨率一律不动（画质优先铁律）。
## MSAA 与菜单日光即时生效；关卡内日光与草量在建关时按 ctx 读取（换关生效）。
func _set_quality(q: String) -> void:
	quality = q
	_refresh_toggles()
	_save_hi()
	_apply_quality()

func _apply_quality() -> void:
	var vp := get_viewport()
	match quality:
		"low": vp.msaa_3d = Viewport.MSAA_DISABLED
		"mid": vp.msaa_3d = Viewport.MSAA_2X
		_: vp.msaa_3d = Viewport.MSAA_4X
	if is_instance_valid(diorama):
		var sun := diorama.get_node_or_null("MenuSun") as DirectionalLight3D
		if sun:
			sun.shadow_enabled = quality != "low"

func _update_hi_label() -> void:
	_lbl_hi.text = "最高分: %d" % hi_score

# ---------------- 游戏流程 ----------------
func show_menu() -> void:
	state = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioSys.stop_bgm()
	if is_instance_valid(_amb):
		_amb.stop()
	_free_run()
	hud.visible = false
	gameover_panel.visible = false
	victory_panel.visible = false
	controls_panel.visible = false
	codex_panel.visible = false
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
	_refresh_level_buttons()
	_update_hi_label()

## 图鉴打开时按遭遇记录重建列表：遭遇过的点亮，未遭遇只显示「？？？」
func _show_codex() -> void:
	for c in _codex_list.get_children():
		c.queue_free()
	for t in Data.BESTIARY:
		var info: Dictionary = Data.BESTIARY[t]
		var seen: bool = encountered.has(String(t))
		var row := _label("", 15, Color(0.88, 0.9, 0.85) if seen else Color(0.42, 0.45, 0.42))
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text = ("%s —— %s" % [String(info["name"]), String(info["desc"])]) if seen else "？？？ —— 尚未遭遇"
		_codex_list.add_child(row)
	codex_panel.visible = true

## 选关行刷新：只显示已解锁关卡（下标 ≤ unlocked_max），按钮带历史最佳评级
func _refresh_level_buttons() -> void:
	for i in _lvl_btns:
		var b := _lvl_btns[i] as Button
		b.visible = int(i) <= unlocked_max
		var r := String(level_ratings.get(int(i), ""))
		b.text = "%d%s" % [int(i) + 1, ("·" + r) if r != "" else ""]

func _free_run() -> void:
	if is_instance_valid(current_level):
		current_level.destroy_level()
		current_level = null
	if is_instance_valid(player):
		player.destroy_player()
		player = null
	projectiles.clear_all()

func start_game(from_level: int = 0) -> void:
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
	codex_panel.visible = false
	hud.visible = true
	touch_ui.visible = DisplayServer.is_touchscreen_available()
	_load_level(from_level)
	AudioSys.start_bgm()

func _start_from_level(i: int) -> void:
	AudioSys.play("pickup")
	start_game(i)

## 进关（全平台统一入口：开始/选关/续关/重开/通关下一关都走这里）。
## 1.1.0 体验项：生成改为分阶段协程——先亮加载界面并等它真正画出来，再逐阶段生成、
## 每阶段先刷文案/进度再执行；玩家不会再对着冻结画面以为卡死。生成中 state="loading"。
func _load_level(idx: int) -> void:
	if _loading:
		return # 生成进行中：重复入口（连点按钮等）直接忽略，防两份关卡叠建
	_loading = true
	state = "loading"
	level_index = idx
	_level_time = 0.0
	_level_start_score = score
	_hint_ever_captured = false
	_show_loading(idx)
	_load_frame_shown = Engine.get_process_frames()
	await get_tree().process_frame
	await get_tree().process_frame # 两帧保险：布局一帧 + 绘制一帧，确保慢机上也先上屏再开工
	_load_frame_gen_start = Engine.get_process_frames()
	_free_run()
	var data: Dictionary = Data.LEVELS[idx]
	current_level = Level.new()
	add_child(current_level)
	current_level.setup(data, idx, {
		"projectiles": projectiles,
		"world_env": world_env,
		"soldier_scenes": soldier_scenes,
		"difficulty": difficulty,
		"quality": quality,
		"staged": true, # 只备阶段不执行，下面逐帧驱动（加载进度的数据源）
		"on_score": _add_score,
		"on_kill": _on_kill,
		"on_encounter": _on_encounter,
		"on_pickup": func(letter): if is_instance_valid(player): player.apply_pickup(letter),
		"on_checkpoint": func(pos): checkpoint = pos,
		"on_boss_activated": _on_boss_activated,
		"on_boss_defeated": _on_boss_defeated,
		"on_core_exposed": func(): pass, # 核心暴露靠画面本身反馈，不弹文字提示弱点
	})
	var total := current_level.build_stage_count()
	while not current_level.build_done:
		var si := current_level.build_stage_index()
		_load_stage_lbl.text = Level.BUILD_STAGE_NAMES[si] + "…"
		_set_load_progress(float(si) / float(total))
		await get_tree().process_frame # 先把本阶段的文案/进度画出来，再执行该阶段
		current_level.run_next_build_stage()
	_load_frame_gen_end = Engine.get_process_frames()
	_set_load_progress(1.0)
	player = Player.new()
	add_child(player)
	player.setup(char_id)
	player.died.connect(_on_player_death)
	player.damaged.connect(func():
		_update_hud()
		_hurt_a = 0.45 # 红闪
		rig.shake = 1.0 # 震屏
		projectiles.spawn_hit_fx(Vector3(player.global_position.x, player.chest_y(), player.global_position.z), "blood"))
	checkpoint = Vector3(0, current_level.get_support_y(0, 26, 999.0), 26)
	player.reset_player(checkpoint, false)
	_yaw = PI
	_pitch = 0.0
	rig.snap_to(player.global_position, _yaw, _pitch)
	_set_boss_bar(false)
	_start_ambient(String(data["theme"]))
	_apply_bgm_theme(String(data["theme"]))
	load_layer.visible = false # 生成完毕立即撤下加载界面，不留多余停顿
	_loading = false
	_show_dialog(String(data["name"]) + "\n" + String(data["story"]), func():
		state = "playing"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_update_hud()

## 环境音：按关卡 theme 选流（base2 与 base 共用），循环播放；切关自动换、回菜单停。
func _start_ambient(theme: String) -> void:
	var key := "base" if theme == "base2" else theme
	if not _amb_streams.has(key):
		var st := load("res://assets/audio/amb_%s.wav" % key) as AudioStreamWAV
		if st == null:
			return
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
		_amb_streams[key] = st
	if _amb.stream != _amb_streams[key]:
		_amb.stream = _amb_streams[key]
	if not _amb.playing:
		_amb.play()

## BGM 分关变奏：按 theme 给 AudioSys 的 BGM 播放器换流（借 AudioSys._bgm 换 stream 实现选曲，
## start/stop/静音语义仍走 AudioSys 原函数）。映射与环境音同系：
## base2→base、waterfall/snow→field、energy/alien/hangar→dark，其余同名；素材缺失时保留默认 bgm。
func _apply_bgm_theme(theme: String) -> void:
	var key := theme
	match theme:
		"base2": key = "base"
		"waterfall", "snow": key = "field"
		"energy", "alien", "hangar": key = "dark"
	if not _bgm_streams.has(key):
		var st := load("res://assets/audio/bgm_%s.wav" % key) as AudioStreamWAV
		if st == null:
			return
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
		_bgm_streams[key] = st
	var target: AudioStreamWAV = _bgm_streams[key]
	if AudioSys._bgm.stream != target:
		var was_playing: bool = AudioSys._bgm.playing
		AudioSys._bgm.stream = target
		if was_playing:
			AudioSys._bgm.play()

## UI/登场音效：AudioSys 预加载名单固定（shoot/explosion/…），新音效走 main 自有小池；
## 素材缺失记 null 静默跳过，不报错。
func _play_ui_sfx(sfx_name: String, vol_db: float = -6.0) -> void:
	if not _ui_streams.has(sfx_name):
		var p := "res://assets/audio/%s.wav" % sfx_name
		if not ResourceLoader.exists(p):
			_ui_streams[sfx_name] = null
			return
		_ui_streams[sfx_name] = load(p)
	var st: AudioStream = _ui_streams[sfx_name]
	if st == null or _ui_pool.is_empty():
		return
	_ui_idx = (_ui_idx + 1) % _ui_pool.size()
	var pl: AudioStreamPlayer = _ui_pool[_ui_idx]
	pl.stream = st
	pl.volume_db = vol_db
	pl.play()

func _show_dialog(text: String, cb: Callable) -> void:
	state = "dialog"
	_dialog_cb = cb
	_lbl_dialog.text = text + "\n（点击画面或按跳跃键继续）"
	_dialog_panel.visible = true

func _advance_dialog() -> void:
	if state != "dialog":
		return
	_play_ui_sfx("ui_confirm", -7.0)
	_dialog_panel.visible = false
	var cb := _dialog_cb
	_dialog_cb = Callable()
	if cb.is_valid():
		cb.call()

func _set_boss_bar(v: bool) -> void:
	_boss_bar.visible = v
	# Boss 条出现在顶部 VBox 里会把整列撑高约 30px，目标行是固定 y=86——两者等高重叠（终检实测）；
	# Boss 战时把目标行下移让位，战后复位
	_lbl_obj.position.y = 118.0 if v else 86.0

func _on_boss_activated(boss) -> void:
	var bd: Dictionary = Data.BOSSES[boss.boss_id]
	_play_ui_sfx("boss_intro", -5.0) # 登场号角/警报（只配音，不加任何弱点提示）
	_center_msg("⚠ " + String(bd["name"]) + " ⚠") # 只报名字，弱点打法让玩家自己探索（用户拍板）
	_set_boss_bar(true)
	_lbl_boss.text = String(Data.BOSSES[boss.boss_id]["name"])

func _on_boss_defeated() -> void:
	_set_boss_bar(false)
	await get_tree().create_timer(1.5).timeout
	if state != "playing" or not is_instance_valid(player) or not player.alive:
		return
	_add_score(1000)
	var rating := _compute_rating()
	_last_rating = rating
	cleared_levels[level_index] = true
	if level_index + 1 < Data.LEVELS.size():
		unlocked_max = maxi(unlocked_max, level_index + 1)
	var rank := {"S": 4, "A": 3, "B": 2, "C": 1}
	if int(rank[rating]) > int(rank.get(String(level_ratings.get(level_index, "")), 0)):
		level_ratings[level_index] = rating
	_save_hi()
	_center_msg("过关！ +1000 · 评级 %s" % rating)
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

## 通关评级公式（0–6 分制）：用时/剩余命数/关内得分（含过关 +1000）各 0–2 分。
## 用时 par = 关长×0.55 秒（按 7.5m/s 移速与多路线绕行估的基准）：≤par 2 分、≤1.5par 1 分。
## 命数：剩余 ≥3 为 2 分、≥1 为 1 分；∞ 命固定 1 分（不惩罚也不白拿满分）。
## 得分 par = 2600 + 关长×4：≥par 2 分、≥0.6par 1 分。总分 ≥5 S、4 A、2–3 B、其余 C。
func _compute_rating() -> String:
	var length := float(Data.LEVELS[level_index]["length"])
	var par_time := length * 0.55
	var t_pts := 2 if _level_time <= par_time else (1 if _level_time <= par_time * 1.5 else 0)
	var l_pts := 1 if lives_inf else (2 if lives >= 3 else (1 if lives >= 1 else 0))
	var gain := score - _level_start_score
	var par_score := 2600.0 + length * 4.0
	var s_pts := 2 if gain >= par_score else (1 if gain >= par_score * 0.6 else 0)
	var total := t_pts + l_pts + s_pts
	return "S" if total >= 5 else ("A" if total >= 4 else ("B" if total >= 2 else "C"))

func _on_player_death() -> void:
	AudioSys.play("die", -3.0, 0.8) # 玩家死亡音（die 在 AudioSys 名单内；降调放慢与敌兵死亡区分）
	_update_hud()
	await get_tree().create_timer(1.3).timeout
	if state != "playing":
		return
	if not lives_inf:
		lives -= 1
	_update_hud()
	if lives_inf or lives > 0:
		# 原地复活（用户拍板）：死在哪就在哪站起来，1.5 秒无敌，不再回检查点重打
		var spot: Vector3 = player.death_pos
		spot.y = current_level.get_support_y(spot.x, spot.z, 999.0)
		player.respawn_player(spot)
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

## 击杀回调（level 在敌人死亡的同一调用栈内触发）：飘分 + 连杀计数 + 图鉴遭遇登记。
## 计分本身仍走 _add_score（on_score 先行调用），这里不重复加分；连杀不设倍率（守对标计分）。
func _on_kill(pts: int, type: String, pos: Vector3) -> void:
	_on_encounter(type)
	_combo += 1
	_combo_t = COMBO_WINDOW
	if _combo > 0 and _combo % 5 == 0:
		_center_msg("%d 连杀!" % _combo)
	for f in _floats:
		if float(f["t"]) >= 1.0:
			f["t"] = 0.0
			f["pos"] = pos + Vector3(0, 1.9, 0)
			var lb := f["label"] as Label
			lb.text = "+%d" % pts if _combo < 3 else "+%d  ×%d连杀" % [pts, _combo]
			lb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if _combo < 3 else Color(1.0, 0.55, 0.2))
			lb.visible = true
			return

## 图鉴遭遇登记（敌人进入警觉或被击杀时由 level 触发），变化即落盘
func _on_encounter(type: String) -> void:
	if type != "" and not encountered.has(type):
		encountered[type] = true
		_save_hi()

func _update_floats(delta: float) -> void:
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_combo = 0
	if not is_instance_valid(camera):
		return
	for f in _floats:
		var t := float(f["t"])
		if t >= 1.0:
			continue
		t += delta
		f["t"] = t
		var lb := f["label"] as Label
		if t >= 1.0:
			lb.visible = false
			continue
		var p: Vector3 = f["pos"]
		p.y += t * 1.1
		if camera.is_position_behind(p):
			lb.visible = false
			continue
		lb.visible = true
		var sp := camera.unproject_position(p)
		lb.position = sp - Vector2(24, 12)
		lb.modulate.a = 1.0 - t * t

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
## 命中顿帧：玩家子弹命中敌人时短暂压慢全局时间（0.08 倍 ≈42ms 真实时间），
## 冷却 160ms 防连发叠加；用真实时钟计时，time_scale 本身不影响恢复
func _on_enemy_hitstop() -> void:
	var n := Time.get_ticks_msec()
	if n >= _hitstop_next:
		Engine.time_scale = 0.08
		_hitstop_end = n + 42
		_hitstop_next = n + 160

func _process(dt: float) -> void:
	if _hitstop_end > 0 and Time.get_ticks_msec() >= _hitstop_end:
		Engine.time_scale = 1.0
		_hitstop_end = 0
	dt = minf(dt, 0.05) # 钳制帧步长：低帧率/卡顿设备上不快进（软件渲染实测教训）
	_update_click_hint(dt) # 点击引导在所有状态下统一更新：切状态自动淡出、游玩中未锁定自动亮起
	if state == "menu":
		_menu_time += dt
		if is_instance_valid(_menu_player):
			_menu_player.facing = PI * 0.92 + sin(_menu_time * 0.3) * 0.14
			_menu_player._sync_visual(0.0, false, false)
		return
	if state != "playing" or not is_instance_valid(player) or current_level == null:
		return
	_level_time += dt
	var aiming := Input.is_action_pressed("aim")
	var shooting := Input.is_action_pressed("shoot") or _touch_shoot
	if _touch_shoot:
		aiming = true
	# 准星变色沿用同一 aiming/shooting 判定：瞄准或开火时橙红，平时白色半透
	_cross.modulate = Color(1.0, 0.45, 0.22, 0.98) if (aiming or shooting) else Color(1, 1, 1, 0.85)
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
		"on_enemy_hit": Callable(self, "_on_enemy_hitstop"),
		"terrain_h": Callable(current_level, "terrain_h"),
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
	# 受击红闪衰减
	if _hurt_a > 0.0:
		_hurt_a = maxf(0.0, _hurt_a - dt * 1.6)
		_hurt_rect.color = Color(0.85, 0.04, 0.04, _hurt_a)
	# 阶段目标 + 目标指引：按推进比例切换目标文案，末段显示距 Boss 的直线距离
	var ratio := current_level.player_dist(player) / maxf(1.0, float(current_level.length))
	var obj := ""
	if current_level.boss_activated and current_level.boss and current_level.boss.alive:
		var bd := player.global_position.distance_to(current_level.boss.global_position)
		obj = "目标：摧毁 %s（%d 米）" % [String(Data.BOSSES[current_level.boss.boss_id]["name"]), int(bd)]
	else:
		var objs: Array = Data.LEVELS[level_index].get("objs", [])
		for o in objs:
			if ratio >= float(o[0]):
				obj = "目标：" + String(o[1])
	if obj != _obj_text:
		_obj_text = obj
		_lbl_obj.text = obj
	_update_floats(dt)
	_update_edge_arrow()
	_update_hud()

## 边缘箭头：目标点依次取——已激活的 Boss → 最近的未开门感应器（基地关）→ Boss 垫（推进方向）。
## 目标在屏内（留 46px 边距）时隐藏；屏外时把箭头钳到边缘并按中心→目标方向旋转。
## 相机背后时 unproject 会镜像，x 取镜像、y 压到下缘再走同一钳制逻辑。
func _update_edge_arrow() -> void:
	if not is_instance_valid(camera) or current_level == null or not is_instance_valid(player):
		_edge_arrow.visible = false
		return
	var target := Vector3.ZERO
	if current_level.boss_activated and current_level.boss and current_level.boss.alive:
		target = current_level.boss.global_position + Vector3(0, 3.0, 0)
	else:
		var best := 1.0e18
		var found := false
		for s in current_level.sensors:
			if s.alive:
				var d: float = player.global_position.distance_squared_to(s.pos)
				if d < best:
					best = d
					target = s.pos
					found = true
		if not found:
			target = Vector3(0, current_level.terrain_h(0.0, -float(current_level.length) + 10.0) + 3.0, -float(current_level.length) + 10.0)
	var vp := get_viewport().get_visible_rect().size
	var behind := camera.is_position_behind(target)
	var sp := camera.unproject_position(target)
	if behind:
		sp = Vector2(vp.x - sp.x, vp.y + 200.0)
	var margin := 46.0
	if not behind and sp.x >= margin and sp.x <= vp.x - margin and sp.y >= margin and sp.y <= vp.y - margin:
		_edge_arrow.visible = false
		return
	var center := vp * 0.5
	var dir := sp - center
	if dir.length() < 1.0:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	var t := 1.0e9
	if absf(dir.x) > 0.001:
		t = minf(t, (vp.x * 0.5 - margin) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (vp.y * 0.5 - margin) / absf(dir.y))
	var pos := center + dir * t
	_edge_arrow.visible = true
	_edge_arrow.pivot_offset = _edge_arrow.size * 0.5
	_edge_arrow.position = pos - _edge_arrow.size * 0.5
	_edge_arrow.rotation = dir.angle()

func _menu_env() -> void:
	var env := world_env.environment
	var sky_res := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/hdri/jungle_day.hdr") # 菜单天空与第1关统一（终检：旧 forest.hdr 已退役）
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
