## 职责：键位设置界面 —— 列出可改键 action，点击后录入新键（键盘/手柄），
## 修改 InputMap 并持久化到 data/configs/keybindings.json
## 键盘 P1/P2 分开；手柄为全局一组（改一次全手柄生效，不绑 device）

class_name KeybindSettings
extends Control

const CONFIG_PATH: String = "res://data/configs/keybindings.json"
const JoypadGlyph = preload("res://scripts/ui/joypad_glyph.gd")

## 可改键项：group 为分组标题，其余为 {action, label}
const _ENTRIES: Array = [
	{"group": "玩家 1（键盘）"},
	{"action": "move_up_p1", "label": "上"},
	{"action": "move_down_p1", "label": "下"},
	{"action": "move_left_p1", "label": "左"},
	{"action": "move_right_p1", "label": "右"},
	{"action": "jump_p1", "label": "跳跃"},
	{"action": "dive_p1", "label": "飞扑"},
	{"action": "pickup_p1", "label": "拾取／使用"},
	{"action": "use_item_p1", "label": "使用道具"},
	{"action": "grab_p1", "label": "抓取场景物"},
	{"action": "suicide_p1", "label": "自杀（测试）"},

	{"group": "玩家 2（键盘）"},
	{"action": "move_up_p2", "label": "上"},
	{"action": "move_down_p2", "label": "下"},
	{"action": "move_left_p2", "label": "左"},
	{"action": "move_right_p2", "label": "右"},
	{"action": "jump_p2", "label": "跳跃"},
	{"action": "dive_p2", "label": "飞扑"},
	{"action": "pickup_p2", "label": "拾取／使用"},
	{"action": "use_item_p2", "label": "使用道具"},
	{"action": "grab_p2", "label": "抓取场景物"},
	{"action": "suicide_p2", "label": "自杀（测试）"},

	{"group": "手柄（全局）"},
	{"action": "joy_jump", "label": "跳跃"},
	{"action": "joy_dive", "label": "飞扑"},
	{"action": "joy_pickup", "label": "拾取／使用"},
	{"action": "joy_use", "label": "使用道具"},
	{"action": "joy_grab", "label": "抓取场景物"},
	{"action": "joy_suicide", "label": "自杀（测试）"},
]

var _list: VBoxContainer
var _list_container: ScrollContainer
var _hint_label: Label
var _recording_action: String = ""
var _recording_row: HBoxContainer = null

func _ready() -> void:
	_list_container = $Panel/Margin/VBox/Scroll
	_list = $Panel/Margin/VBox/Scroll/List
	_hint_label = $Panel/Margin/VBox/HintLabel
	_build_rows()

