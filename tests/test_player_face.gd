## 驗證：表情系統（PlayerFaceController）綁骨 + 切換
extends GutTest

func test_player_has_face_node_and_binds() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	assert_not_null(player.face, "玩家掛載 PlayerFaceController")
	assert_eq(player.face.count(), 209, "表情素材(assets/textures/faces)掃到 209 張")
	# human 綁定 head 骨（HumanBoneMap 解析）→ 貼皮非 fallback
	assert_false(player.face.get("_used_fallback"), "應綁定 head 骨（貼皮），非 fallback")
	var sprite: Sprite3D = player.face.get("_sprite")
	assert_not_null(sprite, "已建立表情 Sprite3D")
	assert_false(sprite.visible, "初始隱藏")

func test_show_expression_switches_and_clears() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	var fc := player.face
	fc.show_expression(0)
	assert_true(fc.get("_sprite").visible, "show_expression 後表情可見")
	assert_eq(fc.get("_current_index"), 0, "索引切到 0")
	fc.clear()
	assert_false(fc.get("_sprite").visible, "clear 後隱藏")
	assert_eq(fc.get("_current_index"), -1, "clear 後索引歸 -1")
	# 越界繞回
	var total: int = fc.count()
	fc.show_expression(total + 5)
	assert_eq(fc.get("_current_index"), 5 % total, "越界索引正確繞回")
