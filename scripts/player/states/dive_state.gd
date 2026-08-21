## 職責：飛撲狀態，向前施加水平衝力產生物理碰撞

class_name DiveState
extends BaseState

const DIVE_FORCE: float = 18.0
const DIVE_DURATION: float = 0.4

var _timer: float = 0.0
var _dive_direction: Vector3 = Vector3.ZERO

func enter() -> void:
	_timer = DIVE_DURATION
	var controller: PlayerController = _player as PlayerController
	if controller:
		var move_dir := controller.player_input.get_move_direction()
		if move_dir.length_squared() > 0.0:
			_dive_direction = Vector3(move_dir.x, 0.0, move_dir.y).normalized()
		else:
			_dive_direction = -controller.global_basis.z
		controller.velocity += _dive_direction * DIVE_FORCE

func physics_update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		var controller: PlayerController = _player as PlayerController
		if controller and controller.is_on_floor():
			controller.state_machine.transition_to("Idle")
