class_name AimModifier
extends SkeletonModifier3D

## 瞄准俯仰修正：给胸骨叠加俯仰旋转，让持枪上身跟随准星上下
## （动画片段本身不带俯仰，靠骨骼后处理叠加，引擎推荐做法）

var pitch := 0.0
var bone_name := "DEF-spine.003"

func _process_modification() -> void:
	if is_equal_approx(pitch, 0.0):
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		return
	var q := Quaternion(Vector3.RIGHT, pitch)
	skel.set_bone_pose_rotation(idx, q * skel.get_bone_pose_rotation(idx))
