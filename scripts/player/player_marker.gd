## 职责：玩家脚底朝向/位置指示（Decal 贴花版）
## - 贴花资源：assets/textures/fx/ground_marker.png（水滴环+核心+前向箭头，白形+alpha）
## - 用 Decal 节点向下方投射，贴合当前所在物体表面（楼板/斜坡/平台）
## - raycast 向下探测，排除玩家自身与所有玩家（collision_layer 2）
## - 箭头指向模型正面（+Z，见 player_controller._turn_toward 注释），随角色旋转
## - 呼吸脉冲增强"位置信标"可读性
## - visibility layer 4：拍照相机 cull_mask=1 排除，不进合照

class_name PlayerMarker
extends Node3D

const MARKER_TEX := preload("res://assets/textures/fx/ground_marker.png")

const DECAL_HEIGHT := 0.6       # Decal 立方体高度（向下投影深度，小=贴合表面）
const RAY_LENGTH := 20.0        # 向下探测最大距离
const PLAYER_LAYER_BIT := 2     # 玩家所在物理层（用于排除）
const SNAP_OFFSET := Vector3(0, 0.03, 0)  # 贴地微调
const PULSE_SPEED := 3.0

@export var player_index: int = 0
## 方向圈投影尺寸（米），越小圈越小
@export var marker_size: float = 0.8
## 呼吸脉冲幅度（占尺寸比例）
@export var pulse_amp: float = 0.035
## 沿角色前向的偏移（米）：>0 向前，<0 向后，脚底中心为 0
@export var forward_offset: float = 0.1

var _decal: Decal
var _pulse_t: float = 0.0

func _ready() -> void:
	# player.tscn 未配置 export：从父节点 PlayerController 同步身份索引
	var pc := get_parent() as PlayerController
	if pc:
		player_index = pc.player_index
	_build_decal()
	_apply_ui_layer()

func _build_decal() -> void:
	_decal = Decal.new()
	_decal.name = "FacingMarker"
	_decal.texture_albedo = MARKER_TEX
	_decal.modulate = PlayerConfig.get_color(player_index)
	# 投射面：排除玩家层。玩家是 CharacterBody，贴花不该贴玩家身体。
	_decal.cull_mask = ~PLAYER_LAYER_BIT
	# 斜面渐隐：凹凸/倾斜表面上避免投影被拉伸成大块
	_decal.normal_fade = 0.4
	_decal.size = Vector3(marker_size, DECAL_HEIGHT, marker_size)
	add_child(_decal)
	_pulse_t = randf() * TAU   # 各玩家脉冲错相

## 每帧向下 raycast 找支撑面，把 Decal 定位到该表面（水平向 +Z 前向）
func _process(delta: float) -> void:
	if _decal == null:
		return
	_update_snap()
	_pulse_t += delta * PULSE_SPEED
	var s := 1.0 + sin(_pulse_t) * pulse_amp
	_decal.size = Vector3(marker_size * s, DECAL_HEIGHT, marker_size * s)

## raycast 向下探测，把 Decal 中心放到支撑面，投影轴对齐表面法线
func _update_snap() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3.UP * 1.0
	query.to = global_position - Vector3.UP * RAY_LENGTH
	query.exclude = [get_parent()]            # 排除玩家自身碰撞体
	query.collision_mask = ~PLAYER_LAYER_BIT  # 排除所有玩家
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_decal.visible = false
		return
	_decal.visible = true
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	# Decal 投影轴为局部 -Y，让 local -Y 对齐表面法线（贴合斜面）
	# 纹理 V+（箭头）在 Decal 中对应 local -Z，故 local +Z = -tangent
	var n := normal.normalized()
	var yaw: float = (get_parent() as Node3D).rotation.y
	# forward：角色前进方向 = 绕 Y 转 yaw 后的世界 +Z
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	# 目标：纹理顶部(箭头)沿投影面指向前进方向 fwd
	var tangent := fwd - n * fwd.dot(n)
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT - n * Vector3.RIGHT.dot(n)
	tangent = tangent.normalized()
	# 沿前向在支撑面上平移，脚底中心为 0
	_decal.global_position = hit.position + SNAP_OFFSET + tangent * forward_offset
	# 右手系：x = y × z，保证行列式 +1，否则 Decal 投影方向会翻转朝上
	var y_axis := n
	var z_axis := -tangent
	var x_axis := y_axis.cross(z_axis)
	_decal.global_transform.basis = Basis(x_axis, y_axis, z_axis)

## 玩家标识放 layer 4，拍照相机 cull_mask=1 排除，不进照片
func _apply_ui_layer() -> void:
	_set_layer_recursive(self, 4)

func _set_layer_recursive(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layer_recursive(child, layers)
