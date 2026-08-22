## 職責：結算面板 —— 照片展示（白色相框+說明欄）+ 六維明細 + 繼續按鈕
## 對應策劃案 09：照片縮入相框、白色邊框與底部說明欄
## 對應策劃案 10：按六維拆分明細逐項亮分

class_name ResultsPanel
extends CanvasLayer

@onready var _photo_rect: TextureRect = $Panel/Margin/VBox/PhotoRow/PhotoFrame/Margin/PhotoRect
@onready var _caption: Label = $Panel/Margin/VBox/PhotoRow/PhotoFrame/Caption
@onready var _rows: HBoxContainer = $Panel/Margin/VBox/Rows
@onready var _continue_btn: Button = $Panel/Margin/VBox/ContinueBtn

var _mask_panel: Control = null
var _mask_rect: TextureRect = null

func _ready() -> void:
	hide()
	_continue_btn.pressed.connect(_on_continue_pressed)
	_build_mask_panel()

## 评分 RT（ID 遮罩）调试面板：贴在结算面板右上角
func _build_mask_panel() -> void:
	_mask_panel = PanelContainer.new()
	_mask_panel.name = "MaskPanel"
	_mask_panel.anchor_left = 1.0
	_mask_panel.anchor_top = 0.0
	_mask_panel.anchor_right = 1.0
	_mask_panel.anchor_bottom = 0.0
	_mask_panel.offset_left = -420.0
	_mask_panel.offset_top = 40.0
	_mask_panel.offset_right = -40.0
	_mask_panel.offset_bottom = 300.0
	_mask_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mask_panel.grow_vertical = Control.GROW_DIRECTION_END
	_mask_panel.hide()
	$Panel.add_child(_mask_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_mask_panel.add_child(vbox)

	var label := Label.new()
	label.text = "评分RT · ID遮罩（只算玩家）"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	_mask_rect = TextureRect.new()
	_mask_rect.custom_minimum_size = Vector2(320, 180)
	_mask_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mask_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(_mask_rect)

func show_results(results: Dictionary) -> void:
	var img: Image = results.get("photo")
	if img:
		var tex := ImageTexture.create_from_image(img)
		_photo_rect.texture = tex
	var mask_img: Image = results.get("mask")
	if mask_img and mask_img.get_width() > 0:
		_mask_rect.texture = ImageTexture.create_from_image(mask_img)
		_mask_panel.show()
	else:
		_mask_panel.hide()
	_caption.text = "快門瞬間 · 四維评分（画面比例/C位/服装/朝向）"
	_build_rows(results.get("actors", []))

func _build_rows(actors: Array) -> void:
	for c in _rows.get_children():
		c.queue_free()
	for data in actors:
		_rows.add_child(_build_actor_column(data))

func _build_actor_column(data: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var color: Color = data.get("color", Color.WHITE)
	var idx: int = data.get("player_index", -1)
	col.add_child(_label("P%d" % (idx + 1), 30, color, HORIZONTAL_ALIGNMENT_CENTER))
	var total: float = data.get("total", 0.0)
	col.add_child(_label("%.0f 分" % total, 42, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_label("畫面占比 %.1f%%" % (data.get("percent", 0.0) * 100.0), 18, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	var sep := HSeparator.new()
	col.add_child(sep)
	var dim: Dictionary = data.get("dimensions", {})
	for key in dim:
		var d: Dictionary = dim[key]
		var suffix := " (TBD)" if d.get("tbd", false) else ""
		var line := _label("%s %.0f%s" % [d.get("label", key), d.get("score", 0.0), suffix], 16, Color(0.7, 0.75, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
		col.add_child(line)
	return col

func _label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _on_continue_pressed() -> void:
	hide()
	GameManager.finish_scoring()
