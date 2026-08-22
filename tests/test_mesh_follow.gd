## 職責：驗證擊飛時 mesh 是否跟隨 body（mesh-relative 偏移不變）

extends GutTest

func test_mesh_follows_body_on_knockback() -> void:
	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var player := pscene.instantiate() as PlayerController
	player.position = Vector3(0, 2, 0)
	add_child_autofree(player)
	await wait_physics_frames(5)
	# mesh 相對 body 的偏移
	var model: Node3D = player.get_node("Model")
	var skeleton: Skeleton3D = _find_skeleton(model)
	var mesh_rel_before: Vector3 = model.global_position - player.global_position
	print("model rel before = ", mesh_rel_before)
	# 擊飛 body
	player.knockback(Vector3(5.0, 2.0, 0.0))
	await wait_physics_frames(30)
	var mesh_rel_after: Vector3 = model.global_position - player.global_position
	print("body pos after = ", player.global_position)
	print("model rel after = ", mesh_rel_after)
	# mesh 應跟 body，相對偏移保持不變
	assert_lt((mesh_rel_after - mesh_rel_before).length(), 0.1, "擊飛時 mesh 應跟隨 body 移動")

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null
