## 職責：角色換裝管理。在骨架骨槽（BoneAttachment3D）上掛載/卸載裝備物。
## 無骨架時退化成普通 Node3D 槽位，仍可換裝（如占位膠囊）。

class_name OutfitManager
extends Node

signal item_equipped(slot_name: String, item: Node3D)
signal item_unequipped(slot_name: String)

## 槽位名 -> 目標骨骼（KayKit Mannequin 命名，缺骨時自動退化成普通槽位）
const SLOT_BONES: Dictionary = {
	"hat_slot": "head",
	"shirt_slot": "chest",
	"accessory_slot": "upperarm.r",
}

@export var character_root: Node3D
@export var skeleton: Skeleton3D

var player_color: Color = Color.WHITE:
	set(value):
		player_color = value
		_recolor_all()

var _slots: Dictionary = {}
var _items: Dictionary = {}
## 槽位名 -> 装备 id（结算评分读单件加成用；未传 id 则空串）
var _item_ids: Dictionary = {}

func _ready() -> void:
	if not character_root:
		character_root = get_parent() as Node3D
	if not skeleton and character_root:
		skeleton = character_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_build_slots()

func _build_slots() -> void:
	for slot_name in SLOT_BONES:
		_create_slot(slot_name)

func _create_slot(slot_name: String) -> void:
	var bone_name: String = SLOT_BONES[slot_name]
	var slot: Node3D
	if skeleton and skeleton.find_bone(bone_name) != -1:
		var attachment := BoneAttachment3D.new()
		attachment.name = slot_name
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
		slot = attachment
	else:
		slot = Node3D.new()
		slot.name = slot_name
		add_child(slot)
	_slots[slot_name] = slot

## 裝備物品到指定槽位（同槽位先卸載舊物）
func equip(slot_name: String, item_scene: PackedScene, item_id: String = "") -> Node3D:
	if not _slots.has(slot_name):
		push_error("OutfitManager: 無此槽位 '%s'" % slot_name)
		return null
	unequip(slot_name)
	var item: Node3D = item_scene.instantiate()
	item.name = "Item"
	_slots[slot_name].add_child(item)
	_items[slot_name] = item
	_item_ids[slot_name] = item_id
	_recolor(item)
	item_equipped.emit(slot_name, item)
	return item

func unequip(slot_name: String) -> void:
	if not _items.has(slot_name):
		return
	var item: Node3D = _items[slot_name]
	_items.erase(slot_name)
	_item_ids.erase(slot_name)
	item.queue_free()
	item_unequipped.emit(slot_name)

func get_item(slot_name: String) -> Node3D:
	return _items.get(slot_name, null)

## 当前已装备槽位数量（结算评分用）
func equipped_slot_count() -> int:
	return _items.size()

## 槽位名 -> 装备 id 的副本（结算评分读单件加成用）
func get_equipped_ids() -> Dictionary:
	return _item_ids.duplicate()

func clear_all() -> void:
	for slot_name in _items.keys():
		unequip(slot_name)

func _recolor_all() -> void:
	for item in _items.values():
		_recolor(item)

func _recolor(item: Node3D) -> void:
	for child in item.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var mat: Material
		var src: Material = mesh.get_active_material(0)
		if src:
			mat = src.duplicate()
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = player_color
		else:
			mat = StandardMaterial3D.new()
			(mat as StandardMaterial3D).albedo_color = player_color
		mesh.material_override = mat
