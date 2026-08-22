## 职责：S1 玩家加入 + S2 人数确认（交互文档 §4 加入与识别 / 人数确认）
## 输入：
##   - 键盘数字键 1~4：加入 / 取消对应槽位（1/2 键键盘，3/4 键手柄槽）
##   - 键盘 Enter / 手柄 A：加入空位；已 >=2 人时再按 = 房主开始
##   - 手柄 B：已加入者退出当前槽位；未加入者返回标题
##   - Backspace / X：取消最后加入     - Esc：返回标题
##   - 鼠标：点卡片加入/取消；底部按钮开始/返回
## 规则：首个加入者为房主；少于 2 人不可开始（按钮置灰）
## 手柄：按 A 加入并绑定该手柄 device id，最多支持 4 个手柄

class_name Lobby
extends Control

const SHAPE_IDS: Array[String] = ["shape_0", "shape_1", "shape_2", "shape_3"]

var _joined: Array[bool] = [false, false, false, false]
## 槽位綁定設備：-2 空位 / -1 鍵盤 / >=0 手柄 device id
var _slot_devices: Array[int] = [-2, -2, -2, -2]
var _cards: Array[PanelContainer] = []
var _card_states: Array[Control] = []
var _device_labels: Array[Label] = []

@onready var _count_label: Label = $Header/CountLabel
@onready var _card_row: HBoxContainer = $Center/CardRow
@onready var _start_btn: Button = $Footer/ButtonRow/StartButton
@onready var _back_btn: Button = $Footer/ButtonRow/BackButton
@onready var _host_hint: Label = $Header/HostHint
@onready var _start_hint: Label = $Footer/StartHint

func _ready() -> void:
	GameManager.current_stage = GameManager.GameStage.LOBBY
	_build_cards()
	_start_btn.pressed.connect(_try_start)
	_back_btn.pressed.connect(_on_back)
	_refresh()
	_pulse(_start_hint)

func _pulse(node: Control) -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(node, "modulate:a", 0.4, 0.6)
	tw.tween_property(node, "modulate:a", 1.0, 0.6)

# ---------------------------------------------------------------- 卡片构建
func _build_cards() -> void:
	for i in 4:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(300, 400)
		_cards.append(card)
		_card_row.add_child(card)
		_build_card_content(card, i)
		var st: Control = card.get_node("VBox/StateBox/StateLabel")
		_card_states.append(st)

func _build_card_content(card: PanelContainer, i: int) -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var avatar := TextureRect.new()
	avatar.name = "Avatar"
	avatar.custom_minimum_size = Vector2(120, 120)
	avatar.texture = ItemIcons.shape_icon(i)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(avatar)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = "P%d" % (i + 1)
	name_label.add_theme_font_size_override("font_size", 44)
	name_label.add_theme_color_override("font_color", PlayerConfig.get_color(i))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var device := Label.new()
	device.name = "DeviceLabel"
	device.text = "等待加入"
	device.add_theme_font_size_override("font_size", 18)
	device.add_theme_color_override("font_color", Color(0.7, 0.76, 0.86))
	device.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(device)
	_device_labels.append(device)

	var state_box := CenterContainer.new()
	state_box.name = "StateBox"
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.text = "等待加入"
	state_label.add_theme_font_size_override("font_size", 22)
	state_box.add_child(state_label)
	vbox.add_child(state_box)

	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.text = "键盘 [%d] / 手柄 A" % (i + 1)
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.add_theme_color_override("font_color", Color(0.5, 0.58, 0.7))
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(key_label)

	card.gui_input.connect(_on_card_gui_input.bind(i))

func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_toggle_slot(index)

# ---------------------------------------------------------------- 加入逻辑
func _joined_count() -> int:
	var n := 0
	for j in _joined:
		if j:
			n += 1
	return n

func _first_joined_index() -> int:
	for i in 4:
		if _joined[i]:
			return i
	return -1

## 找已綁定某設備的槽位（-1 表示鍵盤）
func _slot_for_device(device: int) -> int:
	for i in 4:
		if _joined[i] and _slot_devices[i] == device:
			return i
	return -1

func _toggle_slot(index: int) -> void:
	if _joined[index]:
		# 房主（首位加入者）不可自我取消；其余可退
		if index == _first_joined_index() and _joined_count() > 1:
			return
		_joined[index] = false
		SoundMgr.play("ui_click")
		_slot_devices[index] = -2
	else:
		_joined[index] = true
		# P1/P2 键盘；P3/P4 绑定对应手柄 device（调试用，正式加入走手柄 A）
		_slot_devices[index] = -1 if index <= 1 else index
		SoundMgr.play("join", true)
	_refresh()

