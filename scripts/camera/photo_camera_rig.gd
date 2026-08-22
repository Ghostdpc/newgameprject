## 职责：可复用的拍照相机组件（相机模型 + 拍照机制一体）
## 策划用法：把 PhotoCameraRig 拖进关卡场景，然后：
##   1. 摆 rig 位置 = 相机位置
##   2. use_rig_rotation 关闭 → 拖动 LookTarget 子节点到拍摄区域中心
##      use_rig_rotation 开启 → 直接拖 rig 节点调朝向（与主相机所见即所得一致）
##   3. 设置 fov / viewport_size
## @tool：编辑器里拖 rig/LookTarget 实时更新相机朝向
## 机制：相机持续渲染到内部 SubViewport，供 HUD 取景框实时显示 + 快门截图。
## 相机模型与相机同位置，但放在独立 visibility layer，拍照相机 cull_mask 排除它，
## 因此拍照画面看不到模型（无黑球遮挡），主相机能看到模型（舞台上有台相机的视觉）。

@tool
class_name PhotoCameraRig
extends Node3D

## 模型所在 visibility layer（默认 3，避开 layer 1 场景 / layer 2 结算遮罩）
const MODEL_LAYER: int = 3

@export var fov: float = 45.0
@export var viewport_size: Vector2i = Vector2i(640, 360)
## 拍照相机渲染的 cull_mask（默认只渲染 layer 1，排除模型）
@export var cull_mask: int = 1
## true = 相机朝向读 rig 节点的 rotation（拖 rig 即调朝向，与主相机一致）
## false = 朝向读 LookTarget 子节点（拖 LookTarget 到拍摄中心，默认行为）
@export var use_rig_rotation: bool = false

@onready var _photo_viewport: SubViewport = $PhotoViewport
@onready var _photo_camera: Camera3D = $PhotoViewport/PhotoCamera
@onready var _controller: CameraController = $PhotoViewport/PhotoCamera/CameraController
@onready var _look_target: Node3D = $LookTarget
@onready var _model: Node3D = $Model

var _behavior: FixedShotBehavior

func _ready() -> void:
	add_to_group("photo_camera_rig")
	_apply_config()
	_orient_model()

## 运行时 + 编辑器（@tool）每帧同步：拖 rig / LookTarget 实时更新相机朝向
func _process(_delta: float) -> void:
	if not _behavior or not _photo_camera:
		return
	_behavior.position = global_position
	_behavior.look_target = get_look_target()
	if Engine.is_editor_hint():
		# 编辑器预览：直接同步相机位姿（无 behavior 更新循环时）
		_photo_camera.global_position = global_position
		_photo_camera.look_at(get_look_target(), Vector3.UP)
	_orient_model()

func _apply_config() -> void:
	_photo_camera.fov = fov
	_photo_camera.cull_mask = cull_mask
	_photo_viewport.size = viewport_size
	_apply_model_layer(_model)

	_controller.init(_photo_camera)
	_behavior = FixedShotBehavior.new()
	_behavior.position = global_position
	_behavior.look_target = get_look_target()
	_controller.push_behavior(_behavior)
	CameraSystem.register_photo_camera(_controller)

## 拍摄区域中心（世界坐标）。use_rig_rotation 时读 rig 朝向，否则用 LookTarget 子节点
func get_look_target() -> Vector3:
	if use_rig_rotation:
		return global_position + (-global_basis.z) * 10.0
	if _look_target:
		return _look_target.global_position
	return global_position + Vector3(0, 0, -10)

func _orient_model() -> void:
	if _model:
		_model.look_at(get_look_target(), Vector3.UP)

func _apply_model_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1 << (MODEL_LAYER - 1)
	for child in node.get_children():
		_apply_model_layer(child)

# ---- 对外接口 ----

func get_camera() -> Camera3D:
	return _photo_camera

func get_controller() -> CameraController:
	return _controller

func get_render_viewport() -> Viewport:
	return _photo_viewport
