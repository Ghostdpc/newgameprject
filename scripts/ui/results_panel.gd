## 職責：結算面板 —— 照片展示（白色相框+說明欄）+ 六維明細 + 繼續按鈕
## 對應策劃案 09：照片縮入相框、白色邊框與底部說明欄
## 對應策劃案 10：按六維拆分明細逐項亮分

class_name ResultsPanel
extends CanvasLayer

@onready var _photo_rect: TextureRect = $Panel/Margin/VBox/PhotoRow/PhotoFrame/Margin/PhotoRect
@onready var _caption: Label = $Panel/Margin/VBox/PhotoRow/PhotoFrame/Caption
@onready var _rows: HBoxContainer = $Panel/Margin/VBox/Rows
@onready var _continue_btn: Button = $Panel/Margin/VBox/ContinueBtn

func _ready() -> void:
	hide()
	_continue_btn.pressed.connect(_on_continue_pressed)

func show_results(results: Dictionary) -> void:
	var img: Image = results.get("photo")
	if img:
		var tex := ImageTexture.create_from_image(img)
		_photo_rect.texture = tex
	_caption.text = "快門瞬間 · Demo 測試場（朝向/服裝/Pose 維度待接入）"
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
