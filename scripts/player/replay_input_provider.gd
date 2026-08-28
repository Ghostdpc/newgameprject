## 职责：本端预测输入重放源（reconciliation 用）
## 持有历史输入帧 [{move, buttons, edge}]，按步进回放，边沿位 consume-on-read，
## 语义与 RemoteInputProvider 一致，只是数据来自本地历史而非网络。

class_name ReplayInputProvider
extends PlayerInput

var _entries: Array = []
var _move: Vector2 = Vector2.ZERO
var _buttons: int = 0
var _edge: int = 0

func set_entries(entries: Array) -> void:
	_entries = entries

## 前进到第 i 帧的输入状态（状态机每物理帧读取一次）
func step(i: int) -> void:
	if i >= 0 and i < _entries.size():
		var e: Dictionary = _entries[i]
		_move = e["move"]
		_buttons = e["buttons"]
		_edge = e["edge"]
	else:
		_move = Vector2.ZERO
		_buttons = 0
		_edge = 0

func get_move_direction() -> Vector2:
	return _move

func _take(bit: int) -> bool:
	if _edge & bit:
		_edge &= ~bit
		return true
	return false

func is_jump_just_pressed() -> bool:
	return _take(BIT_JUMP)

func is_dive_just_pressed() -> bool:
	return _take(BIT_DIVE)

func is_pickup_just_pressed() -> bool:
	return _take(BIT_PICKUP)

func is_use_item_just_pressed() -> bool:
	return _take(BIT_USE)

func is_grab_pressed() -> bool:
	return (_buttons & BIT_GRAB) != 0

func is_suicide_just_pressed() -> bool:
	return _take(BIT_SUICIDE)

func is_pickup_held() -> bool:
	return (_buttons & BIT_PICKUP) != 0
