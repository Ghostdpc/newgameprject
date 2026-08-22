extends SceneTree

var _frames: int = 0

func _init() -> void:
	root.add_child(load("res://scenes/tech_demos/active_ragdoll_demo.tscn").instantiate())
	print("LOAD OK")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 50:
		var r := root.get_node("ActiveDemo/Player/RenderModel")
		var anchor := r.get_node("AB_hips")
		var leg := r.get_node("AB_upperleg_l")
		print("PHYS hips pos=", anchor.global_position.y, " up=", (anchor.global_transform.basis as Basis).y)
		print("PHYS leg pos=", leg.global_position, " up=", (leg.global_transform.basis as Basis).y)
		# 动画目标
		var sk := root.get_node("ActiveDemo/Player/DriverModel/Rig_Medium/Skeleton3D")
		if not sk:
			sk = _find_skel(root.get_node("ActiveDemo/Player/DriverModel"))
		if sk:
			var hi: int = sk.find_bone("hips")
			var li: int = sk.find_bone("upperleg.l")
			var ht: Transform3D = sk.global_transform * sk.get_bone_global_pose(hi)
			var lt: Transform3D = sk.global_transform * sk.get_bone_global_pose(li)
			print("ANIM hips up=", (ht.basis as Basis).y, " pos=", ht.origin)
			print("ANIM leg up=", (lt.basis as Basis).y, " pos=", lt.origin)
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
