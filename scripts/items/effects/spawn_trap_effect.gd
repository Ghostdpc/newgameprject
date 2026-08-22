## 職責：spawn_trap 效果 —— 在使用者腳下生成放置物（陷阱）

class_name SpawnTrapEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	# WORLD target 時 source_player 為 null，從 extra["invoker"] 取原始使用者
	var placer: PlayerController = ctx.source_player
	if placer == null:
		placer = ctx.extra.get("invoker") as PlayerController
	if placer == null:
		push_warning("SpawnTrapEffect: no valid placer found")
		return
	var trap_id: String = str(params.get("trap_id", ""))
	if trap_id.is_empty():
		push_warning("SpawnTrapEffect: trap_id is empty")
		return
	var trap_def: TrapDef = ItemSystem._item_config.get_trap(trap_id)
	if trap_def == null:
		push_warning("SpawnTrapEffect: unknown trap_id '%s'" % trap_id)
		return
	var instance := TrapInstance.new()
	# setup 先於 add_child，確保 collision_layer/mask 在進入物理世界前設置好
	instance.setup(trap_def, placer)
	placer.get_tree().current_scene.add_child(instance)
	instance.global_position = placer.global_position
