## 職責：被擊倒後的倒地狀態，角色不可控，計時結束自動站起

class_name StunnedState
extends BaseState

const STUN_DURATION: float = 1.5

var _timer: float = 0.0

func enter() -> void:
	_timer = STUN_DURATION
	var controller := _player as PlayerController
	if controller:
		controller.set_ragdoll(true)

func exit() -> void:
	var controller := _player as PlayerController
	if controller:
		controller.set_ragdoll(false)

func physics_update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		var controller := _player as PlayerController
		if controller and controller.is_on_floor():
			controller.state_machine.transition_to("Idle")
