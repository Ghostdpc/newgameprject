## 驗證：表情貼到服裝（蜗牛服）流程
extends GutTest

func test_garment_attach_applies_texture() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	assert_not_null(player.outfit_manager, "有 outfit_manager")
	# 穿蜗牛服
	GarmentSystem.equip_garment(player, "snail_hoodie")
	await wait_frames(1)
	var item := player.outfit_manager.get_item("shirt_slot")
	assert_not_null(item, "蜗牛服已穿到 shirt_slot")
	print("shirt item=", item, " children=", item.get_child_count())
	# 找 mesh
	var host := player.face
	host.attach_to_garment = true
	var ok: bool = host.apply_garment_attach()
	print("apply ok=", ok, " host=", host._garment_host)
	assert_true(ok, "attach 成功")
	if host._garment_host:
		var m := host._garment_host
		assert_not_null(m.get_surface_override_material(0), "材質 override 已設")
		var mat := m.get_surface_override_material(0) as StandardMaterial3D
		assert_not_null(mat.albedo_texture, "材質有表情貼圖")
		print("mat tex=", mat.albedo_texture)
