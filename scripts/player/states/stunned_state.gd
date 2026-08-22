## 職責：被擊倒後的倒地狀態，角色不可控，計時結束自動站起

class_name StunnedState
extends BaseState

const STUN_DURATION: float = 1.5
const KNOCKBACK_DAMP: float = 3.0

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
	var controller := _player as PlayerController
	if not controller:
		return
	# 落地後水平速度衰減（大刹車=立刻停，倒地滑行短）
	if controller.is_on_floor():
		var brake := TuneConfig.ground_brake * delta
		controller.velocity.x = move_toward(controller.velocity.x, 0.0, brake)
		controller.velocity.z = move_toward(controller.velocity.z, 0.0, brake)
	if _timer <= 0.0 and controller.is_on_floor():
		controller.state_machine.transition_to("Idle")
