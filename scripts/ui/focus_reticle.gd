## 职责：相机取景标线（新设计）—— 四角括号 + 中心对焦圆环/回声弧 + 十字，
## 纯透明覆盖，只标记成像范围。颜色可整体切换（决胜红 / 倍率色）。

class_name FocusReticle
extends Control

@export var line_color: Color = Color(1, 1, 1, 0.92)
@export var bracket_width: float = 4.0
@export var bracket_arm: float = 44.0
@export var circle_radius: float = 78.0
@export var circle_width: float = 3.0
@export var cross_size: float = 15.0

const DEG := PI / 180.0

func set_line_color(c: Color) -> void:
	line_color = c
	queue_redraw()

func _draw() -> void:
	var s := size
	var col := line_color

	# ---- 四角括号（直角细线）
	var a := bracket_arm
	var w := bracket_width
	var m := 2.0  # 内缩
	# TL
	draw_line(Vector2(m, m + a), Vector2(m, m), col, w)
	draw_line(Vector2(m, m), Vector2(m + a, m), col, w)
	# TR
	draw_line(Vector2(s.x - m - a, m), Vector2(s.x - m, m), col, w)
	draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + a), col, w)
	# BR
	draw_line(Vector2(s.x - m, s.y - m - a), Vector2(s.x - m, s.y - m), col, w)
	draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - a, s.y - m), col, w)
	# BL
	draw_line(Vector2(m + a, s.y - m), Vector2(m, s.y - m), col, w)
	draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - a), col, w)

	# ---- 中心对焦圆（左侧留缺口）+ 回声弧
	var c := s * 0.5
	draw_arc(c, circle_radius, -30.0 * DEG, 210.0 * DEG, 48, col, circle_width)
	draw_arc(c, circle_radius, 235.0 * DEG, 300.0 * DEG, 24, col, circle_width)
	# 内侧回声弧（左下）
	draw_arc(c, circle_radius - 14.0, 150.0 * DEG, 235.0 * DEG, 24,
		Color(col.r, col.g, col.b, col.a * 0.85), circle_width)

	# ---- 十字
	var cl := Color(col.r, col.g, col.b, col.a * 0.95)
	draw_line(Vector2(c.x - cross_size, c.y), Vector2(c.x + cross_size, c.y), cl, 3.0)
	draw_line(Vector2(c.x, c.y - cross_size), Vector2(c.x, c.y + cross_size), cl, 3.0)
