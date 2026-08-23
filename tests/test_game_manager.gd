## 職責：測試 GameManager 階段推進邏輯

extends GutTest

var _game_manager: Node

func before_each() -> void:
	_game_manager = load("res://scripts/autoload/game_manager.gd").new()
	# GameManager._ready 依賴 ConfigLoader autoload，手動注入 config
	_game_manager.config = GameConfig.new()
	add_child_autofree(_game_manager)

func test_initial_stage_is_main_menu() -> void:
	assert_eq(_game_manager.current_stage, 0, "初始階段應為 MAIN_MENU(0)")

func test_stage_order_starts_with_theme_announce() -> void:
	var stage_order: Array = _game_manager.STAGE_ORDER
	assert_eq(stage_order[0], GameManager.GameStage.THEME_ANNOUNCE, "第一個階段應為 THEME_ANNOUNCE")

func test_battle_duration_loaded_from_config() -> void:
	var cfg := GameConfig.new()
	cfg.load()
	assert_eq(cfg.battle_duration, 30.0, "battle_duration 應從 JSON 讀為 30.0")

func test_score_system_returns_four_scores() -> void:
	var score_sys := ScoreSystem.new()
	add_child_autofree(score_sys)
	var scores := score_sys.calculate_scores(null)
	assert_eq(scores.size(), 4, "應回傳 4 個玩家的分數")
