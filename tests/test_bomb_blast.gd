## 驗證：炸彈爆炸施加物理擊飛（類似被飛撲）
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
	# 建炸彈
	var bomb := BombInstance.new()
	add_child_autofree(bomb)
	bomb.global_position = Vector3(5, 1, 0)  # 遠離玩家 → 不影響
	# 玩家在炸點附近(近) 與 遠離(遠)
	var near := _make_player(Vector3(5.5, 1, 0))
	var far := _make_player(Vector3(9, 1, 0))
	await wait_frames(2)
	# 手動引爆，炸點在 near 附近
	bomb.global_position = Vector3(5, 1, 0)  # near 距 ~0.5 半徑內, far 距 4 超過半徑3
	bomb._fuse = 0.0
	bomb._explode()
	await wait_frames(1)
	print("near state=", near.state_machine.current_state_name, " vel=", near.velocity)
	print("far state=", far.state_machine.current_state_name)
	assert_eq(near.state_machine.current_state_name, "Fly", "半徑內玩家被炸進 Fly")
	assert_true(near.velocity.length() > 0.0, "半徑內玩家獲得擊飛速度")
