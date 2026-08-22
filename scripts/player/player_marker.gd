## 職責：玩家身份標識（形状 + 編號）與腳底朝向光環
## - 形状標識：P1藍圓 / P2橙三角 / P3綠方 / P4紫菱（頭上浮標）
## - 編號：Label3D 永遠顯示
## - 朝向光環：腳底瓜子型，隨角色朝向旋轉

class_name PlayerMarker
extends Node3D

## 玩家索引 → 形状 / 顏色（不依賴 player_color，強制身份色）
const PLAYER_META: Array = [
	{"shape": "circle",    "color": Color(0.2, 0.5, 1.0)},
	{"shape": "triangle",  "color": Color(1.0, 0.6, 0.1)},
	{"shape": "square",    "color": Color(0.3, 0.9, 0.3)},
	{"shape": "diamond",   "color": Color(0.8, 0.4, 0.9)},
]

const IDENTITY_OFFSET: Vector3 = Vector3(0, 2.7, 0)
const RING_OFFSET: Vector3 = Vector3(0, 0.03, 0)

@export var player_index: int = 0

var _shape_mesh: MeshInstance3D
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D

func _ready() -> void:
	var meta: Dictionary = PLAYER_META[player_index] if player_index < PLAYER_META.size() else PLAYER_META[0]
	var color: Color = meta["color"]
	_build_identity(meta["shape"], color)
	_build_number()
	_build_facing_ring(color)

## 頭上形狀浮標 + 編號
func _build_identity(shape: String, color: Color) -> void:
	_shape_mesh = MeshInstance3D.new()
	_shape_mesh.name = "IdentityShape"
	_shape_mesh.mesh = _new_shape_mesh(shape)
	_shape_mesh.position = IDENTITY_OFFSET
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	_shape_mesh.material_override = mat
	add_child(_shape_mesh)

func _build_number() -> void:
	_label = Label3D.new()
	_label.name = "IdentityNumber"
	_label.text = "P%d" % (player_index + 1)
	_label.position = IDENTITY_OFFSET + Vector3(0, 0.18, 0)
	_label.font_size = 48
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 1)
	_label.modulate = Color.WHITE
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	add_child(_label)

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

## 依形狀名生成 mesh
func _new_shape_mesh(shape: String) -> Mesh:
	match shape:
		"triangle":
			var tri := ImmediateMesh.new()
			tri.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			tri.surface_add_vertex(Vector3(0, 0.14, 0))
			tri.surface_add_vertex(Vector3(-0.12, -0.10, 0))
			tri.surface_add_vertex(Vector3(0.12, -0.10, 0))
			tri.surface_end()
			return tri
		"square":
			var quad := ArrayMesh.new()
			var arr := PackedVector3Array([Vector3(-0.11, 0.11, 0), Vector3(0.11, 0.11, 0), Vector3(0.11, -0.11, 0), Vector3(-0.11, -0.11, 0)])
			var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
			var m2 := ArrayMesh.new()
			var a: Array = []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = arr
			a[Mesh.ARRAY_INDEX] = idx
			m2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			return m2
		"diamond":
			var dia := ImmediateMesh.new()
			dia.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			dia.surface_add_vertex(Vector3(0, 0.15, 0))
			dia.surface_add_vertex(Vector3(0.1, 0.0, 0))
			dia.surface_add_vertex(Vector3(0, -0.15, 0))
			dia.surface_add_vertex(Vector3(0, 0.15, 0))
			dia.surface_add_vertex(Vector3(-0.1, 0.0, 0))
			dia.surface_add_vertex(Vector3(0, -0.15, 0))
			dia.surface_end()
			return dia
		_:  # circle
			var quad := ArrayMesh.new()
			var verts := PackedVector3Array()
			var idxs := PackedInt32Array()
			var seg := 24
			for i in seg:
				var a: float = TAU * float(i) / seg
				verts.append(Vector3(cos(a) * 0.13, sin(a) * 0.13, 0))
			for i in seg - 2:
				idxs.append(0)
				idxs.append(i + 1)
				idxs.append(i + 2)
			var m0 := ArrayMesh.new()
			var ar: Array = []
			ar.resize(Mesh.ARRAY_MAX)
			ar[Mesh.ARRAY_VERTEX] = verts
			ar[Mesh.ARRAY_INDEX] = idxs
			m0.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
			return m0
