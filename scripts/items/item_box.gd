## 道具箱（临时 Cube 占位），被玩家拾取后触发 pickup_item 并消失

class_name ItemBox
extends Area3D

## 由 ItemSpawner 在生成后赋值
var item_id: String = ""

var _mesh: MeshInstance3D
var _collision: CollisionShape3D

func _ready() -> void:
	collision_layer = 0   # 道具箱自身不占物理层
	collision_mask  = 2   # 检测 layer=2（玩家层）
	_build_visuals()
	body_entered.connect(_on_body_entered)
	add_to_group("item_boxes")

func _build_visuals() -> void:
	# Cube mesh（黄色，0.5m 边长）
	_mesh = MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.5, 0.5, 0.5)
	_mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.1) * 0.4
	_mesh.material_override = mat
	add_child(_mesh)

	# 碰撞体
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	_collision.shape = shape
	add_child(_collision)

	# 缓慢旋转动画
	set_meta("_rotate", true)

func _process(delta: float) -> void:
	if _mesh:
		_mesh.rotate_y(delta * 1.5)

func _on_body_entered(body: Node3D) -> void:
	if not (body is PlayerController):
		return
	var player := body as PlayerController
	if item_id.is_empty():
		queue_free()
		return
	queue_free()
	player.pickup_item(item_id)
