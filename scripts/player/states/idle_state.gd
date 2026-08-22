## 職責：待機狀態，等待移動或跳躍輸入

class_name IdleState
extends BaseState

func enter() -> void:
	pass

func physics_update(_delta: float) -> void:
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return
	var move_dir := controller.player_input.get_move_direction()
	if move_dir.length_squared() > 0.0:
		controller.state_machine.transition_to("Move")
		return
	if controller.player_input.is_dive_just_pressed():
		controller.state_machine.transition_to("Dive")
		return
	controller.apply_move(Vector2.ZERO)
	if controller.player_input.is_jump_just_pressed() and controller.is_on_floor():
		controller.state_machine.transition_to("Jump")
