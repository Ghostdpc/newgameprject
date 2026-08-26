## 职责：camera_offset 效果 —— 主相机临时聚焦到使用道具的玩家，持续 N 秒后归位
## target 应配置为 world；invoker 由 ctx.extra["invoker"] 传入
## 注意：ItemDef.effects 中的 effect 是共享单例，per-use 状态必须存 ctx.extra，
##       不能存 self（否则并发/连续使用会互相覆盖，导致行为遗留在相机栈上）

class_name CameraOffsetEffect
extends ItemEffect

## 归位过渡时长（秒）
const RETURN_DURATION: float = 0.6

const KEY_BEHAVIOR: String = "_camera_focus_behavior"
const KEY_ORIGIN: String = "_camera_origin_transform"

func apply(ctx: ItemContext) -> void:
	var invoker: PlayerController = ctx.extra.get("invoker") as PlayerController
	if invoker == null:
		invoker = ctx.source_player
	if invoker == null:
		return
	var controller: CameraController = CameraSystem.get_main_controller() as CameraController
	if controller == null:
		push_warning("CameraOffsetEffect: no main camera controller")
		return
	# 记录触发前的相机位姿，供归位使用
	var cam: Camera3D = controller.get_camera() as Camera3D
	if cam:
		ctx.extra[KEY_ORIGIN] = cam.global_transform
	var focus := PlayerFocusBehavior.new()
	focus.target_player = invoker
	controller.push_behavior(focus)
	ctx.extra[KEY_BEHAVIOR] = focus
	# 联机：host 广播相机聚焦，client 主相机跟随对应 puppet
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_camera_focus(invoker.player_index, duration)

func revert(ctx: ItemContext) -> void:
	var controller: CameraController = CameraSystem.get_main_controller() as CameraController
	if controller == null:
		return
	var focus: PlayerFocusBehavior = ctx.extra.get(KEY_BEHAVIOR) as PlayerFocusBehavior
	if focus != null:
		controller.pop_behavior(focus)
		ctx.extra.erase(KEY_BEHAVIOR)
	# push 归位行为，RETURN_DURATION 秒后自动 pop，恢复下层原有行为（FixedShotBehavior）
	var ret := CameraReturnBehavior.new()
	ret.origin_transform = ctx.extra.get(KEY_ORIGIN, Transform3D.IDENTITY)
	controller.push_behavior(ret, RETURN_DURATION)
