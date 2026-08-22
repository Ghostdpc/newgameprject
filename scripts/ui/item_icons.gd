## 职责：item_id / outfit_id → 图标贴图 的统一映射（demo 占位，正式由资源同事接管）

class_name ItemIcons
extends RefCounted

const ICON_DIR := "res://assets/textures/ui/"

const MAP: Dictionary = {
	# 玩家形状（白色底图，使用时按玩家颜色 modulate）
	"shape_0": "shape_circle.svg",
	"shape_1": "shape_triangle.svg",
	"shape_2": "shape_square.svg",
	"shape_3": "shape_diamond.svg",
	# 服装槽空位轮廓
	"slot_0": "slot_head.svg",
	"slot_1": "slot_body.svg",
	"slot_2": "slot_hand.svg",
	# 装饰
	"crown": "crown.svg",
	# 服装组件（9 件：槽位 0 头 / 1 身 / 2 手）
	"outfit_cap": "outfit_cap.svg",
	"outfit_tophat": "outfit_tophat.svg",
	"outfit_ribbon": "outfit_ribbon.svg",
	"outfit_jacket": "outfit_jacket.svg",
	"outfit_dress": "outfit_dress.svg",
	"outfit_mascot": "outfit_mascot.svg",
	"outfit_balloon": "outfit_balloon.svg",
	"outfit_camera": "outfit_camera.svg",
	"outfit_wand": "outfit_wand.svg",
	# 道具
	"item_fastforward": "item_fastforward.svg",
	"item_slowmo": "item_slowmo.svg",
	"item_battery": "item_battery.svg",
	"item_scissors": "item_scissors.svg",
	"item_energy": "item_energy.svg",
	"item_banana": "item_banana.svg",
	"item_remote": "item_remote.svg",
}

static var _cache: Dictionary = {}

static func load_icon(id: String) -> Texture2D:
	if id == "":
		return null
	if _cache.has(id):
		return _cache[id]
	var file_name: String = MAP.get(id, "")
	if file_name == "":
		return null
	var path := ICON_DIR + file_name
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex:
		_cache[id] = tex
	return tex

static func shape_icon(player_index: int) -> Texture2D:
	return load_icon("shape_%d" % (player_index % 4))

static func slot_icon(slot: int) -> Texture2D:
	return load_icon("slot_%d" % slot)
