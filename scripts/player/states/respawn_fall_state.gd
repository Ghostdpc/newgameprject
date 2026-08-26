## 职责：重生坠落阶段——角色在空中出现并落下，期间不可操作，落地恢复

class_name RespawnFallState
extends BaseState

func enter() -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	# 明确取得读秒阶段的复活座标
	var waiting := controller.state_machine.get_state("RespawnWaiting") as RespawnWaitingState
	if waiting:
		controller.velocity = Vector3.ZERO
		controller.global_position = waiting.get_spawn_position()
		controller.visible = true

func physics_update(delta: float) -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	# 重力下落（重写，固定用较快下落）
	if not controller.is_on_floor():
		controller.velocity.y -= 30.0 * delta
	if controller.is_on_floor():
		controller.state_machine.transition_to("Idle")
