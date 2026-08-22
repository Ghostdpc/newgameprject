## 职责：S0 标题界面 —— 中央 Logo + 底部确认提示，任意确认键进入大厅（交互文档 §4 标题）

class_name MainMenu
extends Control

@onready var _start_hint: Label = $Center/VBox/StartHint
@onready var _shape_row: HBoxContainer = $Center/VBox/ShapeRow

func _ready() -> void:
	_pulse_hint()
	_apply_shape_colors()
	gui_input.connect(_on_gui_input)

## 主界面 4 个形状图标颜色跟随玩家配色配置
func _apply_shape_colors() -> void:
	if not _shape_row:
		return
	var shapes := _shape_row.get_children()
	for i in shapes.size():
		var tex := shapes[i] as TextureRect
		if tex:
			tex.modulate = PlayerConfig.get_color(i)

## 鼠标点击任意位置也可开始（手柄/键盘走 _unhandled_input）
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		GameManager.enter_lobby()

func _pulse_hint() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_start_hint, "modulate:a", 0.35, 0.55)
	tw.tween_property(_start_hint, "modulate:a", 1.0, 0.55)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	# 任意键盘键（非 Esc）或手柄任意按钮 → 进入大厅
	if event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		GameManager.enter_lobby()

func _on_quit_pressed() -> void:
	get_tree().quit()
