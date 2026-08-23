## 道具箱（Cube 占位）
## - "pickup_items" group 复用 PlayerController 现有拾取接口
## - StaticBody3D 子节点提供物理碰撞（玩家可撞飞）
## - Label3D 显示道具名
## - 生成时从天而降（Tween 落地动画）

class_name ItemBox
extends Area3D

const DROP_HEIGHT: float    = 3.5
const DROP_DURATION: float  = 0.45
const BOUNCE_HEIGHT: float  = 0.3
const BOUNCE_DURATION: float = 0.15

## 由 ItemSpawner 在生成后赋值
var item_id: String = ""
var _landed: bool = false

func _ready() -> void:
	_build_visuals()
	add_to_group("item_boxes")
	add_to_group("pickup_items")
	call_deferred("_start_drop")

## 被 PlayerController 拾取，返回道具 id 并消除自身
func pickup_for(_player: PlayerController) -> String:
	if item_id.is_empty() or not _landed:
		queue_free()
		return ""
	var id := item_id
	queue_free()
	return id

func _start_drop() -> void:
	var landing_y := global_position.y
	global_position.y += DROP_HEIGHT

	var tw := create_tween()
	tw.tween_property(self, "position:y", landing_y, DROP_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position:y", landing_y + BOUNCE_HEIGHT, BOUNCE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position:y", landing_y, BOUNCE_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): _landed = true)

func _build_visuals() -> void:
	# 物理碰撞体：原来 layer=1 让玩家/飞扑撞上去（阻挡）。现改到 layer=8
	# （不在玩家 collision_mask=1+2+4 内）→ 玩家可穿过，不阻挡移动/飞扑。
	var static_body := StaticBody3D.new()
	static_body.collision_layer = 8
	static_body.collision_mask  = 0
	var phys_shape := CollisionShape3D.new()
	var phys_box := BoxShape3D.new()
	phys_box.size = Vector3(0.5, 0.5, 0.5)
	phys_shape.shape = phys_box
	static_body.add_child(phys_shape)
	add_child(static_body)

	# 道具名 Label3D（悬浮在箱子上方，layer 3 = UI 标识，不进拍照 RT）
	var label := Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0.0, 0.7, 0.0)
	label.layers = 4
	# 栅格化 3 倍分辨率再缩小显示，文字更清晰（世界尺寸保持不变）
	label.pixel_size = 0.0016667
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.outline_size = 24
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.text = item_id  # 先用 id 占位，_ready 后在 _refresh_label 中更新
	add_child(label)
	# 延迟一帧更新，确保 item_id 已由 ItemSpawner 赋值
	call_deferred("_refresh_label")
	call_deferred("_build_model")

## 依道具配置构建 3D 模型，失败回退黄色旋转方块（视觉命名统一为 "Mesh"）
func _build_model() -> void:
	var visual: Node3D = null
	if ItemSystem and ItemSystem._item_config:
		var def := ItemSystem._item_config.get_item(item_id)
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
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.1) * 0.4
	mesh_inst.material_override = mat
	return mesh_inst

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
	var mesh := get_node_or_null("Mesh") as Node3D
	if mesh:
		mesh.rotate_y(delta * 1.5)
