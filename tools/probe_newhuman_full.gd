extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://newhuman.fbx")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var skel: Skeleton3D = null
	for s in inst.find_children("*", "Skeleton3D", true, false):
		skel = s as Skeleton3D
		break
	# 完整骨骼 + 父子层级
	var children := {}
	for i in skel.get_bone_count():
		var p := skel.get_bone_parent(i)
		if not children.has(p):
			children[p] = []
		children[p].append(i)
	var stack_idx: Array[int] = [-1]
	var stack_depth: Array[int] = [0]
	while stack_idx.size() > 0:
		var idx: int = stack_idx.pop_back()
		var depth: int = stack_depth.pop_back()
		var kids: Array = children.get(idx, [])
		for ci in range(kids.size() - 1, -1, -1):
			stack_idx.append(kids[ci])
			stack_depth.append(depth + 1)
		if idx >= 0:
			var pad := ""
			for _i in depth:
				pad += "  "
			var gp := skel.get_bone_global_pose(idx)
			print(pad, "bone[", idx, "] '", skel.get_bone_name(idx), "' origin=", gp.origin)
	# 动画
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		print("animations: ", a.get_animation_list())
	# 节点结构
	for n in inst.get_children():
		print("node: ", n.name, " type=", n.get_class())
	quit()
