## 职责：拍照相机（无独立摆放，frustum 严格跟随 UI 相机框）
## 每帧同步：PhotoCamera 位置/朝向 = 主相机；用 PROJECTION_FRUSTUM 模式
## 把近平面尺寸/偏移设为「主相机视野中相机框覆盖的区域」。
## 效果：从主相机视角看，相机框内的画面 = 拍照画面 = 截帧 = 小 RT。
## 预留调整接口：
##   set_extra_offset(ndc) —— 框中心偏移（相机遥控器等）
##   set_extra_scale(scale) —— 框范围缩放（>1 更大）

class_name PhotoCameraRig
extends Node3D

@export var cull_mask: int = 1

@onready var _photo_viewport: SubViewport = $PhotoViewport
@onready var _photo_camera: Camera3D = $PhotoViewport/PhotoCamera

var _main_camera: Camera3D
var _viewfinder: Control

## 预留调整：NDC 单位偏移 + 缩放
var extra_offset_ndc := Vector2.ZERO
var extra_scale := 1.0

var _last_vp_size := Vector2i.ZERO

func _ready() -> void:
	add_to_group("photo_camera_rig")
	_photo_camera.cull_mask = cull_mask
	_photo_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_resolve_refs()
	CameraSystem.register_photo_camera(self)

func _resolve_refs() -> void:
	var mains := get_tree().get_nodes_in_group("main_camera")
	if not mains.is_empty():
		_main_camera = mains[0] as Camera3D
	var vfs := get_tree().get_nodes_in_group("camera_viewfinder")
	if not vfs.is_empty():
		_viewfinder = vfs[0] as Control

func _process(_delta: float) -> void:
	# group 注册可能晚于 rig._ready（关卡 _setup_cameras 才加 group），延迟重试
	if _main_camera == null or _viewfinder == null:
		_resolve_refs()
	_sync_frustum()

## 核心：把 PhotoCamera 视锥对齐到主相机视野中相机框覆盖的区域
func _sync_frustum() -> void:
	if not _main_camera or not _viewfinder or not _photo_camera:
		return

	# 位置朝向严格跟随主相机
	_photo_camera.global_transform = _main_camera.global_transform

	var screen := _viewfinder.get_global_rect()
	var vp_rect := get_viewport().get_visible_rect()
	if vp_rect.size.x <= 0.0 or vp_rect.size.y <= 0.0:
		return

	var znear := _photo_camera.near
	var main_fov_rad := deg_to_rad(_main_camera.fov)
	var main_aspect := vp_rect.size.x / vp_rect.size.y

	# 主相机在近平面处的半尺寸（世界单位）
	var half_h := znear * tan(main_fov_rad * 0.5)
	var half_w := half_h * main_aspect

	# 相机框占屏幕的比例
	var h_ratio := screen.size.y / vp_rect.size.y

	# 框中心相对屏中心的 NDC 偏移（+ 预留额外偏移）
	var center := screen.get_center()
	var sc := vp_rect.size * 0.5
	var ndc := Vector2(
		(center.x - sc.x) / sc.x,
		(center.y - sc.y) / sc.y) + extra_offset_ndc

	# FRUSTUM 参数：
	#   size = 近平面垂直尺寸（世界单位），KEEP_HEIGHT 下水平尺寸 = size * viewport_aspect
	#   frustum_offset = 近平面中心偏移（世界单位）
	var fsize := half_h * 2.0 * h_ratio * extra_scale
	var foffset := Vector2(ndc.x * half_w, -ndc.y * half_h)

	_photo_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_photo_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_photo_camera.size = fsize
	_photo_camera.frustum_offset = foffset

	# SubViewport 渲染分辨率匹配框尺寸（变化时才改，避免每帧重建）
	var new_vp := Vector2i(maxi(1, int(screen.size.x)), maxi(1, int(screen.size.y)))
	if new_vp != _last_vp_size:
		_last_vp_size = new_vp
		_photo_viewport.size = new_vp

# ---- 预留调整接口 ----

## 框中心额外偏移（NDC 单位，1.0 = 半个屏幕宽/高）。道具如相机遥控器调用。
func set_extra_offset(offset_ndc: Vector2) -> void:
	extra_offset_ndc = offset_ndc

## 框范围额外缩放（1.0 = 原始框大小，>1 更大范围）。
func set_extra_scale(scale: float) -> void:
	extra_scale = scale

## 重置所有额外调整
func reset_adjust() -> void:
	extra_offset_ndc = Vector2.ZERO
	extra_scale = 1.0

# ---- 对外接口 ----

func get_camera() -> Camera3D:
	return _photo_camera

func get_render_viewport() -> Viewport:
	return _photo_viewport
