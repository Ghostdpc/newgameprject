## 職責：固定拍攝行為，相機保持定點朝向目標

class_name FixedShotBehavior
extends CameraBehavior

var position: Vector3 = Vector3(0.0, 20.0, 0.0)
var look_target: Vector3 = Vector3.ZERO

func update(camera: Camera3D, _delta: float) -> void:
	camera.global_position = position
	camera.look_at(look_target, Vector3.UP)
