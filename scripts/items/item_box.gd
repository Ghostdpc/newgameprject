## 道具箱（Cube 占位）
## - "pickup_items" group 复用 PlayerController 现有拾取接口
## - StaticBody3D 子节点提供物理碰撞（玩家可撞飞）
## - Label3D 显示道具名

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

	# 道具名 Label3D（悬浮在箱子上方）
	var label := Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0.0, 0.7, 0.0)
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 32
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.text = item_id  # 先用 id 占位，_ready 后在 _refresh_label 中更新
	add_child(label)
	# 延迟一帧更新，确保 item_id 已由 ItemSpawner 赋值
	call_deferred("_refresh_label")

func _refresh_label() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label == null:
		return
	var display := item_id
	if ItemSystem and ItemSystem._item_config:
		var def := ItemSystem._item_config.get_item(item_id)
		if def:
			display = def.display_name
	label.text = display

func _process(delta: float) -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		mesh.rotate_y(delta * 1.5)
