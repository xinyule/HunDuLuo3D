extends Node

## contentb_shot 的相机执行节点：process_priority 拉满，在 main 的相机逻辑之后运行，
## 每帧最后写相机位姿（否则自由机位会被游戏相机覆盖）。

var cam: Camera3D
var pos := Vector3.ZERO
var look := Vector3.ZERO
var main_ref: Node
var follow_falcon := false

func _ready() -> void:
	process_priority = 1000

func _process(_dt: float) -> void:
	if cam == null:
		return
	if follow_falcon and main_ref != null and main_ref.current_level and main_ref.current_level.pickups:
		var fs: Array = main_ref.current_level.pickups._falcons
		if fs.size() > 0:
			var g: Node3D = fs[0]["group"]
			var fp: Vector3 = g.global_position
			cam.global_position = fp + Vector3(2.8, 0.55, 3.4)
			cam.look_at(fp, Vector3.UP)
			return
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
