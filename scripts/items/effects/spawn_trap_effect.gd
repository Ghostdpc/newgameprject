## 职责：spawn_trap 效果 —— 在使用者脚下生成放置物（陷阱）
## params.spawn_y（可选）：固定生成高度，不设则使用放置者当前 y 坐标

class_name SpawnTrapEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	# WORLD target 时 source_player 为 null，从 extra["invoker"] 取原始使用者
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
	# setup 先于 add_child，确保 collision_layer/mask 在进入物理世界前设置好
	instance.setup(trap_def, placer)
	instance.spawn_id = NetManager.next_entity_id()
	placer.get_tree().current_scene.add_child(instance)
	var spawn_pos := placer.global_position
	if params.has("spawn_y"):
		spawn_pos.y = float(params["spawn_y"])
	instance.global_position = spawn_pos
	# 联机：host 广播陷阱生成
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_trap_spawn(trap_id, spawn_pos, instance.spawn_id)
