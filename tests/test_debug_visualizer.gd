## 職責：驗證 DebugVisualizer 熱鍵切換

extends GutTest

func test_toggle_collisions_flips_state() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	vis._collisions_on = false
	vis._toggle_collisions()
	assert_true(vis._collisions_on, "F1 應切換碰撞顯示")
	vis._toggle_collisions()
	assert_false(vis._collisions_on)

func test_toggle_bones_flips_state() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	vis._bones_on = false
	vis._toggle_bones()
	assert_true(vis._bones_on, "F2 應切換骨骼線")
	assert_true(vis._bone_mesh.visible, "骨骼網格應可見")
	vis._toggle_bones()
	assert_false(vis._bones_on)
	assert_false(vis._bone_mesh.visible)
