## 職責：群組跟隨行為，自動縮放覆蓋所有玩家

class_name GroupFollowBehavior
extends CameraBehavior

const MIN_HEIGHT: float = 8.0
const MAX_HEIGHT: float = 25.0
const PADDING: float = 4.0
const FOLLOW_SPEED: float = 4.0
const CAMERA_ANGLE_DEG: float = -55.0

func update(camera: Camera3D, delta: float) -> void:
	var players := camera.get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	var center := _calculate_center(players)
	var spread := _calculate_spread(players, center)
	var target_height := clampf(MIN_HEIGHT + spread * 0.8, MIN_HEIGHT, MAX_HEIGHT)
	var angle_rad := deg_to_rad(CAMERA_ANGLE_DEG)
	var offset := Vector3(0.0, target_height, -target_height / tan(abs(angle_rad)))
	var target_pos := center + offset

	camera.global_position = camera.global_position.lerp(target_pos, FOLLOW_SPEED * delta)
	camera.look_at(center, Vector3.UP)

func _calculate_center(players: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in players:
		sum += (p as Node3D).global_position
	return sum / players.size()

func _calculate_spread(players: Array, center: Vector3) -> float:
	var max_dist := 0.0
	for p in players:
		var d := (p as Node3D).global_position.distance_to(center)
		max_dist = maxf(max_dist, d)
	return max_dist + PADDING
