## 職責：封裝單個玩家的輸入查詢（鍵盤 P1/P2、手把 P1-P4，最多 4 個手把）
## 設備綁定由 GameManager.player_devices 提供（與 player_index 對齊）：
##   -2 = 未綁定（自動：P1/P2 鍵盤，P3/P4 手把）
##   -1 = 鍵盤（僅 P1/P2 有效）
##   >=0 = 手把 device id

class_name PlayerInput
extends RefCounted

var player_index: int

func _init(index: int) -> void:
	player_index = index

## 槽位綁定設備（缺省 -2 未綁定）
func _assigned_device() -> int:
	if player_index >= 0 and player_index < GameManager.player_devices.size():
		return GameManager.player_devices[player_index]
	return -2

## 是否啟用鍵盤（僅 P1/P2，明確鍵盤或未綁定自動）
func _keyboard_enabled() -> bool:
	if player_index > 1:
		return false
	var d := _assigned_device()
	return d == -1 or d == -2

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
		var kb := _keyboard_move("_p%d" % (player_index + 1))
		if kb.length_squared() > 0.0:
			return kb
	if _gamepad_enabled():
		return _joy_move()
	return Vector2.ZERO

func is_jump_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed("jump_p%d" % (player_index + 1)):
		return true
	return _gamepad_enabled() and Input.is_joy_button_pressed(_device(), JOY_BUTTON_A)

func is_dive_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed("dive_p%d" % (player_index + 1)):
		return true
	return _gamepad_enabled() and Input.is_joy_button_pressed(_device(), JOY_BUTTON_X)

func is_pickup_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed("pickup_p%d" % (player_index + 1)):
		return true
	return _gamepad_enabled() and Input.is_joy_button_pressed(_device(), JOY_BUTTON_B)

## 拾取按鍵是否持續按住（長按拾取用）
func is_pickup_held() -> bool:
	if _keyboard_enabled() and Input.is_action_pressed("pickup_p%d" % (player_index + 1)):
		return true
	return _gamepad_enabled() and Input.is_joy_button_pressed(_device(), JOY_BUTTON_B)

func is_use_item_just_pressed() -> bool:
	if _keyboard_enabled() and Input.is_action_just_pressed("use_item_p%d" % (player_index + 1)):
		return true
	return _gamepad_enabled() and Input.is_joy_button_pressed(_device(), JOY_BUTTON_Y)

## R 鍵抓取場景物理物件（P1=R / P2=T）。探索性功能，可刪
func is_grab_pressed() -> bool:
	if player_index == 0:
		return Input.is_key_pressed(KEY_R)
	if player_index == 1:
		return Input.is_key_pressed(KEY_T)
	return false

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
