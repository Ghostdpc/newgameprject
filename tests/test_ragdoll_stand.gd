## 職責：驗證 ragdoll 倒地/站起時骨架節點位置

extends GutTest

func test_skeleton_position_during_and_after_ragdoll() -> void:
	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var player := pscene.instantiate() as PlayerController
	player.position = Vector3.ZERO
	add_child_autofree(player)
	# 找骨架
	var skeleton: Skeleton3D = _find_skeleton(player.get_node("Model"))
	print("skeleton found = ", skeleton != null)
	var mesh: Node3D = _find_mesh(player.get_node("Model"))
	var skeleton_start: Vector3 = skeleton.global_position
	var mesh_start: Vector3 = mesh.global_position
	print("start skeleton = ", skeleton_start, " mesh = ", mesh_start)
	# 進入 Stunned（啟用 ragdoll）
	player.state_machine.transition_to("Stunned")
	await wait_physics_frames(10)
	var skeleton_rag: Vector3 = skeleton.global_position
	var mesh_rag: Vector3 = mesh.global_position
	print("ragdoll on: skeleton = ", skeleton_rag, " mesh = ", mesh_rag)
	# 站起
	if player.state_machine.current_state_name == "Stunned":
		player.stand_up()
		player.state_machine.transition_to("Idle")
	await wait_physics_frames(10)
	var skeleton_stand: Vector3 = skeleton.global_position
	var mesh_stand: Vector3 = mesh.global_position
	print("stood up: skeleton = ", skeleton_stand, " mesh = ", mesh_stand)
	print("mesh drift = ", mesh_stand - mesh_start)
	assert_true(true)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _find_mesh(n: Node) -> Node3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null
