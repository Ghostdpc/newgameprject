## 职责：服装系统入口（autoload）
## - 加载 GarmentConfig
## - equip_garment / unequip_garment：穿脱服装 + 效果触发
## - get_equipped_score：返回玩家服装得分（0~1，供 ScoreAnalyzer）
## - battle_ended 时自动清空所有玩家服装

extends Node

var _garment_config: GarmentConfig

## player_instance_id -> { slot_name -> { "def": GarmentDef, "ctx": ItemContext } }
var _equipped: Dictionary = {}

func _ready() -> void:
	_garment_config = GarmentConfig.new()
	_garment_config.load()
	EventBus.battle_ended.connect(_on_battle_ended)

## 检查 id 是否属于服装
func is_garment(id: String) -> bool:
	if _garment_config == null:
		return false
	return _garment_config.get_garment(id) != null

## 给玩家装备服装（自动卸下同槽旧件）
func equip_garment(player: PlayerController, garment_id: String) -> void:
	# 暂时屏蔽衣服装备处理（结算问题排查中）
	return

	var def := _garment_config.get_garment(garment_id)
	if def == null:
		push_warning("GarmentSystem: unknown garment_id '%s'" % garment_id)
		return

	# 卸下同槽旧件
	_unequip_slot(player, def.slot)

	# 挂载外观
	if player.outfit_manager:
		if def.model.is_empty():
			# 占位：直接用空 PackedScene 跳过（OutfitManager.equip 需要 PackedScene）
			# 服装无模型时只触发效果，不挂载视觉节点
			pass
		else:
			var scene := load(def.model) as PackedScene
			if scene:
				player.outfit_manager.equip(def.slot, scene, garment_id)

	# 应用效果
	var ctx := ItemContext.new()
	ctx.source_player = player
	ctx.item_id = garment_id
	for effect in def.effects:
		effect.apply(ctx)

	# 记录装备状态
	var pid := player.get_instance_id()
	if not _equipped.has(pid):
		_equipped[pid] = {}
	_equipped[pid][def.slot] = { "def": def, "ctx": ctx }

	# 更新 PlayerController 装备记录（供评分读取）
	player.equipped_garments[def.slot] = garment_id

	# 通知 EventBus（HUD / PickupBubbles 监听）
	var slot_int := _slot_to_int(def.slot)
	EventBus.outfit_changed.emit(player.player_index, slot_int, garment_id)

## 计算玩家服装得分（0~1），供 ScoreAnalyzer 的 outfit 字段
func get_equipped_score(player: PlayerController) -> float:
	var score := 0.0
	var pid := player.get_instance_id()
	if not _equipped.has(pid):
		return 0.0
	for slot_data in _equipped[pid].values():
		var def: GarmentDef = slot_data.get("def")
		if def:
			score += def.score_bonus
	return clampf(score, 0.0, 1.0)

## 战斗结束时清空所有玩家服装效果
func _on_battle_ended() -> void:
	for pid in _equipped.keys():
		var slot_map: Dictionary = _equipped[pid]
		for slot_data in slot_map.values():
			var def: GarmentDef = slot_data.get("def")
			var ctx: ItemContext = slot_data.get("ctx")
			if def and ctx:
				for effect in def.effects:
					effect.revert(ctx)
		# 清 PlayerController 记录（找玩家节点）
		var player := _find_player_by_instance_id(pid)
		if player:
			player.equipped_garments.clear()
			if player.outfit_manager:
				player.outfit_manager.clear_all()
	_equipped.clear()

## 卸下指定槽位（内部用）
func _unequip_slot(player: PlayerController, slot_name: String) -> void:
	var pid := player.get_instance_id()
	if not _equipped.has(pid):
		return
	var slot_map: Dictionary = _equipped[pid]
	if not slot_map.has(slot_name):
		return
	var slot_data: Dictionary = slot_map[slot_name]
	var def: GarmentDef = slot_data.get("def")
	var ctx: ItemContext = slot_data.get("ctx")
	if def and ctx:
		for effect in def.effects:
			effect.revert(ctx)
	slot_map.erase(slot_name)
	player.equipped_garments.erase(slot_name)
	if player.outfit_manager:
		player.outfit_manager.unequip(slot_name)

func _slot_to_int(slot_name: String) -> int:
	match slot_name:
		"hat_slot":       return 0
		"shirt_slot":     return 1
		"accessory_slot": return 2
	return 0

func _find_player_by_instance_id(pid: int) -> PlayerController:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("players"):
		if node.get_instance_id() == pid:
			return node as PlayerController
	return null
