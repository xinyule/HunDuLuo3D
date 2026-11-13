class_name AimModifier
extends SkeletonModifier3D

## 瞄准后处理：给胸骨叠加俯仰旋转让持枪上身跟随准星上下；
## 再给髋骨叠加偏航、脊柱反向补偿——瞄准移动时脚朝行进方向、上身仍对准星，
## 避免「人朝前、腿横着滑」的假动作（动画片段本身不带这些，靠骨骼后处理叠加）

var pitch := 0.0
var hip_yaw := 0.0
var bone_name := "spine_03" # MPFB game_engine 骨名（旧 UAL 为 DEF-spine.003）

func _apply(skel: Skeleton3D, bname: String, q: Quaternion) -> void:
	var idx := skel.find_bone(bname)
	if idx < 0:
		return
	skel.set_bone_pose_rotation(idx, q * skel.get_bone_pose_rotation(idx))

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if not is_equal_approx(hip_yaw, 0.0):
		# 髋朝行进方向转，脊柱两节反向转回——上身（持枪/头部）保持瞄准朝向
		_apply(skel, "pelvis", Quaternion(Vector3.UP, hip_yaw))
		_apply(skel, "spine_01", Quaternion(Vector3.UP, -hip_yaw * 0.5))
		_apply(skel, "spine_02", Quaternion(Vector3.UP, -hip_yaw * 0.5))
	if not is_equal_approx(pitch, 0.0):
		_apply(skel, bone_name, Quaternion(Vector3.RIGHT, pitch))
