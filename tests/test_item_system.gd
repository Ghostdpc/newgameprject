## 职责：测试道具系统核心逻辑（配表读取、效果注册、use_item 调用链）

extends GutTest

var _item_system: Node
var _config: ItemConfig

func before_each() -> void:
	GameManager.stage_time_remaining = 10.0
	GameManager.time_rate = 1.0
	_item_system = load("res://scripts/items/item_system.gd").new()
	add_child_autofree(_item_system)
	_config = _item_system._item_config

# --- ItemConfig 基础加载 ---

func test_items_json_loaded() -> void:
	var ids := _config.all_ids()
	assert_false(ids.is_empty(), "items.json 应包含至少一条道具")

func test_items_json_has_all_seven() -> void:
	var ids := _config.all_ids()
	assert_eq(ids.size(), 7, "策划定义 7 个道具")

func test_get_item_returns_def() -> void:
	var def := _config.get_item("time_battery")
	assert_not_null(def, "time_battery 应存在")
	assert_eq(def.id, "time_battery")

func test_get_item_unknown_returns_null() -> void:
	var def := _config.get_item("__no_such_item__")
	assert_null(def, "不存在的 id 应回传 null")

# --- spawn_config ---

func test_spawn_config_max_active() -> void:
	var cfg := _config.get_spawn_config()
	assert_eq(int(cfg.get("max_active", 0)), 5, "max_active 应为 5")

func test_spawn_config_respawn_interval() -> void:
	var cfg := _config.get_spawn_config()
	assert_eq(float(cfg.get("respawn_interval", 0.0)), 8.0, "respawn_interval 应为 8.0")

# --- trap 配置 ---

func test_traps_has_banana_peel() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_not_null(trap, "banana_peel 放置物应存在")

func test_banana_peel_trap_lifetime() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_eq(trap.lifetime, 15.0, "banana_peel 寿命应为 15 秒")

func test_banana_peel_trap_has_effect() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_eq(trap.effects.size(), 1, "banana_peel 应有 1 个效果")

func test_banana_peel_effect_is_banana_slide() -> void:
	var trap := _config.get_trap("banana_peel")
	assert_eq(trap.effects[0].kind, ItemTypes.EffectKind.BANANA_SLIDE)

# --- TimerAddEffect（加时电池 / 减时剪刀）---

func test_time_battery_increases_time() -> void:
	GameManager.stage_time_remaining = 10.0
	_item_system.use_item(null, "time_battery")
	assert_eq(GameManager.stage_time_remaining, 13.0, "加时电池应 +3 秒")

func test_time_scissors_decreases_time() -> void:
	GameManager.stage_time_remaining = 10.0
	_item_system.use_item(null, "time_scissors")
	assert_eq(GameManager.stage_time_remaining, 7.0, "减时剪刀应 -3 秒")

func test_time_scissors_min_clamp() -> void:
	GameManager.stage_time_remaining = 2.0
	_item_system.use_item(null, "time_scissors")
	assert_eq(GameManager.stage_time_remaining, 1.0, "减时剪刀保底 1 秒")

func test_time_scissors_min_clamp_at_one() -> void:
	GameManager.stage_time_remaining = 1.0
	_item_system.use_item(null, "time_scissors")
	assert_eq(GameManager.stage_time_remaining, 1.0, "剩余 1 秒时减时剪刀不能再减")

# --- TimerScaleEffect（快进发条 / 慢放沙漏）---

func test_fast_crank_sets_time_scale() -> void:
	GameManager.time_rate = 1.0
	_item_system.use_item(null, "fast_forward_crank")
	assert_eq(GameManager.time_rate, 2.0, "快进发条应将 time_rate 设为 2.0")

func test_slow_hourglass_sets_time_scale() -> void:
	GameManager.time_rate = 1.0
	_item_system.use_item(null, "slow_hourglass")
	assert_eq(GameManager.time_rate, 0.5, "慢放沙漏应将 time_rate 设为 0.5")

func test_timer_scale_reverts_after_duration() -> void:
	GameManager.time_rate = 1.0
	_item_system.use_item(null, "fast_forward_crank")
	assert_eq(GameManager.time_rate, 2.0)
	# 模拟时间流逝超过 3 秒（效果 duration = 3.0）
	_item_system._process(3.1)
	assert_eq(GameManager.time_rate, 1.0, "持续时间结束后 time_rate 应还原为 1.0")

# --- PlayerSpeedEffect（能量饮料）---

func test_energy_drink_sets_speed_multiplier() -> void:
	var mock_player := _make_mock_player()
	mock_player.speed_multiplier = 1.0
	_item_system.use_item(mock_player, "energy_drink")
	assert_eq(mock_player.speed_multiplier, 10.0, "能量饮料应将移速倍数设为 10.0")
	mock_player.queue_free()

func test_energy_drink_reverts_after_duration() -> void:
	var mock_player := _make_mock_player()
	mock_player.speed_multiplier = 1.0
	_item_system.use_item(mock_player, "energy_drink")
	_item_system._process(3.1)
	assert_eq(mock_player.speed_multiplier, 1.0, "能量饮料结束后移速倍数应还原")
	mock_player.queue_free()

# --- 未知道具不崩溃 ---

func test_use_unknown_item_no_crash() -> void:
	_item_system.use_item(null, "__unknown__")
	assert_true(true, "使用未知道具不应崩溃")

# --- 辅助 ---

func _make_mock_player() -> PlayerController:
	# 用最简单的 CharacterBody3D 替身；只需 speed_multiplier 和 player_index
	var script := load("res://scripts/player/player_controller.gd")
	# 直接构造会触发 _ready 中的节点查找，改用场景中的空壳代替
	var node := CharacterBody3D.new()
	node.set_script(script)
	# 跳过 _ready 副作用（add_child_autofree 后 _ready 仍会执行，但缺子节点不崩溃）
	add_child_autofree(node)
	return node as PlayerController
