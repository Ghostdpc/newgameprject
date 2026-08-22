## 職責：道具系統入口（autoload）
## - 啟動時注冊所有 EffectKind 到 ItemEffectRegistry
## - 提供 use_item() 唯一使用接口
## - _process 跑有時長效果的回退計時

extends Node

var _active_effects: Array[Dictionary] = []
var _item_config: ItemConfig

func _ready() -> void:
	_register_effects()
	_item_config = ItemConfig.new()
	_item_config.load()

## 注冊所有 EffectKind → Script（新增效果時在此添加一行）
func _register_effects() -> void:
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.TIMER_ADD,
		load("res://scripts/items/effects/timer_add_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.TIMER_SCALE,
		load("res://scripts/items/effects/timer_scale_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.PLAYER_SPEED,
		load("res://scripts/items/effects/player_speed_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.CAMERA_OFFSET,
		load("res://scripts/items/effects/camera_offset_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.SPAWN_TRAP,
		load("res://scripts/items/effects/spawn_trap_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.PLAYER_RAGDOLL,
		load("res://scripts/items/effects/player_ragdoll_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.BANANA_SLIDE,
		load("res://scripts/items/effects/banana_slide_effect.gd")
	)

## 玩家使用道具的唯一入口
## source_player: 使用者（null = 系統觸發），item_id 對應 items.json
func use_item(source_player: PlayerController, item_id: String, extra: Dictionary = {}) -> void:
	var def := _item_config.get_item(item_id)
	if def == null:
		push_warning("ItemSystem: unknown item_id '%s'" % item_id)
		return

	for effect in def.effects:
		var targets := _resolve_targets(effect.target, source_player)
		for target_player in targets:
			var ctx := ItemContext.new()
			ctx.source_player = target_player
			ctx.item_id       = item_id
			ctx.extra         = extra.duplicate()
			ctx.extra["invoker"] = source_player  # 始終保留原始使用者引用
			effect.apply(ctx)
			if effect.duration > 0.0:
				_active_effects.append({
					"effect":    effect,
					"ctx":       ctx,
					"remaining": effect.duration,
				})

	var src_index: int = source_player.player_index if source_player else -1
	EventBus.item_used.emit(src_index, item_id)

func _process(delta: float) -> void:
	var i := _active_effects.size() - 1
	while i >= 0:
		var entry: Dictionary = _active_effects[i]
		entry["remaining"] -= delta
		if entry["remaining"] <= 0.0:
			(entry["effect"] as ItemEffect).revert(entry["ctx"] as ItemContext)
			_active_effects.remove_at(i)
		i -= 1

## 解析單個效果的目標玩家列表（WORLD 效果返回 [null] 觸發一次）
func _resolve_targets(target: ItemTypes.Target, source: PlayerController) -> Array:
	if target == ItemTypes.Target.WORLD:
		return [null]

	var all_players: Array[PlayerController] = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			all_players.append(node as PlayerController)

	match target:
		ItemTypes.Target.SELF:
			return [source] if source else []
		ItemTypes.Target.OTHERS:
			return all_players.filter(func(p): return p != source)
		ItemTypes.Target.ALL:
			return all_players
	return []
