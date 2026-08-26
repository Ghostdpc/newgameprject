## 职责：测试 ConfigLoader 的加载、快取、fallback 行为

extends GutTest

var _loader: Node

func before_each() -> void:
	_loader = load("res://scripts/autoload/config_loader.gd").new()
	add_child_autofree(_loader)

# --- load_config ---

func test_load_existing_config_returns_dictionary() -> void:
	var cfg: Dictionary = _loader.load_config("game_flow")
	assert_true(cfg is Dictionary, "game_flow.json 应回传 Dictionary")
	assert_false(cfg.is_empty(), "game_flow.json 不应为空")

func test_comment_key_is_stripped() -> void:
	var cfg: Dictionary = _loader.load_config("game_flow")
	assert_false(cfg.has("_comment"), "_comment 键应被过滤")

func test_cache_returns_same_instance() -> void:
	var cfg1: Dictionary = _loader.load_config("game_flow")
	var cfg2: Dictionary = _loader.load_config("game_flow")
	assert_eq(cfg1, cfg2, "第二次读取应命中快取")

# --- get_value ---

func test_get_value_returns_correct_value() -> void:
	var val: Variant = _loader.get_value("game_flow", "battle_duration", 0.0)
	assert_eq(val, 30.0, "battle_duration 应为 30.0")

func test_get_value_missing_key_returns_default() -> void:
	var val: Variant = _loader.get_value("game_flow", "__no_such_key__", 99.0)
	assert_eq(val, 99.0, "缺失键应回传默认值")

# --- GameConfig ---

func test_game_config_loads_battle_duration_from_json() -> void:
	var cfg := GameConfig.new()
	cfg.load()
	assert_eq(cfg.battle_duration, 30.0, "battle_duration 应从 JSON 读为 30.0")

func test_game_config_skipped_stages_are_zero() -> void:
	var cfg := GameConfig.new()
	cfg.load()
	assert_eq(cfg.grab_clothes_duration, 0.0)
	assert_eq(cfg.scoring_duration,      0.0)
