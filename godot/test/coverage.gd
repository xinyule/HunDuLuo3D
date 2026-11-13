extends SceneTree

## 覆盖冒烟：8 关依次建关 + 全部敌人类型生成 + Boss 激活攻击，无脚本错误即过
## 运行：godot --headless --path . --script res://test/coverage.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := 0
var _wait_until := 0
var _level := 0
var _done := false

const TYPES := ["rifleman", "runner", "sniper", "mortar", "garth", "langel", "akbar", "statue", "turret", "roller", "spore", "tank"]

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frame += 1
	# 1.1.0 探针适配：每关生成是跨帧协程，等 dialog 落地再走原阶段（原「+5 帧」与同帧 advance 不再成立）
	if _phase == 1 and _main.state != "dialog":
		return
	if _done or _frame < _wait_until:
		return
	match _phase:
		0:
			_main.start_game() # 进第1关 dialog
			_phase = 1
			_wait_until = _frame + 5
		1:
			# 当前 _level 关：进游戏、生成全部敌人、传送中段与 Boss 区
			_main._advance_dialog()
			_main.player.barrier = 99999.0
			var lv = _main.current_level
			for i in TYPES.size():
				lv._spawn_enemy(TYPES[i], -8.0 + float(i) * 1.5, _main.player.global_position.z - 12.0)
			_main.player.global_position = Vector3(0, lv.get_support_y(0, -60, 999.0), -60)
			_phase = 2
			_wait_until = _frame + 90
		2:
			var lv = _main.current_level
			_main.player.global_position = Vector3(0, lv.boss_y, -(lv.length - 41.0) + 26.0)
			_phase = 3
			_wait_until = _frame + 150 # Boss 攻击两三轮
		3:
			var lv = _main.current_level
			print("LEVEL OK %d %s boss_active=%s enemies=%d" % [_level + 1, String(lv.data["name"]), str(lv.boss_activated), lv.enemies.size()])
			_level += 1
			if _level >= 8:
				_done = true
				print("COVERAGE DONE")
				quit(0)
				return
			_main._load_level(_level)
			_phase = 1
			_wait_until = _frame + 5
