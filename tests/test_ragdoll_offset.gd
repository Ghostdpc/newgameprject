## 職責：測量 ragdoll 倒地/站起時 骨架節點 相對 body 的偏移

extends GutTest

func test_skeleton_relative_offset_during_ragdoll() -> void:
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
	var skeleton_local_start: Vector3 = skeleton.position
	print("skeleton local start = ", skeleton_local_start)
	# 進入 Stunned 倒地
	player.state_machine.transition_to("Stunned")
	await wait_physics_frames(30)
	var skeleton_local_down: Vector3 = skeleton.position
	var body_down: Vector3 = player.global_position
	print("down: body=", body_down, " skeleton_local=", skeleton_local_down, " offset=", skeleton_local_down - skeleton_local_start)
	# 站起
	if player.state_machine.current_state_name == "Stunned":
		player.stand_up()
		player.state_machine.transition_to("Idle")
	await wait_physics_frames(10)
	var skeleton_local_stand: Vector3 = skeleton.position
	var body_stand: Vector3 = player.global_position
	print("stand: body=", body_stand, " skeleton_local=", skeleton_local_stand, " offset=", skeleton_local_stand - skeleton_local_start)
	print("body drift down->stand = ", body_stand - body_down)
	assert_true(true)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null
