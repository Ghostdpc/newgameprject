## 职责：单个玩家卡片（四角之一）
## 组成：泡泡外框(染色) + 小人身体(染色) + 眼睛 + P#字标(染色) + 六边形道具槽
## 附加：皇冠（冠军）、总分大字 + +xx 弹字（结算刷分）。
## 零件布局在 battle_hud.tscn 中独立预置（四个卡片各角可分别拖动细调），
## 本脚本只负责：染色、换贴图、动画、数据逻辑；不翻转、不对齐、不覆盖坐标。

class_name PlayerPanel
extends Control

const TINT_SHADER := preload("res://resources/ui/card_tint.gdshader")
const FONT_SCORE := preload("res://assets/fonts/Kaph-Regular.otf")
const FONT_SCORE_ITALIC := preload("res://assets/fonts/Kaph-Italic.otf")
const COLOR_OUTLINE := Color(0.02, 0.02, 0.03, 1)

var player_index: int = 0
var player_color: Color = Color.WHITE

@onready var _bubble: TextureRect = $Bubble
@onready var _body: TextureRect = $Body
@onready var _eyes: TextureRect = $Eyes
@onready var _label: TextureRect = $Label
@onready var _hex: TextureRect = $Hex
@onready var _item_icon: TextureRect = $ItemIcon
@onready var _crown: TextureRect = $Crown
@onready var _total_label: Label = $TotalLabel

func setup(index: int, color: Color) -> void:
	player_index = index
	player_color = color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_tint(_bubble)
	_apply_tint(_body)
	_apply_tint(_label)
	_setup_label_texture()
	_crown.texture = ItemIcons.load_icon("crown")
	_crown.hide()

func _is_right() -> bool:
	return player_index % 2 == 1

## P# 字标：每玩家一张图（card_p1~p4），尺寸/位置由编辑器手摆，这里只换贴图
func _setup_label_texture() -> void:
	_label.texture = ItemIcons.load_icon("card_p%d" % (player_index + 1))

func _apply_tint(rect: TextureRect) -> void:
	var m := ShaderMaterial.new()
	m.shader = TINT_SHADER
	m.set_shader_parameter("tint", player_color)
	rect.material = m

# ---------------------------------------------------------------- 道具槽
func set_item(icon: Texture2D) -> void:
	if icon == null:
		_item_icon.modulate.a = 0.0
		_item_icon.texture = null
		return
	_item_icon.texture = icon
	_item_icon.pivot_offset = _item_icon.size * 0.5
	_item_icon.modulate.a = 1.0
	_item_icon.scale = Vector2(1.5, 1.5)
	var tw := create_tween()
	tw.tween_property(_item_icon, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func flash_item_used() -> void:
	if _item_icon.texture == null:
		return
	var tw := create_tween()
	tw.tween_property(_item_icon, "self_modulate", Color(0.4, 0.4, 0.4, 0.6), 0.1)
	tw.tween_property(_item_icon, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		_item_icon.texture = null
		_item_icon.self_modulate = Color.WHITE)

# ---------------------------------------------------------------- 冠军皇冠
func show_crown(on: bool) -> void:
	if not on:
		_crown.hide()
		return
	_crown.show()
	# 不碰 pivot_offset/scale：Crown 带 rotation，改 pivot 会位移。用淡入。
	_crown.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_crown, "modulate:a", 1.0, 0.3)

# ---------------------------------------------------------------- 结算刷分
## 总分更新：先放大再回弹（分数更新感）
func set_total(target: float) -> void:
	_total_label.show()
	_total_label.text = "%.0f" % target
	_total_label.pivot_offset = _total_label.size * 0.5
	_total_label.scale = Vector2(1.35, 1.35)
	var tw := create_tween()
	tw.tween_property(_total_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## +xx 弹字：scale 先放大再缩小（不上浮），玩家色
func pop_plus(score: float) -> void:
	if score <= 0.01:
		return
	var plus := Label.new()
	plus.add_theme_font_override("font", FONT_SCORE_ITALIC)
	plus.text = "+%.0f" % score
	plus.add_theme_font_size_override("font_size", 42)
	plus.add_theme_color_override("font_color", player_color)
	plus.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	plus.add_theme_constant_override("outline_size", 10)
	var bx := _bubble.position.x
	var by := _bubble.position.y
	plus.position = Vector2(
		bx + _bubble.size.x + 4.0 if not _is_right() else bx - 84.0,
		by + 30.0)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plus)
	plus.pivot_offset = plus.size * 0.5
	plus.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(plus, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(plus, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(plus, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tw.tween_callback(plus.queue_free)

## -xx 弹字（被炸等惩罚）：红色，与 pop_plus 同动效
func pop_minus(score: float) -> void:
	if score <= 0.01:
		return
	var minus := Label.new()
	minus.add_theme_font_override("font", FONT_SCORE_ITALIC)
	minus.text = "-%.0f" % score
	minus.add_theme_font_size_override("font_size", 42)
	minus.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))
	minus.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	minus.add_theme_constant_override("outline_size", 10)
	var bx := _bubble.position.x
	var by := _bubble.position.y
	minus.position = Vector2(
		bx + _bubble.size.x + 4.0 if not _is_right() else bx - 84.0,
		by + 30.0)
	minus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minus)
	minus.pivot_offset = minus.size * 0.5
	minus.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(minus, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(minus, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(minus, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tw.tween_callback(minus.queue_free)

## 复位结算状态（新一轮开始前调用）
func reset_scoring() -> void:
	_total_label.text = "0"
	_total_label.scale = Vector2.ONE
	_total_label.hide()
	show_crown(false)

## 进入结算模式：隐藏战斗用道具槽（总分由 set_total 显示）
func enter_scoring_style() -> void:
	_hex.hide()
	_item_icon.hide()

## 退出结算模式：恢复道具槽
func exit_scoring_style() -> void:
	_hex.show()
	_item_icon.show()
