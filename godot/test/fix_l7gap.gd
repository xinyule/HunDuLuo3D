extends SceneTree

## 补充探针：L7 鹰徽1（-24,-120）可达性复核——主探针直线+±3m 侧移找不到货架缺口，
## 本探针按真人路线走：中巷 → 货架缺口（左列 sn%4==2 缺口，z≈-112.6）→ 侧巷 → 鹰徽点。
## 三段实走全通即判可达（缺口位置由 _theme_hangar 货架排布公式推得，并以实走验证）。
## 运行：godot --headless --path . --script res://test/fix_l7gap.gd --fixed-fps 60

var _main: Node
var _frame := 0
var _phase := 0
var _level = null
var _player = null
var _legs: Array = []
var _leg_i := 0
var _stall := 0
var _last_d := 1e9
var _frames := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)
	_legs = [Vector2(0.0, -112.6), Vector2(-24.0, -112.6), Vector2(-24.0, -120.0)]

func _teleport(x: float, z: float) -> void:
	var y: float = _level.get_support_y(x, z, 999.0)
	_player.global_position = Vector3(x, y, z)
	_player.vy = 0.0
	_player.grounded = true

func _on_frame() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame == 30:
				_main._set_char("bill")
				_main.start_game()
				_main._load_level(6) # L7 仓库
				_main._advance_dialog()
				_level = _main.current_level
				_player = _main.player
				_player.barrier = 99999.0
				_main.set_process(false)
				_teleport(0.0, -104.0)
				_phase = 1
		1:
			var t: Vector2 = _legs[_leg_i]
			var p: Vector3 = _player.global_position
			var dx := t.x - p.x
			var dz := t.y - p.z
			var d := sqrt(dx * dx + dz * dz)
			_frames += 1
			if d < _last_d - 0.005:
				_last_d = d
				_stall = 0
			else:
				_stall += 1
			if d < 0.6:
				print("  leg %d 到达 (%.1f, %.1f)" % [_leg_i + 1, t.x, t.y])
				_leg_i += 1
				_last_d = 1e9
				_stall = 0
				if _leg_i >= _legs.size():
					var pp: Vector3 = _player.global_position
					var fd := Vector2(pp.x + 24.0, pp.z + 120.0).length()
					print("L7GAP RESULT: %s （终点距鹰徽 %.2f m）" % ["PASS" if fd < 1.25 else "FAIL", fd])
					quit(0 if fd < 1.25 else 1)
					return
			elif _stall > 240 or _frames > 3600:
				print("L7GAP RESULT: FAIL （第 %d 段 stall 于 (%.1f, %.1f)，距段终点 %.1f）" % [_leg_i + 1, p.x, p.z, d])
				quit(1)
				return
			else:
				var yaw := atan2(dx, dz)
				var snap := {"move": Vector2(0, -1), "jump": false, "prone": false, "run": true}
				_player.update_player(1.0 / 60.0, snap, _level, yaw, 0.0, false)
