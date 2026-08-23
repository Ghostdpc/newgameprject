extends GutTest

func test_human_anim_mapping() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	player.player_index = 0
	add_child_autofree(player)
	await wait_frames(4)
	print("is_human=", player.get("_is_human_model"))
	var ap: AnimationPlayer = player.get("_animation_player")
	if ap:
		print("anim list=", ap.get_animation_list())
		var anim_move: String = player._anim_for_state("Move")
		var anim_idle: String = player._anim_for_state("Idle")
		var anim_jump: String = player._anim_for_state("Jump")
		var anim_dive: String = player._anim_for_state("Dive")
		print("Move→", anim_move, " Idle→", anim_idle, " Jump→", anim_jump, " Dive→", anim_dive)
		assert_true(anim_move.ends_with("Walk"), "移動用 Walk 動畫")
		assert_true(anim_idle.ends_with("Idle") or anim_idle.ends_with("Idle_001"), "待機用 Idle 動畫")
		assert_true(anim_jump.ends_with("jump"), "跳躍用 jump 動畫")
