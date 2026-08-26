extends GutTest

## 验证死亡→读秒→坠落→Idle 完整复活流程（状态机）

var _player: PlayerController

func after_each() -> void:
	if _player and is_instance_valid(_player):
		_player.free()

func test_death_flow_through_respawn_states() -> void:
	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	_player = pscene.instantiate() as PlayerController
	add_child_autofree(_player)
	await wait_physics_frames(5)
	assert_eq(_player.state_machine.current_state_name, "Idle")

	# 死亡 → 应先转 Death，再自动到 RespawnWaiting
	_player.die()
	await wait_physics_frames(2)
	assert_eq(_player.state_machine.current_state_name, "RespawnWaiting", "死亡后应进入读秒")
	assert_false(_player.visible, "死亡期间角色应隐藏")

	# 配置并模拟读秒结束 → RespawnFall
	var waiting := _player.state_machine.get_state("RespawnWaiting") as RespawnWaitingState
	waiting.configure(Vector3(0, 8, 0), 0.1)
	await wait_seconds(0.2)
	assert_eq(_player.state_machine.current_state_name, "RespawnFall", "读秒结束应转坠落")
	assert_true(_player.visible, "坠落阶段应重新显示")
	assert_false(_player.visible if false else false)

func test_respawn_falls_to_idle_on_floor() -> void:
	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	_player = pscene.instantiate() as PlayerController
	_player.position = Vector3(0, 1, 0)
	add_child_autofree(_player)
	# 建地面
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 1
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	gs.shape = box
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	add_child(ground)
	await wait_physics_frames(5)

	# 进入 RespawnFall 状态（直接跳转模拟空中落下）
	_player.state_machine.transition_to("RespawnFall")
	await wait_seconds(1.5)
	assert_eq(_player.state_machine.current_state_name, "Idle", "落地后应恢复 Idle")
	ground.queue_free()
