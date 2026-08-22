## 职责：屏幕边缘 UIMask 的矢量绘制层。
## 作为 Control 直接生成边框，不依赖外部贴图导入状态。

class_name ScreenEdgeMask
extends Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var w := maxf(minf(size.x, size.y) * 0.0075, 5.0)
	var left := size.x * 0.039
	var right := size.x * 0.961
	var top := size.y * 0.069
	var bottom := size.y * 0.931
	var corner_x := size.x * 0.105
	var corner_y := size.y * 0.13
	var white := Color.WHITE
	var soft := Color(1.0, 1.0, 1.0, 0.52)
	var dim := Color(1.0, 1.0, 1.0, 0.28)
	draw_polyline(PackedVector2Array([Vector2(left, top + corner_y), Vector2(left, top), Vector2(left + corner_x, top)]), white, w, true)
	draw_polyline(PackedVector2Array([Vector2(right - corner_x, top), Vector2(right, top), Vector2(right, top + corner_y)]), white, w, true)
	draw_polyline(PackedVector2Array([Vector2(left, bottom - corner_y), Vector2(left, bottom), Vector2(left + corner_x, bottom)]), white, w, true)
	draw_polyline(PackedVector2Array([Vector2(right - corner_x, bottom), Vector2(right, bottom), Vector2(right, bottom - corner_y)]), white, w, true)
	draw_line(Vector2(size.x * 0.22, top * 0.60), Vector2(size.x * 0.78, top * 0.60), soft, w)
	draw_line(Vector2(size.x * 0.22, size.y - top * 0.60), Vector2(size.x * 0.78, size.y - top * 0.60), soft, w)
	draw_line(Vector2(left * 0.60, size.y * 0.34), Vector2(left * 0.60, size.y * 0.66), dim, w)
	draw_line(Vector2(size.x - left * 0.60, size.y * 0.34), Vector2(size.x - left * 0.60, size.y * 0.66), dim, w)
