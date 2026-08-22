## 職責：測試 GameManager 階段流程邏輯

extends GutTest

var _gm: Node

func before_each() -> void:
	_gm = load("res://scripts/autoload/game_manager.gd").new()
	add_child_autofree(_gm)

func test_initial_stage_is_main_menu() -> void:
	assert_eq(_gm.current_stage, GameManager.GameStage.MAIN_MENU, "初始應為 MAIN_MENU")

func test_stage_time_remaining_starts_at_zero() -> void:
	assert_eq(_gm.stage_time_remaining, 0.0, "初始 stage_time_remaining 應為 0")

func test_config_battle_duration_is_15() -> void:
	assert_eq(_gm.config.battle_duration, 15.0, "battle_duration 應讀 JSON 得 15.0")

func test_score_system_returns_four_scores() -> void:
	var score_sys: ScoreSystem = ScoreSystem.new()
	add_child_autofree(score_sys)
	var scores: Array[int] = score_sys.calculate_scores(null)
	assert_eq(scores.size(), 4, "應回傳 4 個玩家分數")
