## 职责：用 KayKit Prototype Bits 组件程序化搭建舞台
## - 每个组件自动生成 trimesh 碰撞
## - occluder 组件加入 photo_occluder 群组（结算遮罩分析用）
## - 尺寸基准（实测）：Floor 4x0.5x4 / Primitive_Floor 4x1x4 / Wall 4x4x0.53 /
##   Cube_Prototype_Small 2x2x2 / Pillar_A 0.6x4.1x0.6 / 假人 ~2.2 高

class_name StageBuilder
extends Node

const BITS_DIR := "res://assets/models/prototype_bits/Assets/gltf/"

var _scene_cache: Dictionary = {}

func load_piece(piece_name: String) -> PackedScene:
	if not _scene_cache.has(piece_name):
		_scene_cache[piece_name] = load(BITS_DIR + piece_name + ".gltf")
	return _scene_cache[piece_name]

func add_piece(root: Node3D, piece_name: String, pos: Vector3, rot_y_deg: float = 0.0,
		piece_scale: Vector3 = Vector3.ONE, occluder: bool = false, collision: bool = true,
		physical: bool = false) -> Node3D:
	var ps := load_piece(piece_name)
	if ps == null:
		push_warning("StageBuilder: 缺少组件 %s" % piece_name)
		return null
	var inst := ps.instantiate() as Node3D
	inst.name = "%s_%02d" % [piece_name, root.get_child_count()]
	inst.position = pos
	inst.rotation_degrees.y = rot_y_deg
	inst.scale = piece_scale
	if occluder:
		_add_to_group_recursive(inst, "photo_occluder")
	# 统一先加入 root（reparent 需在树内）
	root.add_child(inst)
	if physical and collision:
		# 可动物：把 inst 从 root 移入 PhysicalProp(RigidBody3D) 根下，物理驱动带动视觉
		_make_dynamic_prop(inst, pos)  # prop 已加入 root
	elif collision:
		_build_collision(inst)
	return inst

func _make_dynamic_prop(inst: Node3D, pos: Vector3) -> PhysicalProp:
	var prop := PhysicalProp.new()
	prop.name = "DynamicProp"
	prop.prop_mass = 8.0
	prop.push_strength = 25.0
	prop.position = pos  # 物理根在舞台位置
	prop.rotation_degrees.y = inst.rotation_degrees.y
	# 先让 prop 进树（reparent keep_global 才生效），再 reparent inst → inst 局部归零，mesh 贴住 prop
	inst.get_parent().add_child(prop)
	inst.reparent(prop)
	# 用 mesh 包围盒生成轻量 box 碰撞（质心匹配，不卡地）
	var mesh := find_child_mesh(inst)
	if mesh and mesh.mesh:
		var aabb := mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = aabb.get_center()
		prop.add_child(cs)
	return prop

func find_child_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := find_child_mesh(c)
		if r:
			return r
	return null

## 示范舞台：主甲板 + 双层高台 + 背景墙 + 前景遮挡物
## 座标约定：拍照相机在 +Z 侧朝 -Z 拍，背景墙在 -Z 侧
func build_show_stage(root: Node3D) -> void:
	# 外围地面（Primitive_Floor 4x1x4，顶面 y=0）
	for x in [-4.0, 0.0, 4.0]:
		add_piece(root, "Primitive_Floor", Vector3(x, -1.0, 6.0))
		add_piece(root, "Primitive_Floor", Vector3(x, -1.0, 10.0))
		add_piece(root, "Primitive_Floor", Vector3(x, -1.0, -6.0))
	# 舞台主甲板（Floor 4x0.5x4，顶面 y=0.5），x∈[-6,6] z∈[-4,4]
	for x in [-4.0, 0.0, 4.0]:
		for z in [-2.0, 2.0]:
			add_piece(root, "Floor", Vector3(x, 0.0, z))
	# 双层高台（Cube 2x2x2，顶面 y=2.5）——高度优势但易被针对
	add_piece(root, "Cube_Prototype_Small", Vector3(0.0, 0.5, -2.5))
	# 背景墙 + 门梁
	for x in [-4.0, 0.0, 4.0]:
		add_piece(root, "Wall", Vector3(x, 0.0, -6.0))
		add_piece(root, "Primitive_Beam", Vector3(x, 4.2, -6.0))
	# 舞台两侧立柱
	add_piece(root, "Pillar_A", Vector3(-6.3, 0.0, -5.6))
	add_piece(root, "Pillar_A", Vector3(6.3, 0.0, -5.6))
	# 两侧翼墙（框住舞台正面）
	add_piece(root, "Wall_Half", Vector3(-6.9, 0.0, 2.5), 90.0)
	add_piece(root, "Wall_Half", Vector3(6.9, 0.0, 2.5), -90.0)
	# 前景遮挡物（策划案：花篮/音响位，这里用桶/箱/桌替代；标记 occluder）
	# 小件设为 physical=true → 可推/可抓/可撞飞的可动物
	add_piece(root, "Barrel_A", Vector3(-4.2, 0.5, 6.5), 0.0, Vector3.ONE, true, true, true)
	add_piece(root, "Barrel_A", Vector3(4.2, 0.5, 6.5), 0.0, Vector3.ONE, true, true, true)
	add_piece(root, "Box_A", Vector3(4.2, 1.3, 6.5), 0.0, Vector3.ONE, true, true, true)
	add_piece(root, "Pallet_Small", Vector3(1.9, 0.0, 7.2), 0.0, Vector3.ONE, true, true, true)
	add_piece(root, "table_medium", Vector3(-1.9, 0.0, 7.4), 0.0, Vector3.ONE, true, true, true)

func _build_collision(inst: Node3D) -> void:
	for node in _collect_meshes(inst):
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var shape: Shape3D = mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Col"
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)

func _collect_meshes(root: Node) -> Array:
	var result: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			result.append(n)
		for c in n.get_children():
			stack.append(c)
	return result

func _add_to_group_recursive(root: Node, group: StringName) -> void:
	root.add_to_group(group)
	for c in root.get_children():
		_add_to_group_recursive(c, group)
