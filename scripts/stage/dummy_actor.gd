## 職責：測試用靜態演員（假人），參與結算評分與遮罩
## 屬性名與 PlayerController 對齊（player_index / player_color），結算系統統一處理
## TODO：正式版由真人玩家取代，或改為 AI 假人

class_name DummyActor
extends Node3D

const DUMMY_SCENE_PATH := "res://assets/models/prototype_bits/Assets/gltf/Dummy_Base.gltf"

@export var player_index: int = 1
@export var player_color: Color = Color.BLUE
## 模型朝向修正：若假人背對鏡頭，設為 180
@export var yaw_degrees: float = 0.0

func _ready() -> void:
	add_to_group("settlement_actor")
	add_to_group("photo_occluder")
	rotation_degrees.y = yaw_degrees
	var ps: PackedScene = load(DUMMY_SCENE_PATH)
	if ps == null:
		push_warning("DummyActor: Dummy_Base 載入失敗")
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
