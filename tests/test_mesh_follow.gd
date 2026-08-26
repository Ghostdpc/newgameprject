## 职责：验证击飞时 mesh 是否跟随 body（mesh-relative 偏移不变）

extends GutTest

func test_mesh_follows_body_on_knockback() -> void:
	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var player := pscene.instantiate() as PlayerController
	player.position = Vector3(0, 2, 0)
	add_child_autofree(player)
	await wait_physics_frames(5)
	# mesh 相对 body 的偏移
	var model: Node3D = player.get_node("Model")
	var skeleton: Skeleton3D = _find_skeleton(model)
	var mesh_rel_before: Vector3 = model.global_position - player.global_position
	print("model rel before = ", mesh_rel_before)
	# 击飞 body
	player.knockback(Vector3(5.0, 2.0, 0.0))
	await wait_physics_frames(30)
	var mesh_rel_after: Vector3 = model.global_position - player.global_position
	print("body pos after = ", player.global_position)
	print("model rel after = ", mesh_rel_after)
	# mesh 应跟 body，相对偏移保持不变
	assert_lt((mesh_rel_after - mesh_rel_before).length(), 0.1, "击飞时 mesh 应跟随 body 移动")

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func test_mesh_follows_body_during_ragdoll() -> void:
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
	var model: Node3D = player.get_node("Model")
	# 开 ragdoll + 击飞 body
	player.state_machine.transition_to("Stunned")
	player.knockback(Vector3(5.0, 2.0, 0.0))
	await wait_physics_frames(20)
	var body_pos := player.global_position
	var model_pos := model.global_position
	print("ragdoll: body=", body_pos, " model=", model_pos, " diff=", (model_pos - body_pos))
	# 模型应跟 body 位移（水平差距小）
	var hz_diff := Vector2(model_pos.x - body_pos.x, model_pos.z - body_pos.z).length()
	assert_lt(hz_diff, 1.0, "ragdoll 时模型应跟 body 位移")
