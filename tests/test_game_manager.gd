## 職責：測試 GameManager 狀態轉換邏輯

extends GutTest

var _game_manager: Node

func before_each() -> void:
	_game_manager = load("res://scripts/autoload/game_manager.gd").new()
	add_child_autofree(_game_manager)

func test_initial_state_is_lobby() -> void:
	assert_eq(_game_manager.current_state, 0, "初始狀態應為 LOBBY(0)")

func test_time_remaining_starts_at_round_duration() -> void:
	assert_eq(_game_manager.time_remaining, GameManager.ROUND_DURATION)

func test_score_system_returns_four_scores() -> void:
	var score_sys := ScoreSystem.new()
	add_child_autofree(score_sys)
	var scores := score_sys.calculate_scores(null)
	assert_eq(scores.size(), 4, "應回傳 4 個玩家的分數")
