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
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.THROW_BOMB,
		load("res://scripts/items/effects/throw_bomb_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.PLAYER_GRAY,
		load("res://scripts/items/effects/player_gray_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.GARMENT_HEAD_SCALE,
		load("res://scripts/items/effects/garment_head_scale_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.GARMENT_BODY_SCALE,
		load("res://scripts/items/effects/garment_body_scale_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.GARMENT_SPRING_WOBBLE,
		load("res://scripts/items/effects/garment_spring_wobble_effect.gd")
	)
	ItemEffectRegistry.register(
		ItemTypes.EffectKind.GARMENT_EMISSION_GLOW,
		load("res://scripts/items/effects/garment_emission_glow_effect.gd")
	)

## 玩家使用道具的唯一入口
## source_player: 使用者（null = 系統觸發），item_id 對應 items.json
func use_item(source_player: PlayerController, item_id: String, extra: Dictionary = {}) -> void:
	var def := _item_config.get_item(item_id)
	if def == null:
		push_warning("ItemSystem: unknown item_id '%s'" % item_id)
		return

	_spawn_use_vfx(def, source_player)

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
	# 联机：host 广播道具使用，client 只播 VFX 不应用效果（效果已由 host 权威模拟）
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_item_used(src_index, item_id)

## client：仅播放使用 VFX（host 广播触发，不应用效果逻辑）
func play_use_vfx_only(item_id: String, player_index: int) -> void:
	var def := _item_config.get_item(item_id)
	if def == null:
		return
	_spawn_use_vfx(def, _find_player(player_index))

func _find_player(player_index: int) -> PlayerController:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as PlayerController
		if p and p.player_index == player_index:
			return p
	return null

## 在使用者位置實例化並播放一次性特效，播完自動銷毀
func _spawn_use_vfx(def: ItemDef, source_player: PlayerController) -> void:
	if def.use_vfx.is_empty():
		return
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var scene: PackedScene = load(def.use_vfx)
	if scene == null:
		push_warning("ItemSystem: use_vfx scene not found '%s'" % def.use_vfx)
		return
	var vfx: Node3D = scene.instantiate() as Node3D
	if vfx == null:
		return
	if "autoplay" in vfx:
		vfx.autoplay = false
	if "one_shot" in vfx:
		vfx.one_shot = true

	match def.use_vfx_mode:
		ItemDef.VfxMode.ATTACH_PLAYER:
			if source_player:
				source_player.add_child(vfx)
				vfx.position = Vector3.ZERO
			else:
				current_scene.add_child(vfx)
		ItemDef.VfxMode.ATTACH_CAMERA:
			var cam := get_viewport().get_camera_3d()
			if cam:
				cam.add_child(vfx)
				vfx.position = Vector3(0.0, 0.0, -1.5)
			else:
				current_scene.add_child(vfx)
				if source_player:
					vfx.global_position = source_player.global_position
		_: # VfxMode.WORLD
			current_scene.add_child(vfx)
			if source_player:
				vfx.global_position = source_player.global_position

	if vfx.has_method("play"):
		vfx.play()
	var anim: AnimationPlayer = vfx.get_node_or_null("AnimationPlayer")
	if anim:
		await anim.animation_finished
	else:
		await get_tree().create_timer(0.5).timeout
	if is_instance_valid(vfx):
		vfx.queue_free()

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
