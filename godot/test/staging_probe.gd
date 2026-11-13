extends SceneTree

## 暂存 GLB 结构探针：骨名/片段/身高逐个核对（headless）
## 运行：godot --headless --path . --script res://test/staging_probe.gd --fixed-fps 60

const NAMES := ["bill", "lance", "enemy_rifleman", "enemy_runner", "enemy_sniper", "enemy_mortar", "enemy_garth", "enemy_langel", "enemy_akbar", "gasmask"]
const NEED_BONES := ["pelvis", "spine_01", "spine_02", "spine_03", "hand_r", "head"]
const NEED_CLIPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Pistol_Shoot", "Hit_Chest", "Death01", "Jump", "Jump_Land", "Roll", "Swim_Idle"]

func _find(n: Node, cls: String) -> Node:
	if (cls == "skel" and n is Skeleton3D) or (cls == "anim" and n is AnimationPlayer):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _initialize() -> void:
	var bad := 0
	for nm in NAMES:
		var ps: PackedScene = load("res://assets/char_staging/%s.glb" % nm)
		if ps == null:
			print("PROBE ", nm, " LOAD FAIL")
			bad += 1
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		await process_frame
		await process_frame
		var skel := _find(inst, "skel") as Skeleton3D
		var anim := _find(inst, "anim") as AnimationPlayer
		var bones_ok := true
		if skel:
			for b in NEED_BONES:
				if skel.find_bone(b) < 0:
					bones_ok = false
					print("PROBE ", nm, " MISSING BONE ", b)
		else:
			bones_ok = false
			print("PROBE ", nm, " NO SKELETON")
		var clips: Array = []
		if anim:
			clips = anim.get_animation_list()
		var miss: Array = []
		for c in NEED_CLIPS:
			if not clips.has(c):
				miss.append(c)
		# 身高：合并全部网格 AABB（实例在原点、无变换）
		var aabb := AABB()
		var first := true
		var stack: Array = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var ab := mi.global_transform * mi.get_aabb()
				if first:
					aabb = ab
					first = false
				else:
					aabb = aabb.merge(ab)
		print("PROBE ", nm, " bones_ok=", bones_ok, " clips=", clips.size(), " miss=", miss, " h=", snappedf(aabb.size.y, 0.01), " zrange=", snappedf(aabb.position.z, 0.01), "..", snappedf(aabb.end.z, 0.01))
		if not bones_ok or not miss.is_empty():
			bad += 1
		inst.queue_free()
	print("PROBE DONE bad=", bad)
	quit(0 if bad == 0 else 1)
