extends SceneTree

## 掩体穿透回归测试（v3.0.3 三修：硬挡/木穿/植被不挡）：
## ① 子弹穿木箱命中后面的敌人 ② 穿透伤害减半 ③ 木箱第一发不烂、第二发打烂且碰撞失效
## ④ 实体岩体挡住子弹、后面的敌人无伤
## 运行：godot --headless --path . --script res://test/cover.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := 0
var _fails := 0
var _crate_col: Dictionary = {}
var _e1 = null
var _e2 = null
var _e1_max := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _check(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + label)
	if not cond:
		_fails += 1

func _shoot_at(p: Vector3) -> void:
	_main.player.fire_timer = 0.0
	_main.player.try_shoot(_main.projectiles, p)

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame > 30:
				_main.start_game()
				_main._advance_dialog()
				_main.player.barrier = 99999.0
				_main.player.global_position = Vector3(0, 0, 20)
				var lv = _main.current_level
				lv._add_crate(0.0, 14.0, 1.1, 1.1, 1.6, Util.pbr(Color(1, 1, 1), "planks", 0.9))
				_crate_col = lv.colliders[lv.colliders.size() - 1]
				_e1 = lv._spawn_enemy("rifleman", 0.0, 10.0)
				_e1_max = _e1.max_hp
				_shoot_at(Vector3(0, 1.0, 10))
				_phase = 1
		1:
			if _frame > 70:
				_check(_e1.hp < _e1_max, "子弹穿过木箱命中敌人 (hp %d/%d)" % [_e1.hp, _e1_max])
				_check(_e1.hp > _e1_max - 34, "穿透伤害已减半 (loss=%d < 34)" % (_e1_max - _e1.hp))
				_check(not bool(_crate_col.get("disabled", false)), "木箱第一发未烂 (hp 40 > 子弹 34)")
				_shoot_at(Vector3(0, 0.8, 14))
				_phase = 2
		2:
			if _frame > 110:
				_check(bool(_crate_col.get("disabled", false)), "木箱第二发打烂、碰撞失效")
				var lv = _main.current_level
				var r := RandomNumberGenerator.new()
				r.seed = 777
				lv._boulder(3.0, 14.0, r)
				_e2 = lv._spawn_enemy("rifleman", 3.0, 10.0)
				_main.player.global_position = Vector3(3, 0, 20)
				_shoot_at(Vector3(3, 1.0, 10))
				_phase = 3
		3:
			if _frame > 150:
				_check(_e2.hp == _e2.max_hp, "岩体挡住子弹、敌人无伤 (hp %d/%d)" % [_e2.hp, _e2.max_hp])
				if _fails == 0:
					print("COVER PASS")
					quit(0)
				else:
					print("COVER FAIL x", _fails)
					quit(1)