func _build_rows() -> void:
	for child in _list.get_children():
		child.queue_free()
	for entry in _ENTRIES:
		if entry.has("group"):
			var header := Label.new()
			header.text = "■ " + entry["group"]
			header.add_theme_font_size_override("font_size", 26)
			header.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
			header.add_theme_constant_override("outline_size", 0)
			_list.add_child(header)
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = entry["label"]
		label.custom_minimum_size = Vector2(180, 0)
		label.add_theme_font_size_override("font_size", 22)
		var btn := Button.new()
		_set_button_display(btn, entry["action"])
		btn.custom_minimum_size = Vector2(240, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(_on_bind_pressed.bind(entry["action"], btn))
		row.add_child(label)
		row.add_child(btn)
		_list.add_child(row)

## 按钮显示：手柄面键用图标，其余（键盘/肩键/扳机等）回退文字
func _set_button_display(btn: Button, action: String) -> void:
	var events := InputMap.action_get_events(action)
	btn.icon = null
	btn.expand_icon = false
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.text = ""
	if events.is_empty():
		btn.text = "（未绑定）"
		return
	var ev: InputEvent = events[0]
	if ev is InputEventKey:
		btn.text = OS.get_keycode_string((ev as InputEventKey).physical_keycode)
		return
	var icon := JoypadGlyph.icon_for_event(ev)
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
		return
	btn.text = JoypadGlyph.text_for_event(ev)
	if btn.text.is_empty():
		btn.text = str(ev)

func _on_bind_pressed(action: String, btn: Button) -> void:
	if _recording_action != "":
		_cancel_recording()
	_recording_action = action
	_recording_row = btn.get_parent() as HBoxContainer
	btn.icon = null
	btn.expand_icon = false
	btn.text = "按下新键…"
	btn.modulate = Color(1, 0.85, 0.4)
	_refresh_hint()

func _cancel_recording() -> void:
	if _recording_action == "":
		return
	var btn := _recording_row.get_child(1) as Button
	_set_button_display(btn, _recording_action)
	btn.modulate = Color.WHITE
	_recording_action = ""
	_recording_row = null
	_refresh_hint()

func _refresh_hint() -> void:
	if _recording_action != "":
		_hint_label.text = "正在为「%s」录入新键…按 Esc 取消，按 Enter 清除绑定" % _recording_action
	else:
		_hint_label.text = "点击按钮后按下新键；Backspace 清除绑定；Esc 返回标题"

func _unhandled_input(event: InputEvent) -> void:
	if _recording_action != "":
		_handle_recording(event)
		return
	if event.is_action_pressed("ui_cancel"):
		_save()
		get_viewport().set_input_as_handled()
		GameManager.enter_title()

func _handle_recording(event: InputEvent) -> void:
	var action := _recording_action
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if key_ev.physical_keycode == KEY_ESCAPE:
				_cancel_recording()
			elif key_ev.physical_keycode == KEY_BACKSPACE:
				_bind_event(action, null)
			else:
				_bind_event(action, event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_bind_event(action, event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if absf(jm.axis_value) > 0.5:
			_bind_event(action, event)
		get_viewport().set_input_as_handled()

## 绑定新事件到 action（event 为 null 代表清空）。替换全部现有事件。
func _bind_event(action: String, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	if event != null:
		InputMap.action_add_event(action, event)
	var btn := _recording_row.get_child(1) as Button
	_set_button_display(btn, action)
	btn.modulate = Color.WHITE
	_recording_action = ""
	_recording_row = null
	_refresh_hint()
	SoundMgr.play("confirm")

## 保存到 JSON：action → [事件数据]
func _save() -> void:
	var data: Dictionary = {}
	for entry in _ENTRIES:
		if not entry.has("action"):
			continue
		var action: String = entry["action"]
		var events: Array = []
		for ev in InputMap.action_get_events(action):
			events.append(_event_to_data(ev))
		data[action] = events
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		push_error("KeybindSettings: 无法写入 keybindings.json")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

## 事件 → 可持久化数据
func _event_to_data(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "physical_keycode": (ev as InputEventKey).physical_keycode}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button_index": (ev as InputEventJoypadButton).button_index}
	if ev is InputEventJoypadMotion:
		return {"type": "joy_motion", "axis": (ev as InputEventJoypadMotion).axis, "axis_value": (ev as InputEventJoypadMotion).axis_value}
	return {"type": "unknown"}

## 启动时从配置恢复绑定（autoload 或入口调用）
static func load_bindings() -> void:
	var path := "res://data/configs/keybindings.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	for action in (parsed as Dictionary):
		if not InputMap.has_action(action):
			continue
		var events: Array = parsed[action]
		InputMap.action_erase_events(action)
		for ev_data in events:
			var ev := _data_to_event(ev_data)
			if ev != null:
				InputMap.action_add_event(action, ev)

static func _data_to_event(data: Dictionary) -> InputEvent:
	match data.get("type"):
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = data["physical_keycode"]
			return ev
		"joy_button":
			var ev := InputEventJoypadButton.new()
			ev.button_index = data["button_index"]
			return ev
		"joy_motion":
			var ev := InputEventJoypadMotion.new()
			ev.axis = data["axis"]
			ev.axis_value = data["axis_value"]
			return ev
	return null
