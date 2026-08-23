## 驗證：正式 player.tscn(newnewhuman) 生成後自動把表情貼到臉片(surf[1])
extends GutTest

func test_player_auto_face_texture() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(4)
	assert_not_null(player.face, "有 face")
	# setup 時應已自動開啟貼臉
	assert_true(player.face.use_head_texture, "use_head_texture 自動開啟")
	assert_true(player.face._head_mi != null, "臉片 mesh 已找(自動貼臉)")
	print("surf=", player.face._head_surf)
	# 表情切換也走臉片材質
	player.face.show_expression(3)
	var ce := player.character_effects
	assert_true(ce != null, "有 CharacterEffects")
	if ce and player.face._head_mi:
		var mid := player.face._head_mi.get_instance_id()
		assert_true(ce.face_textures.has(mid), "切換後仍記錄表情紋理")
