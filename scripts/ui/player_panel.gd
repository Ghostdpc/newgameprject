## 职责：单个玩家角标面板（四角之一）
## 内容：颜色+编号+形状头像、服装 3 槽（头/身/手）、道具槽
## 三重辨识：颜色 + 编号 + 形状

class_name PlayerPanel
extends PanelContainer

## 形状字符（P1圆 / P2三角 / P3方 / P4菱）
const SHAPE_GLYPHS: Array[String] = ["●", "▲", "■", "◆"]

var player_index: int = 0
var player_color: Color = Color.WHITE

var _name_label: Label
var _outfit_slots: Array[TextureRect] = []
var _item_slot: TextureRect

func setup(index: int, color: Color) -> void:
	player_index = index
	player_color = color
	custom_minimum_size = Vector2(200, 84)
	_build_ui()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	hbox.add_child(_build_avatar())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.text = "P%d" % (player_index + 1)
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", player_color)
	vbox.add_child(_name_label)

	var outfit_row := HBoxContainer.new()
	outfit_row.add_theme_constant_override("separation", 4)
	vbox.add_child(outfit_row)
	for i in 3:
		var slot := _make_slot(Vector2(22, 22))
		outfit_row.add_child(slot)
		_outfit_slots.append(slot)

	_item_slot = _make_slot(Vector2(30, 30))
	vbox.add_child(_item_slot)

func _build_avatar() -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(56, 56)

	var bg := ColorRect.new()
	bg.color = player_color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(bg)

	var shape := Label.new()
	shape.text = SHAPE_GLYPHS[player_index % SHAPE_GLYPHS.size()]
	shape.add_theme_font_size_override("font_size", 34)
	shape.add_theme_color_override("font_color", Color.BLACK)
	shape.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shape.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shape.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(shape)
	return box

func _make_slot(size: Vector2) -> TextureRect:
	var slot := TextureRect.new()
	slot.custom_minimum_size = size
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.65)
	style.border_color = Color(0.55, 0.55, 0.6, 0.9)
	style.set_border_width_all(1)
	slot.add_theme_stylebox_override("panel", style)
	return slot

## 设置服装槽图标（item_id 为空则清空）
func set_outfit_slot(slot: int, icon: Texture2D) -> void:
	if slot < 0 or slot >= _outfit_slots.size():
		return
	_outfit_slots[slot].texture = icon

## 设置道具图标（null 则清空）
func set_item(icon: Texture2D) -> void:
	_item_slot.texture = icon
