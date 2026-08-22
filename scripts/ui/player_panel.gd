## 职责：单个玩家角标面板（四角之一）
## 内容：颜色+编号+形状头像（三重辨识）、服装 3 槽（头/身/手）、道具槽、
##       皇冠（冠军）、评分行（S6 逐维刷分）。

class_name PlayerPanel
extends PanelContainer

const OUTFIT_SLOT_COUNT := 3

var player_index: int = 0
var player_color: Color = Color.WHITE

var _avatar_bg: ColorRect
var _avatar_shape: TextureRect
var _name_label: Label
var _crown: TextureRect
# 槽位：[0..2] 服装（头/身/手），[3] 道具
var _slot_ghosts: Array[TextureRect] = []
var _slot_icons: Array[TextureRect] = []
var _score_box: VBoxContainer
var _total_label: Label
var _dim_labels: Dictionary = {}   # key -> ScoreLabel
var _shown_total: float = 0.0

static var SHAPE_IDS: Array[String] = ["shape_0", "shape_1", "shape_2", "shape_3"]

func setup(index: int, color: Color) -> void:
	player_index = index
	player_color = color
	custom_minimum_size = Vector2(240, 0)
	_build_style()
	_build_ui()

func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.085, 0.13, 0.88)
	style.border_color = player_color
	style.set_border_width_all(2)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)

func _build_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	add_child(hbox)

	hbox.add_child(_build_avatar())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.text = "P%d" % (player_index + 1)
	_name_label.add_theme_font_size_override("font_size", 24)
	_name_label.add_theme_color_override("font_color", player_color)
	vbox.add_child(_name_label)

	# 服装 3 槽（头/身/手）
	var outfit_row := HBoxContainer.new()
	outfit_row.add_theme_constant_override("separation", 6)
	vbox.add_child(outfit_row)
	for i in OUTFIT_SLOT_COUNT:
		outfit_row.add_child(_build_slot(Vector2(30, 30), i))

	# 道具槽（单槽，稍大）
	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 6)
	vbox.add_child(item_row)
	item_row.add_child(_build_slot(Vector2(38, 38), 3))
	var item_hint := Label.new()
	item_hint.text = "道具"
	item_hint.add_theme_font_size_override("font_size", 14)
	item_hint.add_theme_color_override("font_color", Color(0.6, 0.66, 0.76))
	item_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item_row.add_child(item_hint)

	# 评分区（S6 才展开）
	_score_box = VBoxContainer.new()
	_score_box.add_theme_constant_override("separation", 2)
	_score_box.hide()
	vbox.add_child(_score_box)

func _build_avatar() -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(64, 64)

	_avatar_bg = ColorRect.new()
	_avatar_bg.color = player_color
	_avatar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(_avatar_bg)

	_avatar_shape = TextureRect.new()
	_avatar_shape.texture = ItemIcons.load_icon(SHAPE_IDS[player_index % 4])
	_avatar_shape.self_modulate = Color(0.06, 0.07, 0.1, 0.95)
	_avatar_shape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_shape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar_shape.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar_shape.offset_left = 8.0
	_avatar_shape.offset_top = 8.0
	_avatar_shape.offset_right = -8.0
	_avatar_shape.offset_bottom = -8.0
	box.add_child(_avatar_shape)

	# 皇冠（冠军，默认隐藏）
	_crown = TextureRect.new()
	_crown.texture = ItemIcons.load_icon("crown")
	_crown.custom_minimum_size = Vector2(40, 40)
	_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crown.position = Vector2(12, -34)
	_crown.hide()
	box.add_child(_crown)
	return box

func _build_slot(size: Vector2, _slot_index: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = size

	var bg := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.8)
	style.border_color = Color(0.45, 0.5, 0.6, 0.7)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)

	# 空槽轮廓
	var ghost := TextureRect.new()
	ghost.texture = ItemIcons.slot_icon(_slot_index) if _slot_index < OUTFIT_SLOT_COUNT \
		else ItemIcons.load_icon("slot_2")
	ghost.modulate = Color(1, 1, 1, 0.4)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	ghost.offset_left = 3.0
	ghost.offset_top = 3.0
	ghost.offset_right = -3.0
	ghost.offset_bottom = -3.0
	holder.add_child(ghost)
	_slot_ghosts.append(ghost)

	# 实际图标（装备后显示）
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2.0
	icon.offset_top = 2.0
	icon.offset_right = -2.0
	icon.offset_bottom = -2.0
	icon.modulate.a = 0.0
	holder.add_child(icon)
	_slot_icons.append(icon)
	return holder

# ---------------------------------------------------------------- 服装/道具
## 装备即生效：旧图标淡出、新图标弹入（交互文档 §5.3）
func set_outfit_slot(slot: int, icon: Texture2D) -> void:
	if slot < 0 or slot >= OUTFIT_SLOT_COUNT:
		return
	_set_slot_icon(slot, icon)

func set_item(icon: Texture2D) -> void:
	_set_slot_icon(OUTFIT_SLOT_COUNT, icon)

func _set_slot_icon(index: int, icon: Texture2D) -> void:
	var ghost := _slot_ghosts[index]
	var rect := _slot_icons[index]
	if icon == null:
		rect.modulate.a = 0.0
		rect.texture = null
		ghost.modulate.a = 1.0
		return
	ghost.modulate.a = 0.0
	rect.texture = icon
	rect.pivot_offset = rect.size * 0.5
	rect.modulate.a = 1.0
	rect.scale = Vector2(1.5, 1.5)
	var tw := create_tween()
	tw.tween_property(rect, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 使用道具：图标清空 + 灰闪
func flash_item_used() -> void:
	var rect := _slot_icons[OUTFIT_SLOT_COUNT]
	if rect.texture == null:
		return
	var tw := create_tween()
	tw.tween_property(rect, "self_modulate", Color(0.4, 0.4, 0.4, 0.6), 0.1)
	tw.tween_property(rect, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		rect.texture = null
		rect.self_modulate = Color.WHITE
		_slot_ghosts[OUTFIT_SLOT_COUNT].modulate.a = 1.0)

# ---------------------------------------------------------------- 冠军皇冠
func show_crown(on: bool) -> void:
	if not on:
		_crown.hide()
		return
	_crown.show()
	_crown.pivot_offset = Vector2(20, 20)
	_crown.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(_crown, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- S6 评分
## 展开评分区并创建维度行（dim_defs: [[key, 名称], ...]）
func begin_scoring(dim_defs: Array) -> void:
	for c in _score_box.get_children():
		c.queue_free()
	_dim_labels.clear()
	for d in dim_defs:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(d[1])
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
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
	_score_box.show()

## 刷一维分数（弹入动画）
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

## 总分滚动
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
		_score_box.hide()
	_crown.hide()
