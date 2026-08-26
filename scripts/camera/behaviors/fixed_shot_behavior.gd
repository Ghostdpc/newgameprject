## 职责：固定拍摄行为，相机保持定点朝向目标

class_name FixedShotBehavior
extends CameraBehavior

var position: Vector3 = Vector3(0.0, 20.0, 0.0)
var look_target: Vector3 = Vector3.ZERO

func update(camera: Camera3D, _delta: float) -> void:
	camera.global_position = position
	camera.look_at(look_target, Vector3.UP)
