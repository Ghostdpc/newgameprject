## 职责：单个玩家卡片（四角之一，新设计）
## 组成：泡泡外框(染色) + 小人身体(染色) + 眼睛 + P#字标(染色) + 六边形道具槽
## 附加：皇冠（S7 冠军）、评分面板（S6 逐维刷分）。
## 零件布局在 player_panel.tscn 中可视化摆放（策划可拖动），
## 本脚本只负责：染色、左右/上下翻转、镜像定位、动画、数据逻辑。

class_name PlayerPanel
extends Control

const TINT_SHADER := preload("res://resources/ui/card_tint.gdshader")

# ---- 卡片尺寸基准（用于镜像定位计算）----
const CARD_W := 240.0
const LABEL_H := 68.0

var player_index: int = 0
var player_color: Color = Color.WHITE

@onready var _bubble: TextureRect = $Bubble
@onready var _body: TextureRect = $Body
@onready var _eyes: TextureRect = $Eyes
@onready var _label: TextureRect = $Label
@onready var _hex: TextureRect = $Hex
@onready var _item_icon: TextureRect = $ItemIcon
@onready var _crown: TextureRect = $Crown
@onready var _score_panel: Panel = $ScorePanel
@onready var _score_box: VBoxContainer = $ScorePanel/VBox

var _dim_labels: Dictionary = {}
var _total_label: Label

func setup(index: int, color: Color) -> void:
	player_index = index
	player_color = color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_tint(_bubble)
	_apply_tint(_body)
	_apply_tint(_label)
	_setup_label_texture()
	_apply_orientation()
	_apply_score_style()

func _is_right() -> bool:
	return player_index % 2 == 1

func _is_bottom() -> bool:
	return player_index >= 2

## P# 字标：每玩家一张图（card_p1~p4），按图宽高比重算宽度
func _setup_label_texture() -> void:
	_label.texture = ItemIcons.load_icon("card_p%d" % (player_index + 1))
	var lw := LABEL_H * _label.texture.get_size().x / _label.texture.get_size().y
	_label.size = Vector2(lw, LABEL_H)

## 泡泡翻转 + 字标/六边形镜像（右/下角卡尾巴朝屏幕中心）
func _apply_orientation() -> void:
	_bubble.flip_h = _is_right()
	_bubble.flip_v = _is_bottom()

	if _is_right():
		_label.position.x = CARD_W - _label.size.x + 16.0
		_hex.position.x = CARD_W - _hex.size.x + 12.0
	_item_icon.position = _hex.position + Vector2(
		_hex.size.x * 0.5 - _item_icon.size.x * 0.5,
		_hex.size.y * 0.5 - _item_icon.size.y * 0.5)

func _apply_score_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.82)
	style.border_color = Color(player_color.r, player_color.g, player_color.b, 0.8)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	_score_panel.add_theme_stylebox_override("panel", style)

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
	_crown.pivot_offset = Vector2(30, 30)
	_crown.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(_crown, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- S6 评分
func begin_scoring(dim_defs: Array) -> void:
	for c in _score_box.get_children():
		c.queue_free()
	_dim_labels.clear()
	for d in dim_defs:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(d[1])
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var score_label := Label.new()
		score_label.text = "—"
		score_label.add_theme_font_size_override("font_size", 15)
		score_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
		row.add_child(score_label)
		row.modulate.a = 0.0
		_score_box.add_child(row)
		_dim_labels[String(d[0])] = score_label
	_total_label = Label.new()
	_total_label.text = "总分 0"
	_total_label.add_theme_font_size_override("font_size", 19)
	_total_label.add_theme_color_override("font_color", player_color.lightened(0.35))
	_score_box.add_child(_total_label)
	_score_panel.show()

func reveal_dim(key: String, score: float) -> void:
	var label: Label = _dim_labels.get(key)
	if label == null:
		return
	label.text = "%.0f" % score
	var row := label.get_parent() as Control
	row.modulate.a = 1.0
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(1.8, 1.8)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_total(target: float) -> void:
	if _total_label == null:
		return
	var tw := create_tween()
	tw.tween_method(func(v: float): _total_label.text = "总分 %.0f" % v,
		0.0, target, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func clear_scoring() -> void:
	if _score_box:
		for c in _score_box.get_children():
			c.queue_free()
		_dim_labels.clear()
	if _score_panel:
		_score_panel.hide()
	if _crown:
		_crown.hide()
