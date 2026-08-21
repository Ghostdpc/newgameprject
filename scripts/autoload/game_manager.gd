## 職責：遊戲流程控制（狀態機 / 倒計時 / 結算觸發）

extends Node

enum GameState {
	LOBBY,
	COUNTDOWN,
	PLAYING,
	PHOTO_SHOT,
	RESULTS
}

const ROUND_DURATION: float = 60.0
const COUNTDOWN_DURATION: float = 3.0

var current_state: GameState = GameState.LOBBY
var time_remaining: float = ROUND_DURATION

func _ready() -> void:
	EventBus.game_state_changed.connect(_on_game_state_changed)

func start_game() -> void:
	_transition_to(GameState.COUNTDOWN)

func _transition_to(new_state: GameState) -> void:
	current_state = new_state
	EventBus.game_state_changed.emit(new_state)

	match new_state:
		GameState.COUNTDOWN:
			_run_countdown()
		GameState.PLAYING:
			time_remaining = ROUND_DURATION
			EventBus.game_started.emit()
		GameState.PHOTO_SHOT:
			_trigger_photo()
		GameState.RESULTS:
			EventBus.game_over.emit()

func _run_countdown() -> void:
	await get_tree().create_timer(COUNTDOWN_DURATION).timeout
	_transition_to(GameState.PLAYING)

func _trigger_photo() -> void:
	# CameraSystem 監聽此信號，拍攝 RT 後回傳
	EventBus.photo_taken.emit(null)
	await get_tree().create_timer(1.5).timeout
	_transition_to(GameState.RESULTS)

func _process(delta: float) -> void:
	if current_state != GameState.PLAYING:
		return
	time_remaining -= delta
	time_remaining = maxf(time_remaining, 0.0)
	EventBus.timer_updated.emit(time_remaining)
	if time_remaining <= 0.0:
		_transition_to(GameState.PHOTO_SHOT)

func _on_game_state_changed(_new_state: int) -> void:
	pass
