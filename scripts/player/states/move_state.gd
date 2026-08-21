## 職責：移動狀態，處理水平移動

class_name MoveState
extends BaseState

func enter() -> void:
	pass

func physics_update(_delta: float) -> void:
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return

	var move_dir := controller.player_input.get_move_direction()

	if move_dir.length_squared() < 0.01:
		controller.state_machine.transition_to("Idle")
		return

	if controller.player_input.is_jump_just_pressed() and controller.is_on_floor():
		controller.state_machine.transition_to("Jump")
		return

	if controller.player_input.is_dive_just_pressed():
		controller.state_machine.transition_to("Dive")
		return

	controller.apply_move(move_dir)
