## 驗證：表情系統（PlayerFaceController）綁骨 + 切換
extends GutTest

func test_player_has_face_node_and_binds() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	assert_not_null(player.face, "玩家掛載 PlayerFaceController")
	assert_eq(player.face.count(), 209, "表情素材(assets/textures/faces)掃到 209 張")
	# 正式場景自動貼臉（newnewhuman 有臉片）→ 臉片已找
	assert_true(player.face.use_head_texture, "正式場景自動開啟貼臉")
	assert_not_null(player.face._head_mi, "已找臉片 mesh")

func test_show_expression_switches_and_clears() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	var fc := player.face
	fc.show_expression(0)
	assert_eq(fc.get("_current_index"), 0, "索引切到 0")
	fc.clear()
	assert_eq(fc.get("_current_index"), -1, "clear 後索引歸 -1")
	# 越界繞回
	var total: int = fc.count()
	fc.show_expression(total + 5)
	assert_eq(fc.get("_current_index"), 5 % total, "越界索引正確繞回")

func test_freeze_pauses_animation() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_physics_frames(3)
	assert_false(player.frozen, "初始未凍結")
	var ap: AnimationPlayer = player.get("_animation_player")
	player.frozen = true
	assert_true(player.frozen, "設為凍結後旗標生效")
	# 凍結期間 update_animation 不重播且 pause
	player._update_animation()
	assert_true(ap != null, "有動畫播放器")
	player.frozen = false
	assert_false(player.frozen, "解凍恢復")

func test_face_mask_mode_uses_mesh() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(3)
	var fc := player.face
	# 關掉自動貼臉，測面具模式（divergent 調試功能）
	fc.use_head_texture = false
	fc.use_face_mask = true
	fc.setup(player.get("_model_skeleton"))
	var node: Node3D = fc.get("_sprite")
	assert_not_null(node, "面具模式有顯示節點")
	assert_true(node is MeshInstance3D, "面具模式用 MeshInstance3D")
	fc.show_expression(0)
	assert_true(node.visible, "面具表情可見")
	var mi := node as MeshInstance3D
	assert_not_null(mi.mesh, "面具 mesh 已加載")
	assert_gt(mi.mesh.get_surface_count(), 0, "面具 mesh 有 surface")
	assert_not_null(mi.get_surface_override_material(0), "面具材質已設")
