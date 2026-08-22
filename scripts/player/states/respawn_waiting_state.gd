## 職責：重生讀秒階段——期間不可操作，等待時間到轉 RespawnFall
## 由 LevelBase 設定復活座標與讀秒時長

class_name RespawnWaitingState
extends BaseState

var _wait_duration: float = 2.0
var _elapsed: float = 0.0

## 設定復活點與等待時長（由 LevelBase 讀秒前調用）
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

## LevelBase 讀取復活座標
func get_spawn_position() -> Vector3:
	return _spawn_pos
