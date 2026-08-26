## 职责：被击倒后的倒地状态（Down 阶段），角色不可控，计时结束站起
## FlyState 落地后进入本状态，开启全骨布娃娃瘫软

class_name StunnedState
extends BaseState

## 倒地时长改用 TuneConfig.stun_duration（F3 面板可调），默认 5s
var _timer: float = 0.0

func enter() -> void:
	_timer = TuneConfig.stun_duration
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
	# 落地后水平速度衰减（倒地滑行）
	if controller.is_on_floor():
		var brake := TuneConfig.ground_brake * delta
		controller.velocity.x = move_toward(controller.velocity.x, 0.0, brake)
		controller.velocity.z = move_toward(controller.velocity.z, 0.0, brake)
	# 瘫软期间 body 持续跟随物理骨落点（避免 mesh 瘫软落地而 body 悬空错位）
	controller.sync_body_to_ragdoll()
	if _timer <= 0.0 and controller.is_on_floor():
		controller.state_machine.transition_to("Idle")
