## 道具箱（Cube 占位）
## - "pickup_items" group 复用 PlayerController 现有拾取接口
## - StaticBody3D 子节点提供物理碰撞（玩家可撞飞）

class_name ItemBox
extends Area3D

## 由 ItemSpawner 在生成后赋值
var item_id: String = ""

func _ready() -> void:
	_build_visuals()
	add_to_group("item_boxes")
	add_to_group("pickup_items")

## 被 PlayerController._pickup_item_id() 调用，返回道具 id 并消除自身
func pickup_for(_player: PlayerController) -> String:
	if item_id.is_empty():
		queue_free()
		return ""
	var id := item_id
	queue_free()
	return id

func _build_visuals() -> void:
	# 物理碰撞体（StaticBody3D，layer=1 让玩家撞上去）
	var static_body := StaticBody3D.new()
	static_body.collision_layer = 1
	static_body.collision_mask  = 0
	var phys_shape := CollisionShape3D.new()
	var phys_box := BoxShape3D.new()
	phys_box.size = Vector3(0.5, 0.5, 0.5)
	phys_shape.shape = phys_box
	static_body.add_child(phys_shape)
	add_child(static_body)

	# 视觉 Mesh（黄色旋转 Cube）
	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.5, 0.5, 0.5)
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.1) * 0.4
	mesh_inst.material_override = mat
	mesh_inst.name = "Mesh"
	add_child(mesh_inst)

func _process(delta: float) -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.rotate_y(delta * 1.5)
