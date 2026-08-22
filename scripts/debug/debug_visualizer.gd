## 職責：開發調試可視化（碰撞體 / 骨骼線），熱鍵 F1/F2 切換
## 碰撞體與骨骼線均自繪並開啟 no_depth_test，穿透模型可見

class_name DebugVisualizer
extends Node3D

const DEBUG_BONE_COLOR: Color = Color(0.0, 1.0, 1.0, 1.0)
const DEBUG_COLLISION_COLOR: Color = Color(1.0, 0.6, 0.0, 1.0)
const CAPSULE_SEGMENTS: int = 16

var _collisions_on: bool = false
var _bones_on: bool = false
var _bone_mesh: MeshInstance3D
var _collision_mesh: MeshInstance3D
var _immediate: ImmediateMesh
var _line_mat: StandardMaterial3D
var _collision_mat: StandardMaterial3D

func _ready() -> void:
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = DEBUG_BONE_COLOR
	_line_mat.no_depth_test = true
	_bone_mesh = MeshInstance3D.new()
	_bone_mesh.name = "DebugBoneLines"
	_bone_mesh.mesh = ImmediateMesh.new()
	add_child(_bone_mesh)
	_bone_mesh.visible = false

	_collision_mat = StandardMaterial3D.new()
	_collision_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_collision_mat.albedo_color = DEBUG_COLLISION_COLOR
	_collision_mat.no_depth_test = true
	_collision_mesh = MeshInstance3D.new()
	_collision_mesh.name = "DebugCollisionShapes"
	_collision_mesh.mesh = ImmediateMesh.new()
	add_child(_collision_mesh)
	_collision_mesh.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			_toggle_collisions()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F2:
			_toggle_bones()
			get_viewport().set_input_as_handled()

func _toggle_collisions() -> void:
	_collisions_on = not _collisions_on
	_collision_mesh.visible = _collisions_on
	print("DebugVisualizer: collisions = ", _collisions_on)

func _toggle_bones() -> void:
	_bones_on = not _bones_on
	_bone_mesh.visible = _bones_on
	print("DebugVisualizer: bones = ", _bones_on)

func _process(_delta: float) -> void:
	if _bones_on:
		_rebuild_bone_lines()
	if _collisions_on:
		_rebuild_collisions()

## 遍歷場景所有 Skeleton3D，畫骨線（父骨→子骨）
func _rebuild_bone_lines() -> void:
	var imm: ImmediateMesh = _bone_mesh.mesh as ImmediateMesh
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	var skeletons := _find_all_skeletons(get_tree().current_scene)
	for skeleton in skeletons:
		var sk := skeleton as Skeleton3D
		if not sk:
			continue
		for i in sk.get_bone_count():
			var parent_idx: int = sk.get_bone_parent(i)
			if parent_idx == -1:
				continue
			var from: Vector3 = sk.global_transform * sk.get_bone_global_pose(parent_idx).origin
			var to: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
			imm.surface_add_vertex(from)
			imm.surface_add_vertex(to)
	imm.surface_end()

## 遍歷所有角色（players 組），只畫角色身上的碰撞體線框
func _rebuild_collisions() -> void:
	var imm: ImmediateMesh = _collision_mesh.mesh as ImmediateMesh
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _collision_mat)
	for player in get_tree().get_nodes_in_group("players"):
		for child in (player as Node).find_children("*", "CollisionShape3D", true, false):
			var cs := child as CollisionShape3D
			if not cs or not cs.shape:
				continue
			var tf := cs.global_transform
			if cs.shape is CapsuleShape3D:
				_draw_capsule(imm, tf, cs.shape as CapsuleShape3D)
			elif cs.shape is BoxShape3D:
				_draw_box(imm, tf, cs.shape as BoxShape3D)
	imm.surface_end()

func _draw_capsule(imm: ImmediateMesh, tf: Transform3D, shape: CapsuleShape3D) -> void:
	var radius: float = shape.radius
	var height: float = shape.height
	var half: float = height * 0.5
	var mid_half: float = half - radius
	# 中段圓柱的上下兩圈
	for ring_y in [mid_half, -mid_half]:
		for i in CAPSULE_SEGMENTS:
			var a0: float = TAU * float(i) / CAPSULE_SEGMENTS
			var a1: float = TAU * float(i + 1) / CAPSULE_SEGMENTS
			imm.surface_add_vertex(tf * Vector3(cos(a0) * radius, ring_y, sin(a0) * radius))
			imm.surface_add_vertex(tf * Vector3(cos(a1) * radius, ring_y, sin(a1) * radius))
	# 兩端半球：沿子午線畫圈
	for i in CAPSULE_SEGMENTS:
		var a: float = TAU * float(i) / CAPSULE_SEGMENTS
		var base: Vector3 = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		# 頂部半球（z 剖面弧）
		imm.surface_add_vertex(tf * (base + Vector3(0, mid_half, 0)))
		imm.surface_add_vertex(tf * (base + Vector3(0, half, 0)))
		# 底部半球
		imm.surface_add_vertex(tf * (base - Vector3(0, mid_half, 0)))
		imm.surface_add_vertex(tf * (base - Vector3(0, half, 0)))
	# 垂直方向連接線（把上下半球的邊緣點連起來，構成網格感）
	for i in CAPSULE_SEGMENTS:
		var a: float = TAU * float(i) / CAPSULE_SEGMENTS
		var dir: Vector3 = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		imm.surface_add_vertex(tf * (dir + Vector3(0, mid_half, 0)))
		imm.surface_add_vertex(tf * (dir - Vector3(0, mid_half, 0)))

func _draw_box(imm: ImmediateMesh, tf: Transform3D, shape: BoxShape3D) -> void:
	var s: Vector3 = shape.size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-s.x, -s.y, -s.z), Vector3(s.x, -s.y, -s.z),
		Vector3(s.x, -s.y, s.z), Vector3(-s.x, -s.y, s.z),
		Vector3(-s.x, s.y, -s.z), Vector3(s.x, s.y, -s.z),
		Vector3(s.x, s.y, s.z), Vector3(-s.x, s.y, s.z),
	]
	var edges: Array = [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for e in edges:
		imm.surface_add_vertex(tf * corners[e[0]])
		imm.surface_add_vertex(tf * corners[e[1]])

func _find_all_skeletons(n: Node, acc: Array = []) -> Array:
	if n is Skeleton3D:
		acc.append(n)
	for c in n.get_children():
		_find_all_skeletons(c, acc)
	return acc
