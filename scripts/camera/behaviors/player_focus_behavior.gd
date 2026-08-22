## 职责：单玩家聚焦行为，主相机保持朝向不变，平移使玩家居中
## 进入时记录相机相对玩家的偏移向量，之后只平移（朝向/角度/高差不变）
## 包含防穿模：从玩家位置向目标相机位置做射线，碰到几何体则推出碰撞面
## 由 camera_offset 道具效果临时 push，效果结束后 pop 恢复原行为

class_name PlayerFocusBehavior
extends CameraBehavior

const FOLLOW_SPEED: float = 5.0
## 防穿模：相机到碰撞面的最小间距（米）
const CLIP_MARGIN: float = 0.3
## 射线检测层（world / static body）
const CLIP_MASK: int = 1

var target_player: Node3D = null

var _cam_offset: Vector3 = Vector3.ZERO
var _offset_captured: bool = false

func update(camera: Camera3D, delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		return
	if not _offset_captured:
		_cam_offset = camera.global_position - target_player.global_position
		_offset_captured = true
	var desired_pos := target_player.global_position + _cam_offset
	# 防穿模：从玩家头部到目标相机位置做射线
	desired_pos = _safe_position(camera, target_player.global_position, desired_pos)
	camera.global_position = camera.global_position.lerp(desired_pos, FOLLOW_SPEED * delta)
	camera.look_at(target_player.global_position, Vector3.UP)

func _safe_position(camera: Camera3D, from: Vector3, to: Vector3) -> Vector3:
	var space := camera.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = CLIP_MASK
	var result := space.intersect_ray(params)
	if result.is_empty():
		return to
	return result["position"] + result["normal"] * CLIP_MARGIN
