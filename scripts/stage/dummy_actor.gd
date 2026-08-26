## 职责：测试用静态演员（假人），参与结算评分与遮罩
## 属性名与 PlayerController 对齐（player_index / player_color），结算系统统一处理
## TODO：正式版由真人玩家取代，或改为 AI 假人

class_name DummyActor
extends Node3D

const DUMMY_SCENE_PATH := "res://assets/models/prototype_bits/Assets/gltf/Dummy_Base.gltf"

@export var player_index: int = 1
@export var player_color: Color = Color.BLUE
## 模型朝向修正：若假人背对镜头，设为 180
@export var yaw_degrees: float = 0.0

func _ready() -> void:
	add_to_group("settlement_actor")
	add_to_group("photo_occluder")
	rotation_degrees.y = yaw_degrees
	var ps: PackedScene = load(DUMMY_SCENE_PATH)
	if ps == null:
		push_warning("DummyActor: Dummy_Base 载入失败")
		return
	var model := ps.instantiate() as Node3D
	model.name = "DummyModel"
	add_child(model)
	_apply_tint(model)

func _apply_tint(model: Node3D) -> void:
	var tint := StandardMaterial3D.new()
	tint.albedo_color = player_color
	for node in _collect_meshes(model):
		(node as MeshInstance3D).material_override = tint

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
