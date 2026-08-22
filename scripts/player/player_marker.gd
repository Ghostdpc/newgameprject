## 职责：玩家脚底朝向/位置指示（美术贴花版）
## - 贴花资源：assets/textures/fx/ground_marker.png（水滴环+核心+前向箭头，白形+alpha）
## - StandardMaterial3D：unshaded + ALPHA，正常深度测试（被角色/场景自然遮挡，踩在脚下）
## - 箭头指向模型正面（+Z，见 player_controller._turn_toward 注释），随角色旋转
## - 轻微呼吸脉冲增强"位置信标"可读性
## - visibility layer 4：拍照相机 cull_mask=1 排除，不进合照

class_name PlayerMarker
extends Node3D

const MARKER_TEX := preload("res://assets/textures/fx/ground_marker.png")

const MARKER_SIZE := 2.0                 # 贴花 quad 边长（米）
const RING_OFFSET := Vector3(0, 0.03, 0) # 贴地微调，防 z-fighting
const PULSE_SPEED := 3.0
const PULSE_AMP := 0.035

@export var player_index: int = 0

var _ring: MeshInstance3D
var _pulse_t: float = 0.0

func _ready() -> void:
	# player.tscn 未配置 export：从父节点 PlayerController 同步身份索引
	var pc := get_parent() as PlayerController
	if pc:
		player_index = pc.player_index
	_build_marker()
	_apply_ui_layer()

func _build_marker() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false   # 光圈贴地，被角色身体自然遮挡
	mat.albedo_texture = MARKER_TEX
	mat.albedo_color = PlayerConfig.get_color(player_index)
	mat.render_priority = 10

	var quad := QuadMesh.new()
	quad.size = Vector2(MARKER_SIZE, MARKER_SIZE)

	_ring = MeshInstance3D.new()
	_ring.name = "FacingMarker"
	_ring.mesh = quad
	_ring.material_override = mat
	# 贴图布局：纹理上(箭头)→世界 +Z（模型正面），法线朝上；贴花左右对称
	_ring.transform.basis = Basis(
		Vector3(-1, 0, 0),   # 纹理右 → 世界 -X
		Vector3(0, 0, 1),    # 纹理上(箭头) → 世界 +Z
		Vector3(0, 1, 0))    # 法线 → 世界 +Y
	_ring.position = RING_OFFSET
	add_child(_ring)
	_pulse_t = randf() * TAU   # 各玩家脉冲错相

## 呼吸脉冲（位置信标）
func _process(delta: float) -> void:
	if _ring == null:
		return
	_pulse_t += delta * PULSE_SPEED
	var s := 1.0 + sin(_pulse_t) * PULSE_AMP
	_ring.scale = Vector3(s, s, s)

## 玩家标识放 layer 4，拍照相机 cull_mask=1 排除，不进照片
func _apply_ui_layer() -> void:
	_set_layer_recursive(self, 4)

func _set_layer_recursive(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layer_recursive(child, layers)
