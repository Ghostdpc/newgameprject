## 職責：封裝單個玩家的輸入查詢（支援鍵盤 P1 / 手把 P2-P4）

class_name PlayerInput
extends RefCounted

var player_index: int

func _init(index: int) -> void:
	player_index = index

func get_move_direction() -> Vector2:
	if player_index == 0:
		var kb := _keyboard_move()
		if kb.length_squared() > 0.0:
			return kb
	return _joy_move()

func is_jump_just_pressed() -> bool:
	if player_index == 0 and Input.is_action_just_pressed("jump_p1"):
		return true
	return Input.is_joy_button_pressed(_joy_device(), JOY_BUTTON_A)

func is_dive_just_pressed() -> bool:
	if player_index == 0 and Input.is_action_just_pressed("dive_p1"):
		return true
	return Input.is_joy_button_pressed(_joy_device(), JOY_BUTTON_X)

func is_pickup_just_pressed() -> bool:
	if player_index == 0 and Input.is_action_just_pressed("pickup_p1"):
		return true
	return Input.is_joy_button_pressed(_joy_device(), JOY_BUTTON_B)

func is_use_item_just_pressed() -> bool:
	if player_index == 0 and Input.is_action_just_pressed("use_item_p1"):
		return true
	return Input.is_joy_button_pressed(_joy_device(), JOY_BUTTON_Y)

func _keyboard_move() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up_p1"):    dir.y -= 1.0
	if Input.is_action_pressed("move_down_p1"):  dir.y += 1.0
	if Input.is_action_pressed("move_left_p1"):  dir.x -= 1.0
	if Input.is_action_pressed("move_right_p1"): dir.x += 1.0
	return dir.normalized() if dir.length_squared() > 0.0 else Vector2.ZERO

func _joy_move() -> Vector2:
	var device := _joy_device()
	var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	var dir := Vector2(x, y)
	if dir.length_squared() < 0.04:
		return Vector2.ZERO
	return dir.normalized() if dir.length() > 1.0 else dir

func _joy_device() -> int:
	return maxi(player_index - 1, 0)
