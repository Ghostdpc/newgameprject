## 職責：測試 ConfigLoader 的加載、快取、fallback 行為

extends GutTest

var _loader: Node

func before_each() -> void:
	_loader = load("res://scripts/autoload/config_loader.gd").new()
	add_child_autofree(_loader)

# --- load_config ---

func test_load_existing_config_returns_dictionary() -> void:
	var cfg: Dictionary = _loader.load_config("game_flow")
	assert_true(cfg is Dictionary, "game_flow.json 應回傳 Dictionary")
	assert_false(cfg.is_empty(), "game_flow.json 不應為空")

func test_comment_key_is_stripped() -> void:
	var cfg: Dictionary = _loader.load_config("game_flow")
	assert_false(cfg.has("_comment"), "_comment 鍵應被過濾")

func test_cache_returns_same_instance() -> void:
	var cfg1: Dictionary = _loader.load_config("game_flow")
	var cfg2: Dictionary = _loader.load_config("game_flow")
	assert_eq(cfg1, cfg2, "第二次讀取應命中快取")

# --- get_value ---

func test_get_value_returns_correct_value() -> void:
	var val: Variant = _loader.get_value("game_flow", "battle_duration", 0.0)
	assert_eq(val, 45.0, "battle_duration 應為 45.0")

func test_get_value_missing_key_returns_default() -> void:
	var val: Variant = _loader.get_value("game_flow", "__no_such_key__", 99.0)
	assert_eq(val, 99.0, "缺失鍵應回傳默認值")

# --- GameConfig ---

func test_game_config_loads_battle_duration_from_json() -> void:
	var cfg := GameConfig.new()
	cfg.load()
	assert_eq(cfg.battle_duration, 45.0, "battle_duration 應從 JSON 讀為 45.0")

func test_game_config_skipped_stages_are_zero() -> void:
	var cfg := GameConfig.new()
	cfg.load()
	assert_eq(cfg.grab_clothes_duration, 0.0)
	assert_eq(cfg.scoring_duration,      0.0)
