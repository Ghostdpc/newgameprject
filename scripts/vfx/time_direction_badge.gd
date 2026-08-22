## 职责：时间操控的顶部方向提示。快进显示双右箭头，慢放显示双左箭头。

class_name TimeDirectionBadge
extends Control

var color := Color(1.0, 0.50, 0.08, 1.0)
var direction := 1
var multiplier_text := "2.0x"
var _pulse := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(230.0, 84.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func configure(next_direction: int, next_text: String, next_color: Color) -> void:
	direction = next_direction
	multiplier_text = next_text
	color = next_color
	queue_redraw()

func set_pulse(value: float) -> void:
	_pulse = value
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var scale := 1.0 + _pulse * 0.06
	var center := rect.get_center()
	draw_style_box(_panel_style(), rect.grow(-2.0))
	var arrow_y := center.y
	var arrow_x := 62.0
	var sign := float(direction)
	for index in 2:
		var x := arrow_x + index * 25.0
		var points := PackedVector2Array([
			Vector2(x - 13.0 * sign, arrow_y - 15.0) * scale + center * (1.0 - scale),
			Vector2(x + 15.0 * sign, arrow_y) * scale + center * (1.0 - scale),
			Vector2(x - 13.0 * sign, arrow_y + 15.0) * scale + center * (1.0 - scale),
		])
		draw_colored_polygon(points, color)
	var font := get_theme_default_font()
	var font_size := 27
	draw_string(font, Vector2(124.0, arrow_y + 9.0), multiplier_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(1.0, 0.97, 0.90, 1.0))
	draw_line(Vector2(20.0, rect.size.y - 12.0), Vector2(rect.size.x - 20.0, rect.size.y - 12.0), Color(color.r, color.g, color.b, 0.62), 3.0)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.025, 0.06, 0.88)
	style.border_color = Color(color.r, color.g, color.b, 0.86)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	return style
