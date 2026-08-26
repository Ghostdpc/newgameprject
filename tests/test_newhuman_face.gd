## 验证：正式 player.tscn(newnewhuman) 生成后自动把表情贴到脸片(surf[1])
extends GutTest

func test_player_auto_face_texture() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(4)
	assert_not_null(player.face, "有 face")
	# setup 时应已自动开启贴脸
	assert_true(player.face.use_head_texture, "use_head_texture 自动开启")
	assert_true(player.face._head_mi != null, "脸片 mesh 已找(自动贴脸)")
	print("surf=", player.face._head_surf)
	# 表情切换也走脸片材质
	player.face.show_expression(3)
	var ce := player.character_effects
	assert_true(ce != null, "有 CharacterEffects")
	if ce and player.face._head_mi:
		var mid := player.face._head_mi.get_instance_id()
		assert_true(ce.face_textures.has(mid), "切换后仍记录表情纹理")
