## 职责：封装单个玩家的输入查询（键盘 P1/P2、手把 P1-P4，最多 4 个手把）
## 设备绑定由 GameManager.player_devices 提供（与 player_index 对齐）：
##   -2 = 未绑定（自动：P1/P2 键盘，P3/P4 手把）
##   -1 = 键盘（仅 P1/P2 有效）
##   >=0 = 手把 device id

class_name PlayerInput
extends RefCounted

## 按键 level 位掩码（联机上行用；host 侧 RemoteInputProvider 从 level 推导边缘）
const BIT_JUMP := 1 << 0
const BIT_DIVE := 1 << 1
const BIT_PICKUP := 1 << 2
const BIT_USE := 1 << 3
const BIT_GRAB := 1 << 4
const BIT_SUICIDE := 1 << 5

var player_index: int

func _init(index: int) -> void:
	player_index = index

## 键位集索引（0=P1 WASD，1=P2 方向键）。联机时取「本端已加入键盘角色」的本地序号
## （手柄不占键盘序号），使本端第一个键盘角色固定用 P1 键位、第二个用 P2；本地模式按席位索引。
func _keybind_index() -> int:
	if NetManager.is_online:
		var kb: Array[int] = []
		for s in NetManager.get_my_seats():
			if GameManager.player_devices.size() > s and GameManager.player_devices[s] < 0:
				kb.append(s)
		var idx := kb.find(player_index)
		if idx >= 0:
			return idx
	return clampi(player_index, 0, 1)

## 按键位集拼动作名（`jump_p1`/`jump_p2` …）
func _kb_action(base: String) -> String:
	return "%s_p%d" % [base, _keybind_index() + 1]

## 键位集后缀（`_p1`/`_p2`），供 _keyboard_move 拼轴动作名
func _kb_suffix() -> String:
	return "_p%d" % (_keybind_index() + 1)

## 槽位绑定设备（缺省 -2 未绑定）
func _assigned_device() -> int:
	if player_index >= 0 and player_index < GameManager.player_devices.size():
		return GameManager.player_devices[player_index]
	return -2

## 是否启用键盘。明确绑定键盘(-1)即在任何席位都可用（联机 client 的键盘角色落在高号席位也可用）；
## 未绑定(-2)时仅 P1/P2(席位 0/1) 自动键盘。
func _keyboard_enabled() -> bool:
	var d := _assigned_device()
	if d == -1:
		return true
	if d == -2:
		return player_index <= 1
	return false

## 是否启用手把（明确手把或未绑定回退；明确键盘则关闭）
func _gamepad_enabled() -> bool:
	return _assigned_device() != -1

## 有效手把 device id（未绑定时按槽位顺序 P1→0 … P4→3）
func _device() -> int:
	var d := _assigned_device()
	if d >= 0:
		return d
	return clampi(player_index, 0, 3)

func get_move_direction() -> Vector2:
	if _keyboard_enabled():
		var kb := _keyboard_move(_kb_suffix())
		if kb.length_squared() > 0.0:
			return kb
	if _gamepad_enabled():
		return _joy_move()
	return Vector2.ZERO

func is_jump_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed(_kb_action("jump")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_jump")

func is_dive_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed(_kb_action("dive")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_dive")

func is_pickup_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed(_kb_action("pickup")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_pickup")

## 拾取按键是否持续按住（长按拾取用）
func is_pickup_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("pickup")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_pickup")

func is_use_item_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed(_kb_action("use_item")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_use")

## 抓取场景物理物件：键盘 grab_p1/p2、手把 joy_grab。探索性功能，可删
func is_grab_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("grab")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_grab")

## 自杀（测试用）：键盘 suicide_p1/p2、手把 joy_suicide
func is_suicide_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("suicide")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_suicide")

## 输入 level 快照（供联机上行：移动向量 + 按键按住位掩码）
func get_input_level() -> Dictionary:
	var buttons := 0
	if _is_jump_held(): buttons |= BIT_JUMP
	if _is_dive_held(): buttons |= BIT_DIVE
	if is_pickup_held(): buttons |= BIT_PICKUP
	if _is_use_held(): buttons |= BIT_USE
	if is_grab_pressed(): buttons |= BIT_GRAB
	if _is_suicide_held(): buttons |= BIT_SUICIDE
	return {"move": get_move_direction(), "buttons": buttons}

## 本帧「刚按下」沿位掩码（联机上行：host 直接 OR 进边缘，避免同一 idle 帧多包压沿丢失）
func get_input_edge() -> int:
	var edge := 0
	if is_jump_just_pressed(): edge |= BIT_JUMP
	if is_dive_just_pressed(): edge |= BIT_DIVE
	if is_pickup_just_pressed(): edge |= BIT_PICKUP
	if is_use_item_just_pressed(): edge |= BIT_USE
	if is_suicide_just_pressed(): edge |= BIT_SUICIDE
	return edge

func _is_jump_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("jump")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_jump")

func _is_dive_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("dive")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_dive")

func _is_use_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("use_item")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_use")

func _is_suicide_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("suicide")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_suicide")

func _keyboard_move(suffix: String) -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up%s" % suffix):    dir.y -= 1.0
	if Input.is_action_pressed("move_down%s" % suffix):  dir.y += 1.0
	if Input.is_action_pressed("move_left%s" % suffix):  dir.x -= 1.0
	if Input.is_action_pressed("move_right%s" % suffix): dir.x += 1.0
	return dir.normalized() if dir.length_squared() > 0.0 else Vector2.ZERO

func _joy_move() -> Vector2:
	var device := _device()
	var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	var dir := Vector2(x, y)
	if dir.length_squared() < 0.04:
		return Vector2.ZERO
	return dir.normalized() if dir.length() > 1.0 else dir
