## 验证：服装系统 core — 配置读取、装备、效果、评分、还原
extends GutTest

func test_config_reads_garments() -> void:
	var def := GarmentSystem._garment_config.get_garment("mushroom_hat")
	assert_not_null(def, "蘑菇帽定义存在")
	assert_eq(def.slot, "hat_slot", "蘑菇帽在头槽")
	assert_gt(def.score_bonus, 0.0, "蘑菇帽有评分加成")
	var ids: Array[String] = GarmentSystem._garment_config.all_ids()
	assert_eq(ids.size(), 6, "garments.json 定义 6 件服装")

func test_equip_garment_applies_effect_and_score_and_revert() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	assert_not_null(player.outfit_manager, "玩家有 OutfitManager")

	# 蘑菇帽：放大头部
	GarmentSystem.equip_garment(player, "mushroom_hat")
	assert_almost_eq(player.head_scale, 1.8, 0.001, "蘑菇帽应放大头部 head_scale=1.8")
	var score_hat: float = GarmentSystem.get_equipped_score(player)
	assert_gt(score_hat, 0.0, "装备后 outfit 分 > 0")

	# 同槽替换：充气球衣 → 身宽
	GarmentSystem.equip_garment(player, "inflate_shirt")
	assert_eq(player.body_width, 1.5, "充气球衣应加宽 body_width=1.5")
	assert_almost_eq(player.body_scale, 1.5, 0.001, "充气球衣应放大 body_scale=1.5")

	# 移速类服装：蜗牛连帽衫 → 减速
	GarmentSystem.equip_garment(player, "snail_hoodie")
	assert_almost_eq(player.speed_multiplier, 0.6, 0.001, "蜗牛连帽衫应减速移速 x0.6")

	# 结束混战还原所有效果
	EventBus.battle_ended.emit()
	assert_almost_eq(player.head_scale, 1.0, 0.001, "还原后头部恢复")
	assert_almost_eq(player.body_width, 1.0, 0.001, "还原后身宽恢复")
	assert_almost_eq(player.body_scale, 1.0, 0.001, "还原后身型恢复")
	assert_almost_eq(player.speed_multiplier, 1.0, 0.001, "还原后移速恢复")
	assert_eq(player.equipped_garments.size(), 0, "还原后装备清空")
