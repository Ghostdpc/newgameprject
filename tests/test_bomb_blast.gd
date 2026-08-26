## 验证：炸弹爆炸施加物理击飞（类似被飞扑）
extends GutTest

func _make_player(pos: Vector3) -> PlayerController:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	p.player_index = 0
	p.position = pos
	add_child_autofree(p)
	return p

func test_blast_knocks_players_into_fly() -> void:
	var p1 := _make_player(Vector3(0, 1, 0))
	await wait_frames(3)
	# 建炸弹
	var bomb := BombInstance.new()
	add_child_autofree(bomb)
	bomb.global_position = Vector3(5, 1, 0)  # 远离玩家 → 不影响
	# 玩家在炸点附近(近) 与 远离(远)
	var near := _make_player(Vector3(5.5, 1, 0))
	var far := _make_player(Vector3(9, 1, 0))
	await wait_frames(2)
	# 手动引爆，炸点在 near 附近
	bomb.global_position = Vector3(5, 1, 0)  # near 距 ~0.5 半径内, far 距 4 超过半径3
	bomb._fuse = 0.0
	bomb._explode()
	await wait_frames(1)
	print("near state=", near.state_machine.current_state_name, " vel=", near.velocity)
	print("far state=", far.state_machine.current_state_name)
	assert_eq(near.state_machine.current_state_name, "Fly", "半径内玩家被炸进 Fly")
	assert_true(near.velocity.length() > 0.0, "半径内玩家获得击飞速度")
