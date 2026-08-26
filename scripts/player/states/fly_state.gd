class_name FlyState
extends BaseState

const FLY_FALL_GRAVITY: float = 30.0
## 触地后的水平阻尼（秒^-1）：落地滑行时快速衰减水平速度，让击飞落地后更快停住
const GROUND_DAMP: float = 12.0

## 飞行结束条件：飞超 2.5s 直接倒地；或连续触地 0.5s 倒地
const MAX_FLY_TIME: float = 2.5
const GROUND_TIME_LIMIT: float = 0.5

var _air_time: float = 0.0
var _ground_time: float = 0.0

## 击飞施加（由 hit 时调用一次）
func launch(direction: Vector3) -> void:
	var controller := _player as PlayerController
	if controller:
		controller.velocity = direction

func enter() -> void:
	_air_time = 0.0
	_ground_time = 0.0
	var controller := _player as PlayerController
	if controller:
		# 关闭布娃娃（Fly 阶段用动画姿态，不开物理）
		controller.set_ragdoll(false)

func physics_update(delta: float) -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	_air_time += delta
	# 落地用较大重力，快速下落
	if controller.is_on_floor():
		_ground_time += delta
		# 落地滑行：水平速度快速衰减，减少被击飞后的滑行距离
		controller.velocity.x = move_toward(controller.velocity.x, 0.0, GROUND_DAMP * delta)
		controller.velocity.z = move_toward(controller.velocity.z, 0.0, GROUND_DAMP * delta)
	else:
		_ground_time = 0.0
		controller.velocity.y -= FLY_FALL_GRAVITY * delta
	# 结束条件：飞行超时 或 连续触地超时
	if _air_time >= MAX_FLY_TIME or _ground_time >= GROUND_TIME_LIMIT:
		controller.state_machine.transition_to("Stunned")