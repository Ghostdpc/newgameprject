## 职责：相机归位行为，平滑将相机插值回到效果触发前的位置/朝向
## 由 CameraOffsetEffect.revert 推入，配合 duration 自动 pop 后由下层行为接管

class_name CameraReturnBehavior
extends CameraBehavior

const RETURN_SPEED: float = 6.0

## 效果触发前记录的原始 Transform
var origin_transform: Transform3D = Transform3D.IDENTITY

func update(camera: Camera3D, delta: float) -> void:
	camera.global_transform = camera.global_transform.interpolate_with(
		origin_transform, RETURN_SPEED * delta)
