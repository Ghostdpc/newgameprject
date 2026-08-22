## 职责：S0 标题界面 —— 3D 房间背景（缓慢环绕相机）+ 模糊滤镜 + Logo/开始/退出 图片按钮
## 输入：开始按钮 / 任意确认键 / 手柄非○键 → 进入大厅；退出按钮 / Esc / 手柄○ → 退出
class_name MainMenu
extends Node

@onready var _pad_start: TextureRect = $UILayer/UIRoot/Center/Menu/StartCol/PadIcon
@onready var _pad_quit: TextureRect = $UILayer/UIRoot/Center/Menu/QuitCol/PadIcon
@onready var _start_btn: TextureButton = $UILayer/UIRoot/Center/Menu/StartCol/StartButton
@onready var _quit_btn: TextureButton = $UILayer/UIRoot/Center/Menu/QuitCol/QuitButton

const _SCALE_NORMAL := Vector2.ONE
const _SCALE_HOVER := Vector2(1.12, 1.12)
const _SCALE_PRESS := Vector2(0.94, 0.94)

func _ready() -> void:
	_pulse(_pad_start)
	_pulse(_pad_quit)
	_setup_button_feedback(_start_btn)
	_setup_button_feedback(_quit_btn)

## 图片按钮：悬停放大、按下缩小、移出复原（缩放绕中心）
func _setup_button_feedback(btn: TextureButton) -> void:
	if not btn:
		return
	btn.pivot_offset = btn.custom_minimum_size * 0.5
	btn.mouse_entered.connect(func() -> void: _scale_to(btn, _SCALE_HOVER))
	btn.mouse_exited.connect(func() -> void: _scale_to(btn, _SCALE_NORMAL))
	btn.button_down.connect(func() -> void: _scale_to(btn, _SCALE_PRESS))
	btn.button_up.connect(func() -> void:
		_scale_to(btn, _SCALE_HOVER if btn.is_hovered() else _SCALE_NORMAL))

func _scale_to(btn: TextureButton, target: Vector2) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", target, 0.12)

func _pulse(node: CanvasItem) -> void:
	if not node:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(node, "modulate:a", 0.45, 0.6)
	tw.tween_property(node, "modulate:a", 1.0, 0.6)

func _on_start_pressed() -> void:
	GameManager.enter_lobby()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		# 手柄○（PS 上映射为 JOY_BUTTON_B）→ 退出，其余按钮 → 开始
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			get_tree().quit()
		else:
			GameManager.enter_lobby()
		return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		GameManager.enter_lobby()
