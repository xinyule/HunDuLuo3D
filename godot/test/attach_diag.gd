extends SceneTree

## 挂件串位决定性探针：同一帧对比「骨骼全局姿态 / BoneAttachment 全局变换 / 子节点实际全局位置」
## 三种条件：A 真实游玩帧；B AimModifier 施加 hip_yaw；C 冻结主循环（复刻 bone_probe2 条件）
## 运行：godot --headless --path . --script res://test/attach_diag.gd --fixed-fps 60
##   或：xvfb-run -a godot --path . --script res://test/attach_diag.gd --rendering-driver opengl3 --resolution 1280x720

var _main: Node
var _frame := 0
var _phase := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://main.tscn")
	_main = ps.instantiate()
	root.add_child(_main)
	process_frame.connect(_on)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r: Skeleton3D = _find_skel(c)
		if r:
			return r
	return null

func _find_ba(n: Node, bname: String) -> BoneAttachment3D:
	if n is BoneAttachment3D and (n as BoneAttachment3D).bone_name == bname:
		return n as BoneAttachment3D
	for c in n.get_children():
		var r: BoneAttachment3D = _find_ba(c, bname)
		if r:
			return r
	return null

func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

func _report(tag: String) -> void:
	var p: Node3D = _main.player
	var skel: Skeleton3D = _find_skel(p)
	var pp: Vector3 = p.global_position
	print("=== %s (player facing=%.2f) ===" % [tag, p.facing])
	var fwd := Vector3(sin(p.facing), 0, cos(p.facing))
	var fidx: int = skel.find_bone("DEF-foot.R")
	if fidx >= 0:
		var fpose: Transform3D = skel.global_transform * skel.get_bone_global_pose(fidx)
		print("DEF-foot.R pose_origin_rel=%s basisY=%s basisZ=%s" % [_v(fpose.origin - pp), _v(fpose.basis.y.normalized()), _v(fpose.basis.z.normalized())])
	for pair in [["DEF-thigh.R", "DEF-shin.R"], ["DEF-shin.R", "DEF-foot.R"], ["DEF-thigh.L", "DEF-shin.L"], ["DEF-shin.L", "DEF-foot.L"], ["DEF-head", ""]]:
		var bname: String = pair[0]
		var child_joint: String = pair[1]
		var idx: int = skel.find_bone(bname)
		if idx < 0:
			print("%s NOT FOUND" % bname)
			continue
		var pose: Transform3D = skel.global_transform * skel.get_bone_global_pose(idx)
		var dir := Vector3.ZERO
		if child_joint != "":
			var cidx: int = skel.find_bone(child_joint)
			var cpose: Transform3D = skel.global_transform * skel.get_bone_global_pose(cidx)
			dir = (cpose.origin - pose.origin).normalized()
		var ba: BoneAttachment3D = _find_ba(p, bname)
		print("%s pose_origin_rel=%s basisY=%s joint_dir=%s basisY·dir=%.2f basis(-Y)·dir=%.2f" % [
			bname, _v(pose.origin - pp), _v(pose.basis.y.normalized()), _v(dir),
			pose.basis.y.normalized().dot(dir), (-pose.basis.y.normalized()).dot(dir)])
		if ba == null:
			print("  BA NOT FOUND")
			continue
		var bag: Transform3D = ba.global_transform
		print("  BA origin_rel=%s basisY=%s idx=%d basis==pose_basis: X %.2f Y %.2f Z %.2f (与 pose basis 各列点积，1=同向)" % [
			_v(bag.origin - pp), _v(bag.basis.y.normalized()), ba.get_bone_idx(),
			bag.basis.x.normalized().dot(pose.basis.x.normalized()),
			bag.basis.y.normalized().dot(pose.basis.y.normalized()),
			bag.basis.z.normalized().dot(pose.basis.z.normalized())])
		for c in ba.get_children():
			if c is Node3D:
				var cn := c as Node3D
				var actual: Vector3 = cn.global_position - pp
				var exp_ba: Vector3 = bag * cn.position - pp
				var exp_pose: Vector3 = pose * cn.position - pp
				var front: float = Vector3(actual.x, 0, actual.z).dot(fwd) - Vector3(pose.origin.x - pp.x, 0, pose.origin.z - pp.z).dot(fwd)
				print("  child local=%s actual_rel=%s exp_by_BA=%s exp_by_pose=%s front_of_bone=%.2f" % [
					_v(cn.position), _v(actual), _v(exp_ba), _v(exp_pose), front])

func _on() -> void:
	_frame += 1
	match _phase:
		0:
			if _frame == 30:
				_main._set_char("bill")
				_main.start_game()
				_main._advance_dialog()
				_main.player.invuln = 99999.0
				_phase = 1
		1:
			if _frame == 90:
				_report("A live-frame")
				_main.player._aim_mod.hip_yaw = 0.6
				_phase = 2
		2:
			if _frame == 110:
				_report("B hip_yaw=0.6")
				_main.player._aim_mod.hip_yaw = 0.0
				_main.set_process(false)
				_phase = 3
		3:
			if _frame == 140:
				_report("C main-frozen")
				print("ATTACH DIAG DONE")
				quit(0)
