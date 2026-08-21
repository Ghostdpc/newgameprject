## 職責：跳躍狀態，施加跳躍衝力並等待落地

class_name JumpState
extends BaseState

func enter() -> void:
	var controller: PlayerController = _player as PlayerController
	if controller:
		controller.velocity.y = controller.jump_force

func physics_update(_delta: float) -> void:
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return

	var move_dir := controller.player_input.get_move_direction()
	controller.apply_move(move_dir)

	if controller.is_on_floor():
		if move_dir.length_squared() > 0.01:
			controller.state_machine.transition_to("Move")
		else:
			controller.state_machine.transition_to("Idle")

	if controller.player_input.is_dive_just_pressed():
		controller.state_machine.transition_to("Dive")
