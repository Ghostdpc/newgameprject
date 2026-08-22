## 職責：測試道具系統核心邏輯（配表讀取、效果注冊、use_item 調用鏈）

extends GutTest

var _item_system: Node
var _config: ItemConfig

func before_each() -> void:
	# 手動構建 ItemSystem（不依賴 autoload 注冊）
	_item_system = load("res://scripts/items/item_system.gd").new()
	add_child_autofree(_item_system)
	_config = _item_system._item_config

# --- ItemConfig ---

func test_items_json_loaded() -> void:
	var ids := _config.all_ids()
	assert_false(ids.is_empty(), "items.json 應包含至少一條道具")

func test_get_item_returns_def() -> void:
	var def := _config.get_item("time_bomb")
	assert_not_null(def, "time_bomb 應存在")
	assert_eq(def.id, "time_bomb")

func test_get_item_unknown_returns_null() -> void:
	var def := _config.get_item("__no_such_item__")
	assert_null(def, "不存在的 id 應回傳 null")

func test_time_bomb_has_one_effect() -> void:
	var def := _config.get_item("time_bomb")
	assert_eq(def.effects.size(), 1, "time_bomb 應有 1 個效果")

func test_time_bomb_effect_is_timer_add() -> void:
	var def := _config.get_item("time_bomb")
	assert_eq(def.effects[0].kind, ItemTypes.EffectKind.TIMER_ADD)

func test_time_bomb_delta_is_negative() -> void:
	var def := _config.get_item("time_bomb")
	var delta: float = float(def.effects[0].params.get("delta", 0.0))
	assert_lt(delta, 0.0, "time_bomb 的 delta 應為負數")

# --- TimerAddEffect ---

func test_timer_add_reduces_time() -> void:
	GameManager.stage_time_remaining = 10.0
	_item_system.use_item(null, "time_bomb")
	assert_eq(GameManager.stage_time_remaining, 7.0, "time_bomb 應減少 3 秒")

func test_timer_add_cannot_go_below_zero() -> void:
	GameManager.stage_time_remaining = 1.0
	_item_system.use_item(null, "time_bomb")
	assert_eq(GameManager.stage_time_remaining, 0.0, "時間不應低於 0")

func test_timer_gift_increases_time() -> void:
	GameManager.stage_time_remaining = 10.0
	_item_system.use_item(null, "time_gift")
	assert_eq(GameManager.stage_time_remaining, 15.0, "time_gift 應增加 5 秒")
