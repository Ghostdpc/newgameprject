## 职责：单玩家聚焦行为，主相机保持朝向不变，平移使玩家居中
## 进入时记录相机相对于"当前 look target"的偏移向量，之后只换 look target 为玩家
## （等价于：相机随玩家整体平移，朝向/角度/高差完全不变）
## 由 camera_offset 道具效果临时 push，效果结束后 pop 恢复原行为

class_name PlayerFocusBehavior
extends CameraBehavior

const FOLLOW_SPEED: float = 5.0

var target_player: Node3D = null

## 相机相对 look target 的偏移，第一帧从当前 GroupFollowBehavior 的结果推算
var _cam_offset: Vector3 = Vector3.ZERO
var _offset_captured: bool = false

func update(camera: Camera3D, delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		return
	# 第一帧：把当前相机视为"已对准某个中心"，记录偏移
	if not _offset_captured:
		# 用相机当前朝向的反方向推算 look target（near 平面外某处），
		# 直接用当前相机位置 - 玩家位置作为偏移即可（平移型追踪）
		_cam_offset = camera.global_position - target_player.global_position
		_offset_captured = true
	var target_pos := target_player.global_position + _cam_offset
	camera.global_position = camera.global_position.lerp(target_pos, FOLLOW_SPEED * delta)
	# look_at 目标 = 玩家位置，使相机朝向始终指向玩家（保持原倾角，因偏移不变）
	camera.look_at(target_player.global_position, Vector3.UP)
