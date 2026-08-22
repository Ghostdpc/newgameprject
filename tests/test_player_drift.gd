## 職責：驗證玩家無輸入時不水平漂移

extends GutTest

func test_player_no_horizontal_drift_without_input() -> void:
	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var player := pscene.instantiate() as PlayerController
	player.position = Vector3.ZERO
	add_child_autofree(player)
	var start := player.global_position
	await wait_physics_frames(60)
	var dxz := Vector2(player.global_position.x - start.x, player.global_position.z - start.z)
	print("hz drift = ", dxz)
	assert_lt(dxz.length(), 0.5, "無輸入時玩家不應水平漂移")
