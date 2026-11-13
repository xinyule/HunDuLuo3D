extends SceneTree

## 战斗反馈批验收截图：开火瞬间（枪口火光+弹壳+点光）→ 弹丸飞行（亮黄曳光 vs 橙红敌弹+拖尾）
## → 炮弹爆炸全套（粒子火球/烟尘/火花+冲击波环）。另打印各表现池的活条目数作数值证据。
## 慢放拍法：软件渲染帧率太低（约 0.4s/帧），瞬时效果（火光 0.05s）会落进帧缝——
## 开火/飞行/爆炸段把 Engine.time_scale 压到 0.06 让效果跨帧存活，拍完恢复；玩家用 invuln 取证不开护盾泡。
## 运行：xvfb-run godot --path . --script res://test/fx_shot.gd --rendering-driver opengl3 --resolution 1280x720

const DIR := "/home/hatch/workspace/HunDuLuo3D_work/shots/"

var _main: Node
var _frame := 0
var _phase := 0
var _mark := 0

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

func _on_frame() -> void:
	_frame += 1
	if _frame < _mark:
		return
	var ps = _main.projectiles
	match _phase:
		0:
			_main.start_game()
			_main._advance_dialog()
			_wait(20)
		1:
			var pl = _main.player
			pl.invuln = 999.0 # 无敌取证，不开 barrier 泡（蓝罩会遮挡火光/爆炸）
			# 玩家前方近处摆步枪兵与迫击炮兵
			var lv = _main.current_level
			lv._spawn_enemy("rifleman", pl.global_position.x + 0.8, pl.global_position.z - 6.5)
			lv._spawn_enemy("mortar", pl.global_position.x - 3.0, pl.global_position.z - 15.0)
			Engine.time_scale = 0.06 # 慢放：让 0.05s 的枪口火光跨帧可拍
			_wait(10)
		2:
			# 开火瞬间：朝步枪兵打一发（下一帧渲染里火光/弹壳/曳光都在）
			var pl2 = _main.player
			var e = _main.current_level.enemies[_main.current_level.enemies.size() - 2]
			pl2.try_shoot(ps, e.global_position + Vector3(0, 1.2, 0))
			_wait(1)
		3:
			print("FX fire: flashes=", ps._flashes.size(), " shells=", ps._shells.size(), " bullets=", ps._bullets.size())
			_snap("fx_fire.png")
			_wait(1)
		4:
			# 弹丸飞行：慢放下连射 + 敌方橙红光弹迎面（第二发为重弹）
			var pl3 = _main.player
			for i in 3:
				pl3.fire_timer = 0.0
				pl3.try_shoot(ps, pl3.global_position + Vector3(0.5, 1.3, -30))
			var from: Vector3 = pl3.global_position + Vector3(-2.0, 1.6, -13.0)
			ps.spawn_orb(from, (pl3.global_position + Vector3(0, 1.2, 0) - from).normalized(), 14.0, 1)
			ps.spawn_orb(from + Vector3(1.5, 0.4, -3.0), (pl3.global_position + Vector3(0, 1.0, 0) - from).normalized(), 14.0, 1, 2.0)
			_wait(3)
		5:
			print("FX tracer: bullets=", ps._bullets.size(), " orbs=", ps._orbs.size(), " grenades=", ps._grenades.size())
			_snap("fx_tracer.png")
			Engine.time_scale = 1.0
			_wait(10)
		6:
			# 爆炸全套：玩家前方直调一次标准爆炸（半径 2.6，与迫击炮/油桶同级）
			# 慢放拍：真实速度下 0.42s/帧会错过火球期，0.06 慢放下每帧约 0.025 游戏秒
			Engine.time_scale = 0.06
			var pl4 = _main.player
			ps.spawn_explosion_fx(pl4.global_position + Vector3(1.5, 0.8, -7.0), 2.6)
			_wait(12) # ≈0.3 游戏秒：火球+冲击波环扩张中
		7:
			print("FX boom: rings=", ps._rings.size(), " fx=", ps._fx.size())
			_snap("fx_boom.png")
			_wait(30) # ≈+0.75 游戏秒：烟尘主导
		8:
			_snap("fx_boom2.png")
			Engine.time_scale = 1.0
			print("FX SHOT DONE")
			quit(0)
