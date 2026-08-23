## 職責：角色換裝管理。在骨架骨槽（BoneAttachment3D）上掛載/卸載裝備物。
## 無骨架時退化成普通 Node3D 槽位，仍可換裝（如占位膠囊）。

class_name OutfitManager
extends Node

const HumanBoneMap = preload("res://scripts/player/human_bone_map.gd")

signal item_equipped(slot_name: String, item: Node3D)
signal item_unequipped(slot_name: String)

## 槽位名 -> 目標骨骼（KayKit Mannequin 命名，缺骨時自動退化成普通槽位；
## Human 骨架經 HumanBoneMap 解析到無語義編號骨）
const SLOT_BONES: Dictionary = {
	"hat_slot": "head",
	"shirt_slot": "chest",
	"accessory_slot": "upperarm.r",
}

## 槽位掛點偏移（米）：human 骨架骨槽位置可能偏高，用偏移把裝備物拉回正確觀感位置。
## 例如 halo 掛 head 骨（human 是頭頂最尖端）會浮太高，下移到底座/頭上。
const SLOT_OFFSET: Dictionary = {
	"hat_slot": Vector3(0.0, -0.3, 0.0),
	"shirt_slot": Vector3(0.0, 0.45, 0.0),
}

var _is_human: bool = false

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
	if not skeleton and character_root:
		# fbx 导入的骨架节点名不一定是 "Skeleton3D"，按类型递归兜底查找
		skeleton = _find_skeleton_by_type(character_root)
	_detect_human()
	_build_slots()

func _find_skeleton_by_type(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton_by_type(c)
		if r:
			return r
	return null

## 偵測骨架是否為 Human（含「骨骼」無語義骨名），決定是否用映射
func _detect_human() -> void:
	_is_human = false
	if not skeleton:
		return
	for i in skeleton.get_bone_count():
		if String(skeleton.get_bone_name(i)).begins_with("骨骼"):
			_is_human = true
			return

func _build_slots() -> void:
	for slot_name in SLOT_BONES:
		_create_slot(slot_name)

func _create_slot(slot_name: String) -> void:
	var bone_name: String = SLOT_BONES[slot_name]
	var real_bone := HumanBoneMap.resolve(bone_name, _is_human)
	var slot: Node3D
	if skeleton and skeleton.find_bone(real_bone) != -1:
		var attachment := BoneAttachment3D.new()
		attachment.name = slot_name
		attachment.bone_name = real_bone
		skeleton.add_child(attachment)
		slot = attachment
	else:
		slot = Node3D.new()
		slot.name = slot_name
		add_child(slot)
	_slots[slot_name] = slot

## 裝備物品到指定槽位（同槽位先卸載舊物）
func equip(slot_name: String, item_scene: PackedScene, item_id: String = "") -> Node3D:
	unequip(slot_name)
	var item := item_scene.instantiate()
	item.name = "Item"
	return _mount(slot_name, item, item_id)

## 直接掛載已構建的 Node3D（如 PropModelBuilder 套貼圖後的節點），避免作為 scene 再實例化
func equip_garment_node(slot_name: String, node: Node3D, item_id: String = "") -> Node3D:
	unequip(slot_name)
	node.name = "Item"
	return _mount(slot_name, node, item_id)

func _mount(slot_name: String, item: Node3D, item_id: String) -> Node3D:
	if not _slots.has(slot_name):
		push_error("OutfitManager: 無此槽位 '%s'" % slot_name)
		item.free()
		return null
	_slots[slot_name].add_child(item)
	# 套用槽位掛點偏移（halo 掛 human head 骨會浮高，下移）
	if SLOT_OFFSET.has(slot_name) and _is_human:
		item.position = SLOT_OFFSET[slot_name]
	_items[slot_name] = item
	_item_ids[slot_name] = item_id
	_recolor(item)
	SoundMgr.play("equip", true)
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
		var src: Material = mesh.get_active_material(0)
		if src:
			# 有自帶材質（halo 金色等）：保留原色，不被玩家色覆蓋成純白
			continue
		# 無材質（占位件）：新建玩家色材質
		var mat := StandardMaterial3D.new()
		mat.albedo_color = player_color
		mesh.material_override = mat
