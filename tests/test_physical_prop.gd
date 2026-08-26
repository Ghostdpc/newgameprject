## 验证：玩家可推动场景物理物件（PhysicalProp）
extends GutTest

func test_player_pushes_physical_prop() -> void:
	# 地面
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 1
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	gs.shape = box
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	add_child_autofree(ground)

	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	player.position = Vector3(0, 1, -2)
	add_child_autofree(player)
	await wait_physics_frames(3)

	# 箱子在玩家面前
	var crate := (load("res://scenes/props/prop_crate.tscn") as PackedScene).instantiate() as RigidBody3D
	crate.position = Vector3(0, 0.4, 0)
	add_child_autofree(crate)
	await wait_physics_frames(5)

	var crate_start: Vector3 = crate.global_position
	var cs_count := crate.find_children("*", "CollisionShape3D", true, false).size()
	print("crate start=", crate_start, " layer=", crate.collision_layer, " mask=", crate.collision_mask, " cs=", cs_count)
	print("player layer=", player.collision_layer, " mask=", player.collision_mask)
	# 玩家持续按下（S 键，+Z 方向）移动撞箱子推动
	Input.action_press("move_down_p1")
	for i in 90:
		await wait_physics_frames(1)
	Input.action_release("move_down_p1")
	var crate_end: Vector3 = crate.global_position
	print("player pos=", player.global_position, " crate end=", crate_end, " moved=", (crate_end - crate_start))
	assert_gt(crate_end.z - crate_start.z, 0.5, "玩家推动箱子产生位移")
