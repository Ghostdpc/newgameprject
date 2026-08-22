## 职责：camera_offset 效果 —— 主相机临时聚焦到使用道具的玩家，持续 N 秒后恢复原行为
## target 应配置为 world；invoker 由 ctx.extra["invoker"] 传入

class_name CameraOffsetEffect
extends ItemEffect

## 记录本次 apply 创建的行为实例，供 revert 时 pop
var _focus_behavior: PlayerFocusBehavior = null

func apply(ctx: ItemContext) -> void:
	var invoker: PlayerController = ctx.extra.get("invoker") as PlayerController
	if invoker == null:
		invoker = ctx.source_player
	if invoker == null:
		return
	var controller := CameraSystem.get_main_controller()
	if controller == null:
		push_warning("CameraOffsetEffect: no main camera controller")
		return
	_focus_behavior = PlayerFocusBehavior.new()
	_focus_behavior.target_player = invoker
	controller.push_behavior(_focus_behavior)

func revert(ctx: ItemContext) -> void:
	if _focus_behavior == null:
		return
	var controller := CameraSystem.get_main_controller()
	if controller:
		controller.pop_behavior(_focus_behavior)
	_focus_behavior = null
