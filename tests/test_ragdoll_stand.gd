## 职责：验证 ragdoll 站起插值是否平滑（无瞬移）

extends GutTest

func test_stand_up_interpolates_smoothly() -> void:
	# 建地面
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	add_child_autofree(ground)

	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var player := pscene.instantiate() as PlayerController
	player.position = Vector3(0, 2, 0)
	add_child_autofree(player)

	await wait_physics_frames(5)
	var skeleton: Skeleton3D = _find_skeleton(player.get_node("Model"))
	# 倒地
	player.state_machine.transition_to("Stunned")
	await wait_physics_frames(30)
	# 倒地
	player.state_machine.transition_to("Stunned")
	await wait_physics_frames(30)
	# 击飞造成位移 + 倒地姿势
	player.knockback(Vector3(2.0, 1.0, 0.0))
	await wait_physics_frames(20)
	var hips_down: Vector3 = skeleton.get_bone_global_pose(0).origin
	print("hips at land = ", hips_down)
	# 站起，第1帧(delayed stop)前 hips
	player.stand_up()
	await wait_physics_frames(1)
	var hips_after_stop: Vector3 = _find_skeleton(player.get_node("Model")).get_bone_global_pose(0).origin
	await wait_physics_frames(1)
	var hips_after_1frame: Vector3 = _find_skeleton(player.get_node("Model")).get_bone_global_pose(0).origin
	print("hips before stop = ", hips_down)
	print("hips after begin stand = ", hips_after_stop)
	print("hips after 1 frame = ", hips_after_1frame)
	# 站起不应瞬移：相邻帧位移小
	var step := absf(hips_after_1frame.y - hips_after_stop.y)
	print("step = ", step)
	assert_lt(step, 0.5, "站起首帧不应瞬移")

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null
