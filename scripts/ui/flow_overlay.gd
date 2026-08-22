## 职责：S3 主题展示（3 秒倒数）+ 暂停覆盖层（Esc，房主可返回房间）
## 交互文档 §4：主题展示 3 秒不可跳过、最后 1 秒预警；暂停不消耗倒计时。

class_name FlowOverlay
extends CanvasLayer

const THEME_NAME := "摄影棚乱斗"
const THEME_BONUS := "加分倾向：完整入镜 · 站位靠中 · 穿戴服装组件"
const COLOR_WARN := Color(1.0, 0.3, 0.25)
const COLOR_NORMAL := Color(0.95, 0.97, 1.0)

@onready var _theme_screen: Control = $ThemeScreen
@onready var _theme_name: Label = $ThemeScreen/Center/VBox/ThemeNameLabel
@onready var _theme_bonus: Label = $ThemeScreen/Center/VBox/ThemeBonusLabel
@onready var _countdown: Label = $ThemeScreen/Center/VBox/CountdownLabel
@onready var _pause_screen: Control = $PauseScreen
@onready var _continue_btn: Button = $PauseScreen/Center/VBox/ButtonRow/ContinueButton
@onready var _lobby_btn: Button = $PauseScreen/Center/VBox/ButtonRow/LobbyButton

var _paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.stage_changed.connect(_on_stage_changed)
	EventBus.stage_timer_updated.connect(_on_timer_updated)
	_continue_btn.pressed.connect(resume)
	_lobby_btn.pressed.connect(_return_lobby)
	_theme_screen.hide()
	_pause_screen.hide()
	_theme_name.text = THEME_NAME
	_theme_bonus.text = THEME_BONUS

func _on_stage_changed(stage: int) -> void:
	if stage == GameManager.GameStage.THEME_ANNOUNCE:
		_theme_screen.show()
		_countdown.text = "3"
		_countdown.modulate = COLOR_NORMAL
	elif _theme_screen.visible:
		_theme_screen.hide()
	if stage != GameManager.GameStage.BATTLE and stage != GameManager.GameStage.THEME_ANNOUNCE and _paused:
		resume()

func _on_timer_updated(seconds: float) -> void:
	if GameManager.current_stage != GameManager.GameStage.THEME_ANNOUNCE:
		return
	if not _theme_screen.visible:
		return
	var n := ceili(seconds)
	_countdown.text = "%d" % n
	# 最后 1 秒预警（红 + 放大）
	if n <= 1:
		_countdown.modulate = COLOR_WARN
		_countdown.add_theme_font_size_override("font_size", 140)
	else:
		_countdown.modulate = COLOR_NORMAL
		_countdown.add_theme_font_size_override("font_size", 120)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	var stage := GameManager.current_stage
	if stage != GameManager.GameStage.BATTLE and stage != GameManager.GameStage.THEME_ANNOUNCE:
		return
	if _paused:
		resume()
	else:
		pause()

func pause() -> void:
	_paused = true
	_pause_screen.show()
	get_tree().paused = true
	EventBus.game_paused_changed.emit(true)

func resume() -> void:
	_paused = false
	_pause_screen.hide()
	get_tree().paused = false
	EventBus.game_paused_changed.emit(false)

func _return_lobby() -> void:
	_paused = false
	get_tree().paused = false
	EventBus.game_paused_changed.emit(false)
	GameManager.enter_lobby()
