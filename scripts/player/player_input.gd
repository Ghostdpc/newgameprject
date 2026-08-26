## 職責：封裝單個玩家的輸入查詢（鍵盤 P1/P2、手把 P1-P4，最多 4 個手把）
## 設備綁定由 GameManager.player_devices 提供（與 player_index 對齊）：
##   -2 = 未綁定（自動：P1/P2 鍵盤，P3/P4 手把）
##   -1 = 鍵盤（僅 P1/P2 有效）
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

## 槽位綁定設備（缺省 -2 未綁定）
func _assigned_device() -> int:
	if player_index >= 0 and player_index < GameManager.player_devices.size():
		return GameManager.player_devices[player_index]
	return -2

## 是否啟用鍵盤。明確綁定鍵盤(-1)即在任何席位都可用（聯機 client 的鍵盤角色落在高號席位也可用）；
## 未綁定(-2)時僅 P1/P2(席位 0/1) 自動鍵盤。
func _keyboard_enabled() -> bool:
	var d := _assigned_device()
	if d == -1:
		return true
	if d == -2:
		return player_index <= 1
	return false

## 是否啟用手把（明確手把或未綁定回退；明確鍵盤則關閉）
func _gamepad_enabled() -> bool:
	return _assigned_device() != -1

## 有效手把 device id（未綁定時按槽位順序 P1→0 … P4→3）
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

## 拾取按鍵是否持續按住（長按拾取用）
func is_pickup_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("pickup")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_pickup")

func is_use_item_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed(_kb_action("use_item")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_use")

## 抓取場景物理物件：鍵盤 grab_p1/p2、手把 joy_grab。探索性功能，可刪
func is_grab_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("grab")):
		return true
	return _gamepad_enabled() and Input.is_action_pressed("joy_grab")

## 自殺（測試用）：鍵盤 suicide_p1/p2、手把 joy_suicide
func is_suicide_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed(_kb_action("suicide")):
		return true
	return _gamepad_enabled() and Input.is_action_just_pressed("joy_suicide")

## 輸入 level 快照（供聯機上行：移動向量 + 按鍵按住位掩碼）
func get_input_level() -> Dictionary:
	var buttons := 0
	if _is_jump_held(): buttons |= BIT_JUMP
	if _is_dive_held(): buttons |= BIT_DIVE
	if is_pickup_held(): buttons |= BIT_PICKUP
	if _is_use_held(): buttons |= BIT_USE
	if is_grab_pressed(): buttons |= BIT_GRAB
	if _is_suicide_held(): buttons |= BIT_SUICIDE
	return {"move": get_move_direction(), "buttons": buttons}

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
