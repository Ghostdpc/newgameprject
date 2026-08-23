extends GutTest

func test_face_demo_p1_state() -> void:
	var scene := load("res://scenes/tech_demos/face_demo.tscn") as PackedScene
	var inst: Node = scene.instantiate()
	add_child_autofree(inst)
	await wait_frames(4)
	var p1: Node = inst.get_node_or_null("PlayerP1")
	var p2: Node = inst.get_node_or_null("PlayerP2")
	var sp: Node3D = p1.get("face").get("_sprite")
	var spv := sp.visible if sp else false
	print("P1 face use_head_texture=", p1.get("face").use_head_texture,
		" _head_mi=", p1.get("face")._head_mi,
		" sprite_visible=", spv)
	print("P2 face use_head_texture=", p2.get("face").use_head_texture,
		" _head_mi=", p2.get("face")._head_mi)
