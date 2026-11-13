extends SceneTree

## 4A 新兵种验收：功能断言（盾牌正面拦截/中心点爆炸可伤/背面可伤、掷弹兵一发死）
## + 实机截图（掷弹兵掷雷瞬间、盾牌兵正面挡弹火花、噪声石像、坦克小核心）。
## 慢放拍法同 fx_shot：Engine.time_scale=0.06 让榴弹弧线/火花跨帧可拍。
## 运行：xvfb-run godot --path . --script res://test/newtypes_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0
var _mark := 0
var _shield: Node
var _bomber: Node
var _statue: Node
var _tank: Node
var _thrown := false
var _thrown_frame := 0
var _p3_deadline := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + name)
	print("SNAP ", name)

func _wait(frames: int) -> void:
	_mark = _frame + frames
	_phase += 1

func _fwd_of(e: Node) -> Vector3:
	return Vector3(sin(e.rotation.y), 0.0, cos(e.rotation.y))

func _on_frame() -> void:
	_frame += 1
	var ps = _main.projectiles if _main else null
	if ps and not _thrown and _bomber and is_instance_valid(_bomber):
		if (ps._grenades as Array).size() > 0:
			_thrown = true
			_thrown_frame = _frame
	if _frame < _mark:
		return
	var pl = _main.player
	var lv = _main.current_level
	match _phase:
		0:
			_main.start_game()
			_main._advance_dialog()
			_wait(20)
		1:
			pl.invuln = 999.0
			# ---- 功能断言：盾牌三向受伤 ----
			var sh = lv._spawn_enemy("shield", pl.global_position.x + 3.0, pl.global_position.z - 7.0)
			sh._alert = true
			sh.rotation.y = atan2(pl.global_position.x - sh.global_position.x, pl.global_position.z - sh.global_position.z)
			var fwd := _fwd_of(sh)
			var c: Vector3 = sh.global_position
			sh.on_hit(10, c + fwd * 0.6 + Vector3(0, 1.2, 0))
			print("SHIELD FRONT: hp=", sh.hp, " 期望 30（正面拦截）")
			sh.on_hit(10, c + Vector3(0, 1.0, 0))
			print("SHIELD CENTER(爆炸式): hp=", sh.hp, " 期望 20（全向可伤）")
			sh.on_hit(10, c - fwd * 0.6 + Vector3(0, 1.2, 0))
			print("SHIELD BACK: hp=", sh.hp, " 期望 10（背面可伤）")
			sh.on_hit(999, c + Vector3(0, 1.0, 0))
			# ---- 功能断言：掷弹兵一发死 ----
			var bo = lv._spawn_enemy("bomber", pl.global_position.x - 3.0, pl.global_position.z - 7.0)
			bo.on_hit(34, bo.global_position + Vector3(0, 1.0, 0))
			print("BOMBER ONE-SHOT: alive=", bo.alive, " 期望 false（30hp 吃 34 伤）")
			_wait(5)
		2:
			# ---- 摆拍：盾牌兵正面、掷弹兵侧后、石像与坦克列阵 ----
			_shield = lv._spawn_enemy("shield", pl.global_position.x + 1.2, pl.global_position.z - 6.5)
			_bomber = lv._spawn_enemy("bomber", pl.global_position.x - 2.2, pl.global_position.z - 6.0)
			_statue = lv._spawn_enemy("statue", pl.global_position.x - 6.0, pl.global_position.z - 14.0)
			_tank = lv._spawn_enemy("tank", pl.global_position.x + 6.5, pl.global_position.z - 17.0)
			Engine.time_scale = 0.06
			_p3_deadline = _frame + 1200
			_wait(30)
		3:
			# 等掷弹兵出手、榴弹出手后 14 帧再拍；超时兜底
			if (_thrown and _frame >= _thrown_frame + 14) or _frame > _p3_deadline:
				_snap("new_bomber.png")
				_wait(2)
			else:
				_mark = _frame + 10 # 继续等
		4:
			# 朝盾牌兵胸口连打两发，拍正面挡弹火花
			pl.try_shoot(ps, _shield.global_position + Vector3(0, 1.1, 0))
			_wait(2)
		5:
			pl.try_shoot(ps, _shield.global_position + Vector3(0, 1.1, 0))
			_wait(2)
		6:
			print("SHIELD VISUAL BLOCK: hp=", _shield.hp, "（应仍为 30，正面全挡）")
			_snap("new_shield.png")
			Engine.time_scale = 1.0
			_wait(3)
		7:
			# 近看石像（噪声轮廓）与坦克（小红核心）
			pl.global_position = Vector3(_statue.global_position.x + 1.6, _statue.global_position.y, _statue.global_position.z + 6.5)
			_wait(6)
		8:
			_snap("new_statue.png")
			pl.global_position = Vector3(_tank.global_position.x - 2.0, _tank.global_position.y, _tank.global_position.z + 9.5)
			_wait(6)
		9:
			_snap("new_tank.png")
			print("NEWTYPES SHOT DONE")
			quit(0)
