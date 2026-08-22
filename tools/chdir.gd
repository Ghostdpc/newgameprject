extends SceneTree

var _frames: int = 0

func _init() -> void:
	root.add_child(load("res://scenes/tech_demos/active_ragdoll_demo.tscn").instantiate())
	print("LOAD OK")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 50:
		var r := root.get_node("ActiveDemo/Player/RenderModel")
		var leg := r.get_node("AB_upperleg_l")
		print("PHYS leg up=", (leg.global_transform.basis as Basis).y)
		print("PHYS leg pos=", leg.global_position.y)
		# render 骨架对应骨 pose（写回后）
		var render_skel := root.get_node("ActiveDemo/Player/RenderModel/Rig_Medium/Skeleton3D")
		if not render_skel:
			render_skel = _find_skel(root.get_node("ActiveDemo/Player/RenderModel"))
		if render_skel:
			var li: int = render_skel.find_bone("upperleg.l")
			var lp: Transform3D = render_skel.global_transform * render_skel.get_bone_global_pose(li)
			print("RENDER leg up=", (lp.basis as Basis).y, " pos=", lp.origin)
		quit(0)
	return false

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var q := _find_skel(c)
		if q:
			return q
	return null