## 加入下一个空位并绑定设备（-1 键盘只占 P1/P2）
func _join_with_device(device: int) -> void:
	if device == -1:
		for i in [0, 1]:
			if not _joined[i]:
				_joined[i] = true
				_slot_devices[i] = -1
				_refresh()
				return
		return
	for i in 4:
		if not _joined[i]:
			_joined[i] = true
			_slot_devices[i] = device
			_refresh()
			return

## 手柄玩家退出当前槽位（房主除外）
func _leave_slot(index: int) -> void:
	if not _joined[index]:
		return
	if index == _first_joined_index() and _joined_count() > 1:
		return
	_joined[index] = false
	_slot_devices[index] = -2
	_refresh()

func _remove_last() -> void:
	for i in range(3, -1, -1):
		if _joined[i] and i != _first_joined_index():
			_joined[i] = false
			_slot_devices[i] = -2
			_refresh()
			return

func _device_label(device: int) -> String:
	if device < 0:
		return "键盘 · Keyboard"
	var joy_name := Input.get_joy_name(device)
	if joy_name.is_empty():
		joy_name = "手柄 %d" % (device + 1)
	return "手柄 %d · %s" % [device + 1, joy_name]

func _refresh() -> void:
	var count := _joined_count()
	_count_label.text = "已加入 %d / 4" % count
	for i in 4:
		var card := _cards[i]
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.09, 0.11, 0.17, 0.92)
		style.corner_radius_top_left = 14
		style.corner_radius_top_right = 14
		style.corner_radius_bottom_right = 14
		style.corner_radius_bottom_left = 14
		if _joined[i]:
			style.border_color = PlayerConfig.get_color(i)
			style.set_border_width_all(3)
		else:
			style.border_color = Color(0.35, 0.4, 0.5, 0.5)
			style.set_border_width_all(2)
		card.add_theme_stylebox_override("panel", style)
		var avatar: TextureRect = card.get_node("VBox/Avatar")
		avatar.modulate = PlayerConfig.get_color(i) if _joined[i] else Color(0.35, 0.38, 0.45)
		var state := _card_states[i] as Label
		if _joined[i]:
			state.text = "已就绪 ✓"
			state.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55))
			_device_labels[i].text = _device_label(_slot_devices[i])
		else:
			state.text = "等待加入"
			state.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
			_device_labels[i].text = "等待加入"
	_host_hint.text = "房主：P%d（首个加入）" % (_first_joined_index() + 1) if count > 0 else "等待玩家加入…"
	var can_start := count >= 2
	_start_btn.disabled = not can_start
	if can_start:
		_start_btn.text = "开始游戏（房主确认）"
		_start_hint.text = "人数已满足：Enter / 手柄 A / 点击开始 → 主题展示"
		_start_hint.modulate = Color(0.55, 0.95, 1.0)
	else:
		_start_btn.text = "至少 2 人才能开始"
		_start_hint.text = "加入至少 2 名玩家后，房主确认开始（键盘 Enter / 手柄 A）"
		_start_hint.modulate = Color(0.62, 0.68, 0.8)

func _try_start() -> void:
	if _joined_count() < 2:
		return
	SoundMgr.play("confirm")
	GameManager.lobby_player_count = _joined_count()
	# 按槽位顺序压缩设备列表，与出生 player_index 对齐
	var devices: Array[int] = []
	for i in 4:
		if _joined[i]:
			devices.append(_slot_devices[i])
	GameManager.player_devices = devices
	get_tree().change_scene_to_file("res://scenes/levels/room_stage_battle.tscn")

func _on_back() -> void:
	GameManager.enter_title()

# ---------------------------------------------------------------- 输入
func _event_device(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).device
	if event is InputEventJoypadMotion:
		return (event as InputEventJoypadMotion).device
	return -1

func _on_accept(device: int) -> void:
	if device == -1:
		# 键盘 Enter：先补 P1/P2 键盘槽位，已 >=2 人则开始
		if _joined_count() >= 2:
			_try_start()
		else:
			_join_with_device(-1)
		return
	# 手柄 A
	var existing := _slot_for_device(device)
	if existing >= 0:
		# 已加入的手柄再按 A = 房主确认开始
		if _joined_count() >= 2:
			_try_start()
		return
	if _joined_count() >= 4:
		return
	_join_with_device(device)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	# 手柄 A：加入或（已加入）房主开始
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
		_on_accept((event as InputEventJoypadButton).device)
		return
	# 手柄 B：已加入则退出当前槽位，未加入则返回标题
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B:
		var dev := (event as InputEventJoypadButton).device
		var slot := _slot_for_device(dev)
		if slot >= 0:
			_leave_slot(slot)
		else:
			_on_back()
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		return
	if event.is_action_pressed("ui_accept"):
		_on_accept(_event_device(event))
		return
	if event is InputEventKey:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_1: _toggle_slot(0)
			KEY_2: _toggle_slot(1)
			KEY_3: _toggle_slot(2)
			KEY_4: _toggle_slot(3)
			KEY_BACKSPACE, KEY_X: _remove_last()
