## 职责：远端席位的输入源（host 侧），从网络缓冲的按键 level 推导边缘
## 设计：client 上行按键 level + 移动向量；host 比对上一帧 level 自算 just_pressed
## 防丢操作：unreliable 丢一帧时，level 由下一帧覆盖；只要"按下→松开"两个 level
##           有一个到达即可判出一次沿（60Hz 上行 + 人类按键 >=50ms 保证 >=2 帧到达）
##
## 边缘推进（_buttons_prev）必须发生在 apply_input（RPC 到达，idle 阶段）时，
## 不能在每物理帧无条件推进：physics 阶段 advance 在 RPC 更新 cur 之后、状态机查询
## 之前执行，会把新 level 提前移入 prev，导致查询时 cur==prev，_edge 恒 false
## （移动是 level 直读不受影响，但跳跃/飞扑/拾取/使用/自杀等边缘输入全部失效）。

class_name RemoteInputProvider
extends PlayerInput

var _move: Vector2 = Vector2.ZERO
var _buttons_cur: int = 0
var _buttons_prev: int = 0

## host 收到上行输入时写入（最新覆盖）；仅当 level 变化时把旧值移入 prev 供边缘比对
## （同一物理帧多帧 RPC 到达时，不变化就不推进，保证按下边缘至少被记录一帧）
func apply_input(move: Vector2, buttons: int) -> void:
	_move = move
	if buttons != _buttons_cur:
		_buttons_prev = _buttons_cur
		_buttons_cur = buttons

func _edge(bit: int) -> bool:
	return (_buttons_cur & bit) != 0 and (_buttons_prev & bit) == 0

func get_move_direction() -> Vector2:
	return _move

func is_jump_just_pressed() -> bool:
	return _edge(BIT_JUMP)

func is_dive_just_pressed() -> bool:
	return _edge(BIT_DIVE)

func is_pickup_just_pressed() -> bool:
	return _edge(BIT_PICKUP)

func is_pickup_held() -> bool:
	return (_buttons_cur & BIT_PICKUP) != 0

func is_use_item_just_pressed() -> bool:
	return _edge(BIT_USE)

func is_grab_pressed() -> bool:
	return (_buttons_cur & BIT_GRAB) != 0

func is_suicide_just_pressed() -> bool:
	return _edge(BIT_SUICIDE)
