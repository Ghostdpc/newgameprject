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

func test_toggle_data_panel_flips_state() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	assert_false(vis._data_panel_on, "初始應為關閉")
	vis._toggle_data_panel()
	assert_true(vis._data_panel_on, "F3 應開啟數據面板")
	assert_true(vis._overlay.visible, "overlay 應可見")
	vis._toggle_data_panel()
	assert_false(vis._data_panel_on)
	assert_false(vis._overlay.visible)

func test_data_panel_overlay_exists() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	assert_not_null(vis._overlay, "overlay CanvasLayer 應已構建")
	assert_not_null(vis._panel_root, "panel_root 應已構建")
