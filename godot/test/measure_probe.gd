extends SceneTree

## 模型尺寸测量：按骨骼主导权重把顶点变换到骨骼本地空间，打印头/大腿/小腿/脚的真实包围
## 运行：godot --headless --path . --script res://test/measure_probe.gd

var _frame := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://assets/char/ual.glb")
	var model := ps.instantiate() as Node3D
	root.add_child(model)
	process_frame.connect(_on.bind(model))

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _find_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find_meshes(c, out)

func _on(model: Node3D) -> void:
	_frame += 1
	if _frame < 3:
		return
	process_frame.disconnect(_on)
	var skel := _find_skel(model)
	var meshes: Array = []
	_find_meshes(model, meshes)
	print("skeleton bones: ", skel.get_bone_count())
	var targets := ["DEF-head", "DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-toe.L", "DEF-hips", "DEF-spine.002"]
	var bidx := {}
	for t in targets:
		bidx[t] = skel.find_bone(t)
		var bi: int = bidx[t]
		if bi >= 0:
			var parent := skel.get_bone_parent(bi)
			print(t, " idx=", bi, " rest_origin(local to parent)=", skel.get_bone_rest(bi).origin, " parent=", skel.get_bone_name(parent) if parent >= 0 else "none")
			# 子关节在本骨本地系的位置 = 子骨 rest 的 origin（近似：子骨 rest 是相对父骨的）
			for ci in skel.get_bone_children(bi):
				print("   child ", skel.get_bone_name(ci), " rest_origin=", skel.get_bone_rest(ci).origin)
	# 收集顶点：bone_local 字典 bone_name -> Array[Vector3]
	var pts := {}
	for t in targets:
		pts[t] = []
	var skel_gt: Transform3D = skel.global_transform
	for mi_v in meshes:
		var mi := mi_v as MeshInstance3D
		if mi.mesh == null:
			continue
		var mi_gt: Transform3D = mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty() or weights.is_empty():
				continue
			for vi in verts.size():
				var best_b := -1
				var best_w := 0.0
				for k in 4:
					var w: float = weights[vi * 4 + k]
					if w > best_w:
						best_w = w
						best_b = bones[vi * 4 + k]
				if best_w < 0.4 or best_b < 0:
					continue
				var bname := skel.get_bone_name(best_b)
				if not pts.has(bname):
					continue
				var vw: Vector3 = mi_gt * verts[vi]
				var bl: Vector3 = (skel_gt * skel.get_bone_global_rest(best_b)).affine_inverse() * vw
				(pts[bname] as Array).append(bl)
	# 整脚（foot+toe 两骨顶点）在脚骨系下的包围
	var foot_bi: int = bidx["DEF-foot.L"]
	var foot_inv: Transform3D = (skel_gt * skel.get_bone_global_rest(foot_bi)).affine_inverse()
	var fmn := Vector3(INF, INF, INF)
	var fmx := Vector3(-INF, -INF, -INF)
	for mi_v2 in meshes:
		var mi2 := mi_v2 as MeshInstance3D
		if mi2.mesh == null:
			continue
		var gt2: Transform3D = mi2.global_transform
		for s2 in mi2.mesh.get_surface_count():
			var arr2 := mi2.mesh.surface_get_arrays(s2)
			var verts2: PackedVector3Array = arr2[Mesh.ARRAY_VERTEX]
			var bones2: PackedInt32Array = arr2[Mesh.ARRAY_BONES]
			var weights2: PackedFloat32Array = arr2[Mesh.ARRAY_WEIGHTS]
			if bones2.is_empty():
				continue
			for vi2 in verts2.size():
				var bb := -1
				var bw := 0.0
				for k2 in 4:
					if weights2[vi2 * 4 + k2] > bw:
						bw = weights2[vi2 * 4 + k2]
						bb = bones2[vi2 * 4 + k2]
				if bb < 0 or bw < 0.4:
					continue
				var bn := skel.get_bone_name(bb)
				if bn != "DEF-foot.L" and bn != "DEF-toe.L":
					continue
				var pf: Vector3 = foot_inv * (gt2 * verts2[vi2])
				fmn = fmn.min(pf)
				fmx = fmx.max(pf)
	print("WHOLE FOOT in foot-bone space: min=", fmn, " max=", fmx)
	for t in targets:
		var a: Array = pts[t]
		if a.is_empty():
			print(t, " NO POINTS")
			continue
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for p_v in a:
			var p := p_v as Vector3
			mn = mn.min(p)
			mx = mx.max(p)
		print(t, " n=", a.size(), " min=", mn, " max=", mx)
		# 沿 +Y 分片打印最大 |x| / 前 z / 后 z（头与腿都关心）
		var y0: float = floor(mn.y * 20.0) / 20.0
		var y1: float = mx.y
		var yy := y0
		while yy <= y1:
			var mx_x := 0.0
			var mx_zf := -INF
			var mn_zb := INF
			var cnt := 0
			for p_v in a:
				var p := p_v as Vector3
				if p.y >= yy and p.y < yy + 0.05:
					cnt += 1
					mx_x = max(mx_x, absf(p.x))
					mx_zf = max(mx_zf, p.z)
					mn_zb = min(mn_zb, p.z)
			if cnt > 0:
				print("   y[%.2f,%.2f) n=%d max|x|=%.3f front_z=%.3f back_z=%.3f" % [yy, yy + 0.05, cnt, mx_x, mx_zf, mn_zb])
			yy += 0.05
	quit(0)
