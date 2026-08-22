## 驗證：服裝系統 core — 配置讀取、裝備、效果、評分、還原
extends GutTest

func test_config_reads_garments() -> void:
	var def := GarmentSystem._garment_config.get_garment("mushroom_hat")
	assert_not_null(def, "蘑菇帽定義存在")
	assert_eq(def.slot, "hat_slot", "蘑菇帽在頭槽")
	assert_gt(def.score_bonus, 0.0, "蘑菇帽有評分加成")
	var ids: Array[String] = GarmentSystem._garment_config.all_ids()
	assert_eq(ids.size(), 6, "garments.json 定義 6 件服裝")

func test_equip_garment_applies_effect_and_score_and_revert() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	assert_not_null(player.outfit_manager, "玩家有 OutfitManager")

	# 蘑菇帽：放大頭部
	GarmentSystem.equip_garment(player, "mushroom_hat")
	assert_almost_eq(player.head_scale, 1.8, 0.001, "蘑菇帽應放大頭部 head_scale=1.8")
	var score_hat: float = GarmentSystem.get_equipped_score(player)
	assert_gt(score_hat, 0.0, "裝備後 outfit 分 > 0")

	# 同槽替換：充氣球衣 → 身寬
	GarmentSystem.equip_garment(player, "inflate_shirt")
	assert_eq(player.body_width, 1.5, "充氣球衣應加寬 body_width=1.5")
	assert_almost_eq(player.body_scale, 1.5, 0.001, "充氣球衣應放大 body_scale=1.5")

	# 移速類服裝：蝸牛連帽衫 → 減速
	GarmentSystem.equip_garment(player, "snail_hoodie")
	assert_almost_eq(player.speed_multiplier, 0.6, 0.001, "蝸牛連帽衫應減速移速 x0.6")

	# 結束混戰還原所有效果
	EventBus.battle_ended.emit()
	assert_almost_eq(player.head_scale, 1.0, 0.001, "還原後頭部恢復")
	assert_almost_eq(player.body_width, 1.0, 0.001, "還原後身寬恢復")
	assert_almost_eq(player.body_scale, 1.0, 0.001, "還原後身型恢復")
	assert_almost_eq(player.speed_multiplier, 1.0, 0.001, "還原後移速恢復")
	assert_eq(player.equipped_garments.size(), 0, "還原後裝備清空")
