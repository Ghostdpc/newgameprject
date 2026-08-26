## 职责：重生读秒阶段——期间不可操作，等待时间到转 RespawnFall
## 由 LevelBase 设定复活座标与读秒时长

class_name RespawnWaitingState
extends BaseState

var _wait_duration: float = 2.0
var _elapsed: float = 0.0

## 设定复活点与等待时长（由 LevelBase 读秒前调用）
func configure(respawn_pos: Vector3, duration: float) -> void:
	_spawn_pos = respawn_pos
	_wait_duration = duration

var _spawn_pos: Vector3 = Vector3.ZERO

func enter() -> void:
	_elapsed = 0.0

func physics_update(delta: float) -> void:
	_elapsed += delta
	var controller := _player as PlayerController
	if not controller:
		return
	if _elapsed >= _wait_duration:
		controller.state_machine.transition_to("RespawnFall")

## LevelBase 读取复活座标
func get_spawn_position() -> Vector3:
	return _spawn_pos
