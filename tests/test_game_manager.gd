## 职责：测试 GameManager 阶段推进逻辑

extends GutTest

var _game_manager: Node

func before_each() -> void:
	_game_manager = load("res://scripts/autoload/game_manager.gd").new()
	# GameManager._ready 依赖 ConfigLoader autoload，手动注入 config
	_game_manager.config = GameConfig.new()
	add_child_autofree(_game_manager)

func test_initial_stage_is_main_menu() -> void:
	assert_eq(_game_manager.current_stage, 0, "初始阶段应为 MAIN_MENU(0)")

func test_stage_order_starts_with_theme_announce() -> void:
	var stage_order: Array = _game_manager.STAGE_ORDER
	assert_eq(stage_order[0], GameManager.GameStage.THEME_ANNOUNCE, "第一个阶段应为 THEME_ANNOUNCE")

func test_battle_duration_loaded_from_config() -> void:
	var cfg := GameConfig.new()
	cfg.load()
	assert_eq(cfg.battle_duration, 30.0, "battle_duration 应从 JSON 读为 30.0")

func test_score_system_returns_four_scores() -> void:
	var score_sys := ScoreSystem.new()
	add_child_autofree(score_sys)
	var scores := score_sys.calculate_scores(null)
	assert_eq(scores.size(), 4, "应回传 4 个玩家的分数")
