## 职责：标题界面背景相机 —— 以编辑器里摆放的 Transform 为初始机位，
## 运行时绕 pivot 缓慢环绕（半径/高度/起始角均从初始机位反推），注视房间中心
@tool
extends Camera3D

## 环绕中心（相机绕此点旋转并注视，落在房间地面上方一点）
@export var pivot: Vector3 = Vector3(0.9, 1.0, -2.5)
## 注视点相对 pivot 的抬高量
@export var look_height: float = 0.8
## 环绕角速度（度/秒），正值顺时针；设 0 则静止在初始机位
@export var speed_deg: float = 6.0

# 以下由初始 Transform 反推得到（水平半径 / 相对高度 / 起始角）
var _radius: float = 0.0
var _height: float = 0.0
var _angle: float = 0.0

func _ready() -> void:
	# 用编辑器摆放的当前位置作为初始机位，反推环绕参数
	var offset := global_position - pivot
	_radius = Vector2(offset.x, offset.z).length()
	_height = offset.y
	_angle = atan2(offset.x, offset.z)
	_update_transform()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_angle += deg_to_rad(speed_deg) * delta
	_update_transform()

func _update_transform() -> void:
	var pos := pivot + Vector3(sin(_angle) * _radius, _height, cos(_angle) * _radius)
	global_position = pos
	look_at(pivot + Vector3(0.0, look_height, 0.0), Vector3.UP)
