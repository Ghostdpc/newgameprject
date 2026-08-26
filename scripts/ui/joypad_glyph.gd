## 手柄按键 → 图标/文字 映射（改键界面与 loading 提示共用）。
## 面键（A/B/X/Y → ✕/○/□/△）有图标；肩键/扳机/摇杆等无图标，回退文字。
## 通过 preload 引用，避免依赖全局类缓存。

const ICON_CROSS: Texture2D = preload("res://assets/textures/ui/load_hint_cross.png")
const ICON_CIRCLE: Texture2D = preload("res://assets/textures/ui/load_hint_circle.png")
const ICON_SQUARE: Texture2D = preload("res://assets/textures/ui/loading_hint_square.png")
const ICON_TRIANGLE: Texture2D = preload("res://assets/textures/ui/load_hint_triangle.png")

static func icon_for_event(ev: InputEvent) -> Texture2D:
	if ev is InputEventJoypadButton:
		match (ev as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: return ICON_CROSS
			JOY_BUTTON_B: return ICON_CIRCLE
			JOY_BUTTON_X: return ICON_SQUARE
			JOY_BUTTON_Y: return ICON_TRIANGLE
	return null

static func text_for_event(ev: InputEvent) -> String:
	if ev is InputEventJoypadButton:
		return button_text((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return motion_text(m.axis, m.axis_value)
	return ""

static func button_text(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "Select"
		JOY_BUTTON_GUIDE: return "Guide"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "↑"
		JOY_BUTTON_DPAD_DOWN: return "↓"
		JOY_BUTTON_DPAD_LEFT: return "←"
		JOY_BUTTON_DPAD_RIGHT: return "→"
	return "按键%d" % index

static func motion_text(axis: int, value: float) -> String:
	var dir := "+" if value >= 0.0 else "-"
	match axis:
		JOY_AXIS_LEFT_X: return "左摇杆X" + dir
		JOY_AXIS_LEFT_Y: return "左摇杆Y" + dir
		JOY_AXIS_RIGHT_X: return "右摇杆X" + dir
		JOY_AXIS_RIGHT_Y: return "右摇杆Y" + dir
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return "轴%d" % axis

## 取该 action 的首个手柄事件（键盘事件忽略）
static func find_joypad_event(action: String) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return ev
	return null
