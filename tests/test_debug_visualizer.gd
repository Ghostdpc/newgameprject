## 职责：验证 DebugVisualizer 热键切换

extends GutTest

func test_toggle_collisions_flips_state() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	vis._collisions_on = false
	vis._toggle_collisions()
	assert_true(vis._collisions_on, "F1 应切换碰撞显示")
	vis._toggle_collisions()
	assert_false(vis._collisions_on)

func test_toggle_bones_flips_state() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	vis._bones_on = false
	vis._toggle_bones()
	assert_true(vis._bones_on, "F2 应切换骨骼线")
	assert_true(vis._bone_mesh.visible, "骨骼网格应可见")
	vis._toggle_bones()
	assert_false(vis._bones_on)
	assert_false(vis._bone_mesh.visible)

func test_toggle_data_panel_flips_state() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	assert_false(vis._data_panel_on, "初始应为关闭")
	vis._toggle_data_panel()
	assert_true(vis._data_panel_on, "F3 应开启数据面板")
	assert_true(vis._overlay.visible, "overlay 应可见")
	vis._toggle_data_panel()
	assert_false(vis._data_panel_on)
	assert_false(vis._overlay.visible)

func test_data_panel_overlay_exists() -> void:
	var vis := DebugVisualizer.new()
	add_child_autofree(vis)
	assert_not_null(vis._overlay, "overlay CanvasLayer 应已构建")
	assert_not_null(vis._panel_root, "panel_root 应已构建")
