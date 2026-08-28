## 职责：远端席位的输入源（host 侧），从网络缓冲的按键 level 推导边缘
## 设计：client 上行按键 level + 移动向量 + 本帧沿(edge)；host 比对上一帧 level 自算 just_pressed
## 防丢操作：unreliable 丢一帧时，level 由下一帧覆盖；只要"按下→松开"两个 level
##           有一个到达即可判出一次沿（60Hz 上行 + 人类按键 >=50ms 保证 >=2 帧到达）
##
## 边缘推进（_buttons_prev）必须发生在 apply_input（RPC 到达，idle 阶段）时，
## 不能在每物理帧无条件推进：physics 阶段 advance 在 RPC 更新 cur 之后、状态机查询
## 之前执行，会把新 level 提前移入 prev，导致查询时 cur==prev，_edge 恒 false
## （移动是 level 直读不受影响，但跳跃/飞扑/拾取/使用/自杀等边缘输入全部失效）。
##
## 同一 idle 帧多帧 RPC 到达（press→release 压成一帧）时，client 显式上行 edge 位，
## host 把 edge OR 进累积器，保证按下沿至少被记录一帧；边缘按位读后即清除（consume-on-read）。

class_name RemoteInputProvider
extends PlayerInput

var _move: Vector2 = Vector2.ZERO
var _buttons_cur: int = 0
var _buttons_prev: int = 0
## 本帧累积的按下沿（idle 阶段 OR 进来，状态机查询后按位清除）
var _edge_acc: int = 0
## 最近一次累积边缘时的物理帧号（过期边缘自动失效，防 tap 后延迟触发）
var _edge_frame: int = -1
## 最近一次收到的输入序号（快照回执给 client 做 reconciliation）
var last_seq: int = -1

## 断线/重连标记时清空输入：避免掉线期间「幽灵」按残留方向持续移动
func reset() -> void:
	_move = Vector2.ZERO
	_buttons_cur = 0
	_buttons_prev = 0
	_edge_acc = 0
	_edge_frame = -1
	last_seq = -1

## host 收到上行输入时写入（最新覆盖）；仅当 level 变化时把旧值移入 prev 供边缘比对。
## edge 由 client 显式上行（防压帧丢沿）；host 侧 level 推导兜底仅在 level 变化时累加。
func apply_input(move: Vector2, buttons: int, edge: int = 0, seq: int = -1) -> void:
	_move = move
	var new_edges := 0
	if buttons != _buttons_cur:
		_buttons_prev = _buttons_cur
		_buttons_cur = buttons
		new_edges |= (buttons & ~_buttons_prev)
	new_edges |= edge
	if new_edges != 0:
		_edge_acc |= new_edges
		_edge_frame = Engine.get_physics_frames()
	if seq >= 0:
		last_seq = seq

func _take_edge(bit: int) -> bool:
	if _edge_acc & bit:
		var f := Engine.get_physics_frames()
		if _edge_frame >= 0 and f > _edge_frame + 2:
			_edge_acc = 0
			_edge_frame = -1
			return false
		_edge_acc &= ~bit
		if _edge_acc == 0:
			_edge_frame = -1
		return true
	return false

func get_move_direction() -> Vector2:
	return _move

func is_jump_just_pressed() -> bool:
	return _take_edge(BIT_JUMP)

func is_dive_just_pressed() -> bool:
	return _take_edge(BIT_DIVE)

func is_pickup_just_pressed() -> bool:
	return _take_edge(BIT_PICKUP)

func is_pickup_held() -> bool:
	return (_buttons_cur & BIT_PICKUP) != 0

func is_use_item_just_pressed() -> bool:
	return _take_edge(BIT_USE)

func is_grab_pressed() -> bool:
	return (_buttons_cur & BIT_GRAB) != 0

func is_suicide_just_pressed() -> bool:
	return _take_edge(BIT_SUICIDE)
