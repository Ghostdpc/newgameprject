## 职责：服装拾取实体 —— 从天而降落地，长按即可装备
## 复用 PlayerController 的 pickup_items 拾取接口（与 ItemBox 相同组）

class_name GarmentPickup
extends Area3D

## 由 GarmentSpawner 在生成后赋值
var garment_id: String = ""

## 落地动画参数
const DROP_HEIGHT: float    = 3.5   # 生成点相对热点的额外高度（米）
const DROP_DURATION: float  = 0.45  # 下落时长（秒）
const BOUNCE_HEIGHT: float  = 0.3   # 弹跳高度（米）
const BOUNCE_DURATION: float = 0.15 # 弹跳时长（秒）

var _landed: bool = false

func _ready() -> void:
	monitoring = false  # 落地前关闭，防误触
	monitorable = true
	add_to_group("garment_pickups")
	add_to_group("pickup_items")
	_build_visuals()
	call_deferred("_start_drop")

## 被 PlayerController._pickup_item_id() 调用，返回 garment_id 并销毁自身
func pickup_for(_player: PlayerController) -> String:
	if garment_id.is_empty() or not _landed:
		return ""
	var id := garment_id
	queue_free()
	return id

func _build_visuals() -> void:
	# 触发区域碰撞形状（小球，玩家靠近即可拾取）
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	col.shape = sphere
	add_child(col)

	# 占位 mesh（品红色旋转方块，待美术替换）
	call_deferred("_build_model")

	# 悬浮名称标签
	var label := Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0.0, 0.7, 0.0)
	label.layers = 4
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 32
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.text = garment_id
	add_child(label)
	call_deferred("_refresh_label")

func _build_model() -> void:
	var visual: Node3D = null
	if GarmentSystem and GarmentSystem._garment_config:
		var def := GarmentSystem._garment_config.get_garment(garment_id)
		if def and not def.model.is_empty():
			visual = PropModelBuilder.build(def.model, def.texture, 0.5, def.model_scale)
	if visual == null:
		visual = _make_placeholder_mesh()
	visual.name = "Mesh"
	add_child(visual)

func _make_placeholder_mesh() -> Node3D:
	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.5, 0.5, 0.5)
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2) * 0.4
	mesh_inst.material_override = mat
	return mesh_inst

func _refresh_label() -> void:
	var label := get_node_or_null("NameLabel") as Label3D
	if label == null:
		return
	if GarmentSystem and GarmentSystem._garment_config:
		var def := GarmentSystem._garment_config.get_garment(garment_id)
		if def:
			label.text = def.display_name

## 从高处下落 → 弹跳落地
func _start_drop() -> void:
	var landing_y := global_position.y  # 最终落地 y（生成时已在热点 y）
	global_position.y += DROP_HEIGHT    # 先升到天上

	var tw := create_tween()
	# 第一段：ease_in 下落
	tw.tween_property(self, "position:y", landing_y, DROP_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 第二段：上弹
	tw.tween_property(self, "position:y", landing_y + BOUNCE_HEIGHT, BOUNCE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 第三段：落定
	tw.tween_property(self, "position:y", landing_y, BOUNCE_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_on_landed)

func _on_landed() -> void:
	_landed = true
	monitoring = true  # 落地后才可拾取

func _process(delta: float) -> void:
	if not _landed:
		return
	var mesh := get_node_or_null("Mesh") as Node3D
	if mesh:
		mesh.rotate_y(delta * 1.5)
