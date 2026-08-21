## 職責：HUD，顯示倒計時與遊戲狀態

class_name HUD
extends CanvasLayer

@onready var _timer_label: Label = $VBox/TimerLabel
@onready var _state_label: Label = $VBox/StateLabel
@onready var _start_button: Button = $VBox/StartButton

func _ready() -> void:
	EventBus.timer_updated.connect(_on_timer_updated)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	if _start_button:
		_start_button.pressed.connect(_on_start_pressed)

func _on_timer_updated(seconds: float) -> void:
	if _timer_label:
		_timer_label.text = "%.0f" % ceilf(seconds)

func _on_game_state_changed(new_state: int) -> void:
	if not _state_label:
		return
	match new_state:
		GameManager.GameState.LOBBY:      _state_label.text = "等待開始"
		GameManager.GameState.COUNTDOWN:  _state_label.text = "倒計時..."
		GameManager.GameState.PLAYING:    _state_label.text = "搶占位置！"
		GameManager.GameState.PHOTO_SHOT: _state_label.text = "拍照中！"
		GameManager.GameState.RESULTS:    _state_label.text = "結算"

func _on_start_pressed() -> void:
	GameManager.start_game()
	if _start_button:
		_start_button.hide()
