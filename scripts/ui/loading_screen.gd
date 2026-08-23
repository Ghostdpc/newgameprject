## 职责：进局前假加载界面 —— 紫色背景 + 差分滚动条（同大厅视觉）、
##       logo、进度条（约 2 秒 0→100）、按键提示。
##       加载完成后跳转目标关卡，关卡自身流程（主题公布倒计时 → 混战）照常启动。

class_name LoadingScreen
extends Control

const SCROLL_TEX: Texture2D = preload("res://assets/textures/ui/lobby/scroll_band.png")
const SCROLL_SPEED := 42.0
const LOAD_DURATION := 2.0
const HOLD_AFTER_FULL := 0.2

@onready var _scroll_layer: Control = $ScrollLayer
@onready var _bar: TextureProgressBar = $BarArea/LoadBar
@onready var _pct: Label = $BarArea/PercentLabel

var _rows: Array[TextureRect] = []
var _row_dirs: Array[float] = []
var _elapsed := 0.0
var _finished := false

func _ready() -> void:
	_build_scroll_rows()
	_bar.value = 0.0
	_refresh_pct()

# ---------------------------------------------------------------- 差分滚动背景（同大厅）
func _build_scroll_rows() -> void:
	var view := get_viewport_rect().size
	var band_w := float(SCROLL_TEX.get_width())
	var band_h := float(SCROLL_TEX.get_height())
	var count := int(ceil(view.y / band_h)) + 1
	for i in count:
		var row := TextureRect.new()
		row.texture = SCROLL_TEX
		row.stretch_mode = TextureRect.STRETCH_TILE
		row.size = Vector2(view.x + band_w, band_h)
		row.position = Vector2(-band_w * randf(), i * band_h)
		row.modulate = Color(1, 1, 1, 0.5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll_layer.add_child(row)
		_rows.append(row)
		_row_dirs.append(1.0 if i % 2 == 0 else -1.0)

func _process(delta: float) -> void:
	var band_w := float(SCROLL_TEX.get_width())
	for i in _rows.size():
		var row := _rows[i]
		var x := row.position.x - _row_dirs[i] * SCROLL_SPEED * delta
		if x <= -band_w:
			x += band_w
		elif x > 0.0:
			x -= band_w
		row.position.x = x

	if _finished:
		return
	_elapsed += delta
	var t := clampf(_elapsed / LOAD_DURATION, 0.0, 1.0)
	_bar.value = pow(t, 0.65) * 100.0   # 假加载节奏：先快后慢
	_refresh_pct()
	if t >= 1.0:
		_finished = true
		_bar.value = 100.0
		_refresh_pct()
		await get_tree().create_timer(HOLD_AFTER_FULL).timeout
		GameManager.enter_pending_level()

# ---------------------------------------------------------------- 百分比跟随填充条右端
func _refresh_pct() -> void:
	if not _pct or not _bar:
		return
	_pct.text = "%d%%" % int(roundf(_bar.value))
	var bar_rect := _bar.get_global_rect()
	var fill_w := bar_rect.size.x * _bar.value / 100.0
	_pct.reset_size()
	var x := bar_rect.position.x + maxf(fill_w - _pct.size.x - 18.0, 10.0)
	_pct.global_position = Vector2(x, bar_rect.get_center().y - _pct.size.y * 0.5)
