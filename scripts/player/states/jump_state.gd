## 职责：跳跃状态，施加跳跃冲力并等待落地

class_name JumpState
extends BaseState

func enter() -> void:
	var controller: PlayerController = _player as PlayerController
	if controller:
		controller.velocity.y = controller.jump_force
		# 初跳后确认可二段跳（一个空中周期内只能用一次）
		controller.double_jump_available = true

func physics_update(_delta: float) -> void:
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return

	var move_dir := controller.player_input.get_move_direction()
	controller.apply_move(move_dir)

	# 二段跳：空中按跳，且本空中周期未用过二段跳，且配置开启
	if not controller.is_on_floor() and controller.player_input.is_jump_just_pressed() \
			and controller.double_jump_ratio > 0.0 and controller.double_jump_available:
		controller.velocity.y = controller.jump_force * controller.double_jump_ratio
		controller.double_jump_available = false
		controller.cycle_face()   # 二段跳换表情（提示动作用）

	if controller.is_on_floor():
		# 落地时重置二段跳可用
		controller.double_jump_available = false
		if move_dir.length_squared() > 0.01:
			controller.state_machine.transition_to("Move")
		else:
			controller.state_machine.transition_to("Idle")

	if controller.player_input.is_dive_just_pressed():
		controller.cycle_face()
		controller.state_machine.transition_to("Dive")
