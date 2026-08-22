## 職責：被擊倒後的倒地狀態（Down 階段），角色不可控，計時結束站起
## FlyState 落地後進入本狀態，開啟全骨布娃娃癱軟

class_name StunnedState
extends BaseState

const STUN_DURATION: float = 1.8

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
	# 落地後水平速度衰減（倒地滑行）
	if controller.is_on_floor():
		var brake := TuneConfig.ground_brake * delta
		controller.velocity.x = move_toward(controller.velocity.x, 0.0, brake)
		controller.velocity.z = move_toward(controller.velocity.z, 0.0, brake)
	if _timer <= 0.0 and controller.is_on_floor():
		# 站起前把 body 對齊到 ragdoll 落點，避免站起瞬移
		controller.sync_body_to_ragdoll()
		controller.state_machine.transition_to("Idle")
