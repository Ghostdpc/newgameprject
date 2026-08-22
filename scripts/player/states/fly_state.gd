class_name FlyState
extends BaseState

const FLY_FALL_GRAVITY: float = 30.0

## 飛行結束條件：飛超 2.5s 直接倒地；或連續觸地 0.5s 倒地
const MAX_FLY_TIME: float = 2.5
const GROUND_TIME_LIMIT: float = 0.5

var _air_time: float = 0.0
var _ground_time: float = 0.0

## 擊飛施加（由 hit 時調用一次）
func launch(direction: Vector3) -> void:
	var controller := _player as PlayerController
	if controller:
		controller.velocity = direction

func enter() -> void:
	_air_time = 0.0
	_ground_time = 0.0
	var controller := _player as PlayerController
	if controller:
		# 關閉布娃娃（Fly 階段用動畫姿態，不開物理）
		controller.set_ragdoll(false)

func physics_update(delta: float) -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	_air_time += delta
	# 落地用較大重力，快速下落
	if controller.is_on_floor():
		_ground_time += delta
	else:
		_ground_time = 0.0
		controller.velocity.y -= FLY_FALL_GRAVITY * delta
	# 結束條件：飛行超時 或 連續觸地超時
	if _air_time >= MAX_FLY_TIME or _ground_time >= GROUND_TIME_LIMIT:
		controller.state_machine.transition_to("Stunned")