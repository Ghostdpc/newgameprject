## 職責：測試道具系統核心邏輯（配表讀取、效果注冊、use_item 調用鏈）

extends GutTest

var _item_system: Node
var _config: ItemConfig

func before_each() -> void:
	GameManager.stage_time_remaining = 10.0
	GameManager.time_scale = 1.0
	_item_system = load("res://scripts/items/item_system.gd").new()
	add_child_autofree(_item_system)
	_config = _item_system._item_config

# --- ItemConfig 基礎加載 ---

func test_items_json_loaded() -> void:
	var ids := _config.all_ids()
	assert_false(ids.is_empty(), "items.json 應包含至少一條道具")

func test_items_json_has_all_seven() -> void:
	var ids := _config.all_ids()
	assert_eq(ids.size(), 7, "策劃定義 7 個道具")

func test_get_item_returns_def() -> void:
	var def := _config.get_item("time_battery")
	assert_not_null(def, "time_battery 應存在")
	assert_eq(def.id, "time_battery")

func test_get_item_unknown_returns_null() -> void:
	var def := _config.get_item("__no_such_item__")
	assert_null(def, "不存在的 id 應回傳 null")

# --- spawn_config ---

func test_spawn_config_max_active() -> void:
	var cfg := _config.get_spawn_config()
	assert_eq(int(cfg.get("max_active", 0)), 5, "max_active 應為 5")

func test_spawn_config_respawn_interval() -> void:
	var cfg := _config.get_spawn_config()
	assert_eq(float(cfg.get("respawn_interval", 0.0)), 8.0, "respawn_interval 應為 8.0")

# --- trap 配置 ---

func test_traps_has_banana_peel() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_not_null(trap, "banana_peel 放置物應存在")

func test_banana_peel_trap_lifetime() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_eq(trap.lifetime, 15.0, "banana_peel 壽命應為 15 秒")

func test_banana_peel_trap_has_effect() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_eq(trap.effects.size(), 1, "banana_peel 應有 1 個效果")

func test_banana_peel_effect_is_ragdoll() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_eq(trap.effects[0].kind, ItemTypes.EffectKind.PLAYER_RAGDOLL)

# --- TimerAddEffect（加時電池 / 減時剪刀）---

func test_time_battery_increases_time() -> void:
	GameManager.stage_time_remaining = 10.0
	_item_system.use_item(null, "time_battery")
	assert_eq(GameManager.stage_time_remaining, 13.0, "加時電池應 +3 秒")

func test_time_scissors_decreases_time() -> void:
	GameManager.stage_time_remaining = 10.0
	_item_system.use_item(null, "time_scissors")
	assert_eq(GameManager.stage_time_remaining, 7.0, "減時剪刀應 -3 秒")

func test_time_scissors_min_clamp() -> void:
	GameManager.stage_time_remaining = 2.0
	_item_system.use_item(null, "time_scissors")
	assert_eq(GameManager.stage_time_remaining, 1.0, "減時剪刀保底 1 秒")

func test_time_scissors_min_clamp_at_one() -> void:
	GameManager.stage_time_remaining = 1.0
	_item_system.use_item(null, "time_scissors")
	assert_eq(GameManager.stage_time_remaining, 1.0, "剩餘 1 秒時減時剪刀不能再減")

# --- TimerScaleEffect（快進發條 / 慢放沙漏）---

func test_fast_crank_sets_time_scale() -> void:
	GameManager.time_scale = 1.0
	_item_system.use_item(null, "fast_forward_crank")
	assert_eq(GameManager.time_scale, 2.0, "快進發條應將 time_scale 設為 2.0")

func test_slow_hourglass_sets_time_scale() -> void:
	GameManager.time_scale = 1.0
	_item_system.use_item(null, "slow_hourglass")
	assert_eq(GameManager.time_scale, 0.5, "慢放沙漏應將 time_scale 設為 0.5")

func test_timer_scale_reverts_after_duration() -> void:
	GameManager.time_scale = 1.0
	_item_system.use_item(null, "fast_forward_crank")
	assert_eq(GameManager.time_scale, 2.0)
	# 模擬時間流逝超過 3 秒（效果 duration = 3.0）
	_item_system._process(3.1)
	assert_eq(GameManager.time_scale, 1.0, "持續時間結束後 time_scale 應還原為 1.0")

# --- PlayerSpeedEffect（能量飲料）---

func test_energy_drink_sets_speed_multiplier() -> void:
	var mock_player := _make_mock_player()
	mock_player.speed_multiplier = 1.0
	_item_system.use_item(mock_player, "energy_drink")
	assert_eq(mock_player.speed_multiplier, 1.4, "能量飲料應將移速倍數設為 1.4")
	mock_player.queue_free()

func test_energy_drink_reverts_after_duration() -> void:
	var mock_player := _make_mock_player()
	mock_player.speed_multiplier = 1.0
	_item_system.use_item(mock_player, "energy_drink")
	_item_system._process(3.1)
	assert_eq(mock_player.speed_multiplier, 1.0, "能量飲料結束後移速倍數應還原")
	mock_player.queue_free()

# --- 未知道具不崩潰 ---

func test_use_unknown_item_no_crash() -> void:
	_item_system.use_item(null, "__unknown__")
	assert_true(true, "使用未知道具不應崩潰")

# --- 輔助 ---

func _make_mock_player() -> PlayerController:
	# 用最簡單的 CharacterBody3D 替身；只需 speed_multiplier 和 player_index
	var script := load("res://scripts/player/player_controller.gd")
	# 直接構造會觸發 _ready 中的節點查找，改用場景中的空殼代替
	var node := CharacterBody3D.new()
	node.set_script(script)
	# 跳過 _ready 副作用（add_child_autofree 後 _ready 仍會執行，但缺子節點不崩潰）
	add_child_autofree(node)
	return node as PlayerController
