## 职责：camera_offset 效果 —— 主相机临时聚焦到使用道具的玩家，持续 N 秒后归位
## target 应配置为 world；invoker 由 ctx.extra["invoker"] 传入

class_name CameraOffsetEffect
extends ItemEffect

## 归位过渡时长（秒）
const RETURN_DURATION: float = 0.6

var _focus_behavior: PlayerFocusBehavior = null
## 效果触发前的相机 Transform，归位时还原
var _origin_transform: Transform3D = Transform3D.IDENTITY

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
	# 记录触发前的相机位姿，供归位使用
	var cam: Camera3D = controller.get_camera() as Camera3D
	if cam:
		_origin_transform = cam.global_transform
	_focus_behavior = PlayerFocusBehavior.new()
	_focus_behavior.target_player = invoker
	controller.push_behavior(_focus_behavior)

func revert(ctx: ItemContext) -> void:
	var controller := CameraSystem.get_main_controller()
	if controller == null:
		return
	if _focus_behavior != null:
		controller.pop_behavior(_focus_behavior)
		_focus_behavior = null
	# push 归位行为，RETURN_DURATION 秒后自动 pop，恢复下层 GroupFollowBehavior
	var ret := CameraReturnBehavior.new()
	ret.origin_transform = _origin_transform
	controller.push_behavior(ret, RETURN_DURATION)
