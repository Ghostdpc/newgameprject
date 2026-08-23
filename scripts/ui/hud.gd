## 职责：对局 HUD（S4）—— 屏幕中央取景框（camera_frame 贴图）+ 中央倒计时数字
##       （数值越小字号越大）+ 倍率徽标 + 决胜红框脉冲、+/-秒飞字、快门白闪。
## 四角玩家面板由 PlayerHUD/PlayerPanel 负责（交互文档 §5 核心 HUD）。

class_name HUD
extends CanvasLayer

enum TimeEffect { FAST = 0, SLOW = 1, ADD = 2, SUB = 3 }

const COLOR_NORMAL   := Color(1, 1, 1)
const COLOR_DECISIVE := Color(1.0, 0.28, 0.22)   # 最后 3 秒红
const COLOR_FAST     := Color(1.0, 0.55, 0.18)   # 快进橙红
const COLOR_SLOW     := Color(0.42, 0.86, 1.0)   # 慢放青蓝
const COLOR_ADD      := Color(0.45, 0.95, 0.5)
const COLOR_SUB      := Color(1.0, 0.35, 0.3)
const DECISIVE_SECONDS := 3.0
# 倒计时数字：数值越小，字号越大（越小越大）
const TIMER_MIN_SIZE := 72
const TIMER_MAX_SIZE := 260

@onready var _timer_label: Label = get_node_or_null("CameraViewfinder/TimerLabel")
@onready var _frame: TextureRect = get_node_or_null("CameraViewfinder/Frame")
@onready var _rate_badge: PanelContainer = get_node_or_null("CameraViewfinder/RateBadge")
@onready var _rate_label: Label = get_node_or_null("CameraViewfinder/RateBadge/RateLabel")
@onready var _stage_label: Label = get_node_or_null("TopBar/StageLabel")
@onready var _float_layer: Control = get_node_or_null("FloatLayer")
@onready var _viewfinder: Control = get_node_or_null("CameraViewfinder")
@onready var _top_bar: Control = get_node_or_null("TopBar")
@onready var _film_border: Control = get_node_or_null("FilmBorder")

var _last_seconds: float = -1.0
var _active_rate_type: int = -1
var _pulse_tween: Tween = null

func _ready() -> void:
	EventBus.stage_changed.connect(_on_stage_changed)
	EventBus.stage_timer_updated.connect(_on_timer_updated)
	EventBus.time_effect_applied.connect(_on_time_effect)
	if _rate_badge:
		_rate_badge.hide()

# ---------------------------------------------------------------- 倒计时
func _on_timer_updated(seconds: float) -> void:
	_last_seconds = seconds
	if _timer_label:
		var n := maxi(1, ceili(seconds))
		_timer_label.text = "%d" % n
		var fs := int(round(TIMER_MIN_SIZE + float(TIMER_MAX_SIZE - TIMER_MIN_SIZE) / float(n)))
		_timer_label.add_theme_font_size_override("font_size", fs)
		_timer_label.add_theme_constant_override("outline_size", int(round(fs * 0.09)))
	_refresh_timer_look()

func _refresh_timer_look() -> void:
	if not _timer_label:
		return
	var decisive := _last_seconds <= DECISIVE_SECONDS and _last_seconds > 0.0 \
		and GameManager.current_stage == GameManager.GameStage.BATTLE
	# 颜色优先级：倍率效果 > 决胜红 > 白；倒计时与取景标线同色
	var look := COLOR_NORMAL
	if _active_rate_type == TimeEffect.FAST:
		look = COLOR_FAST
	elif _active_rate_type == TimeEffect.SLOW:
		look = COLOR_SLOW
	elif decisive:
		look = COLOR_DECISIVE
	_timer_label.add_theme_color_override("font_color", look)
	# 红框脉冲（仅决胜时刻）
	if decisive:
		_start_pulse()
	else:
		_stop_pulse()

func _start_pulse() -> void:
	if _frame and not (_pulse_tween and _pulse_tween.is_running()):
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(_frame, "modulate:a", 1.0, 0.25)
		_pulse_tween.tween_property(_frame, "modulate:a", 0.4, 0.25)

func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	if _frame:
		_frame.modulate.a = 1.0

# ---------------------------------------------------------------- 时间道具
func _on_time_effect(effect_type: int, value: float) -> void:
	match effect_type:
		TimeEffect.FAST, TimeEffect.SLOW:
			if value <= 0.0:
				if _active_rate_type == effect_type:
					_active_rate_type = -1
					_hide_rate_badge()
			else:
				_active_rate_type = effect_type
				_show_rate_badge(("%.1fx" % value),
					COLOR_FAST if effect_type == TimeEffect.FAST else COLOR_SLOW)
			_refresh_timer_look()
		TimeEffect.ADD:
			_spawn_float_text("+%.1fs" % value, COLOR_ADD)
		TimeEffect.SUB:
			_spawn_float_text("%.1fs" % value, COLOR_SUB)   # value 为负，显示 "-3.0s"
			_shake_timer()

func _show_rate_badge(text: String, color: Color) -> void:
	if not _rate_badge:
		return
	_rate_label.text = text
	_rate_label.add_theme_color_override("font_color", color)
	_rate_badge.show()
	_rate_badge.scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.tween_property(_rate_badge, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_rate_badge() -> void:
	if _rate_badge:
		_rate_badge.hide()

func _spawn_float_text(text: String, color: Color) -> void:
	if not _float_layer or not _timer_label:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	_float_layer.add_child(label)
	label.reset_size()
	var timer_rect := _timer_label.get_global_rect()
	label.global_position = Vector2(
		timer_rect.get_center().x - label.size.x * 0.5,
		timer_rect.position.y + timer_rect.size.y + 6.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 70.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)

func _shake_timer() -> void:
	if not _timer_label:
		return
	var base := _timer_label.position
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_timer_label, "position:x", base.x + (6.0 if i % 2 == 0 else -6.0), 0.04)
	tw.tween_property(_timer_label, "position:x", base.x, 0.04)

# ---------------------------------------------------------------- 阶段
func _on_stage_changed(stage: int) -> void:
	if stage == GameManager.GameStage.MAIN_MENU or stage == GameManager.GameStage.LOBBY:
		return
		if _stage_label:
			match stage:
				GameManager.GameStage.THEME_ANNOUNCE:
					_stage_label.text = "主题公布"
				GameManager.GameStage.BATTLE:
					_stage_label.text = ""
				_:
					_stage_label.text = ""
	# 非混战阶段隐藏倒计时数字
	if stage != GameManager.GameStage.BATTLE and _timer_label:
		_timer_label.text = ""
		if _rate_badge:
			_rate_badge.hide()
		_active_rate_type = -1
		_stop_pulse()

## S6 评分：隐藏顶部栏与取景框，保留四角面板（照片与刷分由 ScoringScreen 接管）
func enter_scoring_mode() -> void:
	if _top_bar:
		_top_bar.hide()
	if _viewfinder:
		_viewfinder.hide()
	if _film_border:
		_film_border.hide()

func exit_scoring_mode() -> void:
	if _top_bar:
		_top_bar.show()
	if _viewfinder:
		_viewfinder.show()
	if _film_border:
		_film_border.show()
