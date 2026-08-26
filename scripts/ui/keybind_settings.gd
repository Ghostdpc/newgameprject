## 職責：鍵位設置界面 —— 列出可改鍵 action，點擊後錄入新鍵（鍵盤/手柄），
## 修改 InputMap 並持久化到 data/configs/keybindings.json
## 鍵盤 P1/P2 分開；手柄為全局一組（改一次全手柄生效，不綁 device）

class_name KeybindSettings
extends Control

const CONFIG_PATH: String = "res://data/configs/keybindings.json"

## 可改鍵項：group 為分組標題，其餘為 {action, label}
const _ENTRIES: Array = [
	{"group": "玩家 1（鍵盤）"},
	{"action": "move_up_p1", "label": "上"},
	{"action": "move_down_p1", "label": "下"},
	{"action": "move_left_p1", "label": "左"},
	{"action": "move_right_p1", "label": "右"},
	{"action": "jump_p1", "label": "跳躍"},
	{"action": "dive_p1", "label": "飛撲"},
	{"action": "pickup_p1", "label": "拾取／使用"},
	{"action": "use_item_p1", "label": "使用道具"},
	{"action": "grab_p1", "label": "抓取場景物"},
	{"action": "suicide_p1", "label": "自殺（測試）"},

	{"group": "玩家 2（鍵盤）"},
	{"action": "move_up_p2", "label": "上"},
	{"action": "move_down_p2", "label": "下"},
	{"action": "move_left_p2", "label": "左"},
	{"action": "move_right_p2", "label": "右"},
	{"action": "jump_p2", "label": "跳躍"},
	{"action": "dive_p2", "label": "飛撲"},
	{"action": "pickup_p2", "label": "拾取／使用"},
	{"action": "use_item_p2", "label": "使用道具"},
	{"action": "grab_p2", "label": "抓取場景物"},
	{"action": "suicide_p2", "label": "自殺（測試）"},

	{"group": "手柄（全局）"},
	{"action": "joy_jump", "label": "跳躍"},
	{"action": "joy_dive", "label": "飛撲"},
	{"action": "joy_pickup", "label": "拾取／使用"},
	{"action": "joy_use", "label": "使用道具"},
	{"action": "joy_grab", "label": "抓取場景物"},
	{"action": "joy_suicide", "label": "自殺（測試）"},
]

var _list: VBoxContainer
var _list_container: ScrollContainer
var _hint_label: Label
var _recording_action: String = ""
var _recording_row: HBoxContainer = null

func _ready() -> void:
	_list_container = $Panel/Scroll
	_list = $Panel/Scroll/List
	_hint_label = $Panel/HintLabel
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
		btn.text = _action_display(entry["action"])
		btn.custom_minimum_size = Vector2(240, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(_on_bind_pressed.bind(entry["action"], btn))
		row.add_child(label)
		row.add_child(btn)
		_list.add_child(row)

## action 的當前綁定顯示（多事件全列）
func _action_display(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "（未綁定）"
	var names: Array[String] = []
	for ev in events:
		names.append(_event_display(ev))
	return " / ".join(names)

## 單個事件的簡短顯示名
func _event_display(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	if ev is InputEventJoypadButton:
		return "手柄按鈕 %d" % (ev as InputEventJoypadButton).button_index
	if ev is InputEventJoypadMotion:
		return "手柄軸 %d" % (ev as InputEventJoypadMotion).axis
	return str(ev)

func _on_bind_pressed(action: String, btn: Button) -> void:
	if _recording_action != "":
		_cancel_recording()
	_recording_action = action
	_recording_row = btn.get_parent() as HBoxContainer
	btn.text = "按下新鍵…"
	btn.modulate = Color(1, 0.85, 0.4)
	_refresh_hint()

func _cancel_recording() -> void:
	if _recording_action == "":
		return
	var evs := InputMap.action_get_events(_recording_action)
	var text := "（未綁定）" if evs.is_empty() else _event_display(evs[0])
	var btn := _recording_row.get_child(1) as Button
	btn.text = text
	btn.modulate = Color.WHITE
	_recording_action = ""
	_recording_row = null
	_refresh_hint()

func _refresh_hint() -> void:
	if _recording_action != "":
		_hint_label.text = "正在為「%s」錄入新鍵…按 Esc 取消，按 Enter 清除綁定" % _recording_action
	else:
		_hint_label.text = "點擊按鈕後按下新鍵；Backspace 清除綁定；Esc 返回標題"

func _unhandled_input(event: InputEvent) -> void:
	if _recording_action != "":
		_handle_recording(event)
		return
	if event.is_action_pressed("ui_cancel"):
		_save()
		GameManager.enter_title()
		get_viewport().set_input_as_handled()

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

## 綁定新事件到 action（event 為 null 代表清空）。替換全部現有事件。
func _bind_event(action: String, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	if event != null:
		InputMap.action_add_event(action, event)
	var btn := _recording_row.get_child(1) as Button
	btn.text = _action_display(action)
	btn.modulate = Color.WHITE
	_recording_action = ""
	_recording_row = null
	_refresh_hint()
	SoundMgr.play("confirm")

## 保存到 JSON：action → [事件數據]
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
		push_error("KeybindSettings: 無法寫入 keybindings.json")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

## 事件 → 可持久化數據
func _event_to_data(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "physical_keycode": (ev as InputEventKey).physical_keycode}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button_index": (ev as InputEventJoypadButton).button_index}
	if ev is InputEventJoypadMotion:
		return {"type": "joy_motion", "axis": (ev as InputEventJoypadMotion).axis, "axis_value": (ev as InputEventJoypadMotion).axis_value}
	return {"type": "unknown"}

## 啟動時從配置恢復綁定（autoload 或入口調用）
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
