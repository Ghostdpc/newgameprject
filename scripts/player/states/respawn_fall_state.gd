## 職責：重生墜落階段——角色在空中出現並落下，期間不可操作，落地恢復

class_name RespawnFallState
extends BaseState

func enter() -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	# 明確取得讀秒階段的復活座標
	var waiting := controller.state_machine.get_state("RespawnWaiting") as RespawnWaitingState
	if waiting:
		controller.velocity = Vector3.ZERO
		controller.global_position = waiting.get_spawn_position()
		controller.visible = true

func physics_update(delta: float) -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	# 重力下落（重寫，固定用較快下落）
	if not controller.is_on_floor():
		controller.velocity.y -= 30.0 * delta
	if controller.is_on_floor():
		controller.state_machine.transition_to("Idle")
