extends SceneTree

## 终检截图：final_char_*（角色近景）/ final_lv*（关卡代表图）/ final_boss*（Boss 实机关）
## 运行：xvfb-run godot --path . --script res://test/final_shot.gd --rendering-driver opengl3 --resolution 1280x720 -- <mode>
## mode = chars | levels | bosses；机位经 cam_rig（高优先级）在游戏相机之后写入。

var _main: Node
var _rig: Node
var _frame := 0
var _mode := "chars"
var _shots: Array = []
var _si := -1
var _phase := "boot"
var _wait := 0
var _cur_enemy = null
var _pin_pos := Vector3.ZERO
var _pin_on := false
var _cur_dist := 3.0
var _cur_cy_off := 1.25

const OUT := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = String(args[0])
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	_rig = (load("res://test/cam_rig.gd") as GDScript).new()
	root.add_child(_rig)
	process_frame.connect(_on_frame)
	match _mode:
		"chars":
			_shots = ["bill", "lance", "rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar", "bomber", "shield", "statue", "tank"]
		"levels":
			_shots = [1, 2, 3, 4, 5, 6, 7, 8]
		"bosses":
			_shots = [1, 2, 3, 4, 5, 6, 7, 8]
	if args.size() > 1 and String(args[1]).begins_with("only:"):
		var want: Array = String(args[1]).substr(5).split(",")
		var filtered: Array = []
		for s in _shots:
			if want.has(String(s)):
				filtered.append(s)
		_shots = filtered

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	print("SNAP ", name)

func _next() -> void:
	_si += 1
	if _si >= _shots.size():
		print("FINAL SHOTS DONE mode=", _mode)
		quit(0)
		return
	_phase = "setup"
	_wait = 0

func _on_frame() -> void:
	_frame += 1
	match _phase:
		"boot":
			if _frame == 5:
				_rig.cam = _main.camera
				_rig.main_ref = _main
				_next()
		"setup":
			_setup_shot()
		"hold":
			if _pin_on and _cur_enemy != null and is_instance_valid(_cur_enemy):
				_cur_enemy.global_position = _pin_pos # 钉住摆拍位（只钉位置，朝向/动画照常）
				if _mode == "chars":
					# 相机跟到主体正前方（待机朝向随机，正面取景才稳定）
					var ep: Vector3 = _cur_enemy.global_position
					var fwd: Vector3 = _cur_enemy.global_transform.basis.z
					fwd.y = 0.0
					if fwd.length() > 0.01:
						fwd = fwd.normalized()
						_rig.pos = Vector3(ep.x + fwd.x * _cur_dist + 0.4, ep.y + _cur_cy_off, ep.z + fwd.z * _cur_dist)
						_rig.look = Vector3(ep.x, ep.y + _cur_cy_off - 0.1, ep.z)
			_wait -= 1
			if _wait <= 0:
				match _mode:
					"chars": _snap("final_char_%s.png" % String(_shots[_si]))
					"levels": _snap("final_lv%d.png" % int(_shots[_si]))
					"bosses": _snap("final_boss%d.png" % int(_shots[_si]))
				_next()

func _start_level(lv: int) -> void:
	_main.start_game(lv)
	_main._advance_dialog()
	_main.player.invuln = 99999.0 # 用 invuln 不用 barrier：barrier 会罩一层蓝泡遮挡摆拍（反馈批教训）
	_main.ui.visible = false

func _setup_shot() -> void:
	_wait = 55
	_phase = "hold"
	match _mode:
		"chars":
			var t := String(_shots[_si])
			if _si == 0:
				_start_level(0)
			var lvl = _main.current_level
			# 摆拍点扫描：出生点附近找一处无岩石/摆件占位的草地（support 与地形等高=无占位），
			# 主体与相机位都要干净；主体面朝 +z（顺光），相机在 +z 侧
			var sx := 0.0
			var sz := 16.0
			var cands := [Vector2(0, 16), Vector2(8, 22), Vector2(-8, 24), Vector2(14, 8), Vector2(-16, 10), Vector2(4, 26)]
			for c in cands:
				var h1: float = lvl.height(c.x, c.y)
				var s1: float = lvl.get_support_y(c.x, c.y, 999.0)
				var s2: float = lvl.get_support_y(c.x, c.y + 3.2, 999.0)
				var h2: float = lvl.height(c.x, c.y + 3.2)
				if absf(s1 - h1) < 0.05 and absf(s2 - h2) < 0.05:
					sx = c.x
					sz = c.y
					break
			var gy: float = lvl.get_support_y(sx, sz, 999.0)
			if t == "bill" or t == "lance":
				_main._set_char(t)
				# 换角色需重开局才换模型：直接重建玩家
				_main._load_level(0)
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				_main.ui.visible = false
				_main.player.global_position = Vector3(sx, gy, sz)
				_main.player.facing = 0.0
				_rig.pos = Vector3(sx + 0.7, gy + 1.45, sz + 2.7)
				_rig.look = Vector3(sx, gy + 1.15, sz)
			else:
				if _cur_enemy != null and is_instance_valid(_cur_enemy):
					_cur_enemy.destroy_enemy()
					lvl.enemies.erase(_cur_enemy)
				_cur_enemy = lvl._spawn_enemy(t, sx, sz)
				_pin_pos = _cur_enemy.global_position
				_pin_on = true
				# 玩家站在相机一侧（+z），让敌人面朝镜头
				_main.player.global_position = Vector3(sx, gy, sz + 6.0)
				var ey: float = _cur_enemy.global_position.y
				var dist := 3.0
				var cy := ey + 1.25
				_cur_cy_off = 1.25
				if t == "statue":
					dist = 6.5
					cy = ey + 1.9
					_cur_cy_off = 1.9
				elif t == "tank":
					dist = 8.5
					cy = ey + 1.5
					_cur_cy_off = 1.5
				_cur_dist = dist
				_rig.pos = Vector3(sx + 0.9, cy, sz + dist)
				_rig.look = Vector3(sx, cy - 0.1, sz)
		"levels":
			var lv := int(_shots[_si])
			_start_level(lv - 1)
			var lvl2 = _main.current_level
			var d: Dictionary = Data.LEVELS[lv - 1]
			var dist := float(d["length"]) * 0.32
			var pz := 26.0 - dist
			var py: float = lvl2.get_support_y(0.0, pz, 999.0)
			_main.player.global_position = Vector3(0.0, py, pz)
			if String(d["theme"]) == "base":
				# 室内关：相机进走廊内（高位机位会撞进天花板夹层）
				_rig.pos = Vector3(5.0, py + 3.0, pz + 8.0)
				_rig.look = Vector3(-1.5, py + 1.2, pz - 10.0)
			else:
				_rig.pos = Vector3(9.0, py + 5.5, pz + 13.0)
				_rig.look = Vector3(-2.0, py + 0.5, pz - 26.0)
			_wait = 70
		"bosses":
			var lv3 := int(_shots[_si])
			_start_level(lv3 - 1)
			_main.ui.visible = true # Boss 图保留 HUD（血条只报名字，正好入镜核查）
			var lvl3o = _main.current_level
			_main.player.global_position = Vector3(0.0, lvl3o.get_support_y(0.0, lvl3o.boss_z + 20.0, 999.0), lvl3o.boss_z + 20.0)
			var bz: float = lvl3o.boss_z
			var by: float = lvl3o.boss_y
			var bd := 19.0
			if lv3 == 8:
				bd = 24.0
			_rig.pos = Vector3(10.5, by + 4.5, bz + bd)
			_rig.look = Vector3(0.0, by + 2.6, bz)
			_wait = 110
