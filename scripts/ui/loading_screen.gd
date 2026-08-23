## 职责：进局前加载界面 —— 紫色背景 + 差分滚动条（同大厅视觉）、
##       logo、进度条、按键提示。
##       真实加载：后台线程预加载目标关卡场景，进度条反映真实加载进度，
##       保底 2 秒展示（避免一闪而过）。
##       换场景采用手动实例化 + 本遮罩（高优先级 CanvasLayer）盖到关卡
##       重活（RoomSource 同步 load GLB、trimesh 碰撞生成）跑完才移除，
##       避免关卡 _ready 阻塞期间出现空白帧。

class_name LoadingScreen
extends CanvasLayer

const SCROLL_TEX: Texture2D = preload("res://assets/textures/ui/lobby/scroll_band.png")
const SCROLL_SPEED := 42.0
const MIN_DURATION := 2.0
const HOLD_AFTER_FULL := 0.2

@onready var _scroll_layer: Control = $Screen/ScrollLayer
@onready var _bar: TextureProgressBar = $Screen/BarArea/LoadBar
@onready var _pct: Label = $Screen/BarArea/PercentLabel

var _rows: Array[TextureRect] = []
var _row_dirs: Array[float] = []
var _elapsed := 0.0
var _finished := false
var _load_status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
var _load_progress := 0.0

func _ready() -> void:
	_build_scroll_rows()
	_bar.value = 0.0
	_refresh_pct()
	_start_load()

# ---------------------------------------------------------------- 后台线程真实加载
func _start_load() -> void:
	var path := GameManager.pending_level_path
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		GameManager.enter_pending_level()
		return
	_load_status = ResourceLoader.THREAD_LOAD_IN_PROGRESS

# ---------------------------------------------------------------- 差分滚动背景（同大厅）
func _build_scroll_rows() -> void:
	var view := get_viewport().get_visible_rect().size
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
	var t := clampf(_elapsed / MIN_DURATION, 0.0, 1.0)

	# 轮询后台加载进度
	if _load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var progress: Array[float] = []
		_load_status = ResourceLoader.load_threaded_get_status(
			GameManager.pending_level_path, progress)
		if not progress.is_empty():
			_load_progress = progress[0]

	# 显示进度 = 真实进度与时间进度取小值，保底 2 秒平滑爬满
	_bar.value = minf(_load_progress, t) * 100.0
	_refresh_pct()

	var loaded := _load_status == ResourceLoader.THREAD_LOAD_LOADED
	if loaded and t >= 1.0:
		_finish()

func _finish() -> void:
	_finished = true
	_bar.value = 100.0
	_refresh_pct()
	await get_tree().create_timer(HOLD_AFTER_FULL).timeout

	var packed: PackedScene = ResourceLoader.load_threaded_get(GameManager.pending_level_path)
	if packed == null:
		GameManager.enter_pending_level()
		return

	# 手动实例化关卡并设为当前场景，加载界面仍盖在上层。
	# 关卡 _ready 里的同步重活（RoomSource load GLB、trimesh 碰撞）会阻塞一两帧，
	# 但本遮罩还在树上，画面不会空白。
	var level := packed.instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level

	# 关卡 _ready 内先 await process_frame，下一帧才跑重活；
	# 再等一帧确保重活完成、关卡已渲染首帧，最后移除遮罩。
	await get_tree().process_frame
	await get_tree().process_frame
	queue_free()

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
