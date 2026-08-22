## 職責：玩家腳底朝向光環
## - 腳底瓜子型，隨角色朝向旋轉，顏色為身份色

class_name PlayerMarker
extends Node3D

## 玩家索引 → 顏色（不依賴 player_color，強制身份色）
const PLAYER_COLORS: Array[Color] = [
	Color(0.2, 0.5, 1.0),
	Color(1.0, 0.6, 0.1),
	Color(0.3, 0.9, 0.3),
	Color(0.8, 0.4, 0.9),
]

const RING_OFFSET: Vector3 = Vector3(0, 0.03, 0)

@export var player_index: int = 0

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

func _ready() -> void:
	var color: Color = PLAYER_COLORS[player_index] if player_index < PLAYER_COLORS.size() else PLAYER_COLORS[0]
	_build_facing_ring(color)
	_apply_ui_layer()

## 玩家标识（朝向光環）放 layer 3，拍照相机 cull_mask=1 排除，不进照片
func _apply_ui_layer() -> void:
	_set_layer_recursive(self, 4)

func _set_layer_recursive(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layer_recursive(child, layers)

## 腳底瓜子型朝向前後光環（橢圓，長軸指向移動方向）
func _build_facing_ring(color: Color) -> void:
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = color
	_ring_mat.no_depth_test = true
	_ring = MeshInstance3D.new()
	_ring.name = "FacingRing"
	_ring.mesh = _make_seed_shape_mesh()
	_ring.material_override = _ring_mat
	_ring.position = RING_OFFSET
	_ring.rotation_degrees = Vector3(-90, 0, 0)  # 平貼地面
	add_child(_ring)

## 瓜子形輪廓線（長軸為 Z，指向角色前向）
func _make_seed_shape_mesh() -> ImmediateMesh:
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _ring_mat)
	var segments := 24
	for i in segments:
		var a0: float = TAU * float(i) / segments
		var a1: float = TAU * float(i + 1) / segments
		# 瓜子形：長軸 Z (0.6)，短軸 X (0.35)；朝向角色前向 +Z
		imm.surface_add_vertex(Vector3(sin(a0) * 0.35, 0.0, cos(a0) * 0.6))
		imm.surface_add_vertex(Vector3(sin(a1) * 0.35, 0.0, cos(a1) * 0.6))
	imm.surface_end()
	return imm
