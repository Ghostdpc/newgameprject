## 职责：测试 SettlementSystem 初始化（掩码视口构建 + ID 材质 + 配置加载）

extends GutTest

func test_ready_builds_mask_viewport() -> void:
	var ss = load("res://scripts/systems/settlement_system.gd").new()
	add_child_autofree(ss)
	assert_not_null(ss._mask_viewport, "掩码视口应构建")
	assert_not_null(ss._mask_camera, "掩码相机应构建")
	assert_eq(ss._mask_camera.cull_mask, ss.MASK_LAYER_BIT, "掩码相机应只渲染 MASK_LAYER")

func test_mask_viewport_has_no_independent_world() -> void:
	var ss = load("res://scripts/systems/settlement_system.gd").new()
	add_child_autofree(ss)
	assert_null(ss._mask_viewport.world_3d, "掩码视口应继承主场景 world（不设独立 world）")

func test_id_materials_built_for_four_players() -> void:
	var ss = load("res://scripts/systems/settlement_system.gd").new()
	add_child_autofree(ss)
	assert_eq(ss._id_materials.size(), 4, "应构建 4 个 ID 材质")

func test_id_material_p0_is_pure_red() -> void:
	var ss = load("res://scripts/systems/settlement_system.gd").new()
	add_child_autofree(ss)
	var mat: StandardMaterial3D = ss._id_materials[0]
	assert_almost_eq(mat.albedo_color.r, 1.0, 0.01, "P0 ID 色应为纯红 R=1")
	assert_almost_eq(mat.albedo_color.g, 0.0, 0.01, "P0 ID 色应为纯红 G=0")
	assert_almost_eq(mat.albedo_color.b, 0.0, 0.01, "P0 ID 色应为纯红 B=0")

func test_score_config_weights_loaded() -> void:
	var ss = load("res://scripts/systems/settlement_system.gd").new()
	add_child_autofree(ss)
	var weights: Dictionary = ss._score_config.get("weights", {})
	assert_almost_eq(float(weights.get("ratio",  0.0)), 0.25, 0.001, "画面比例权重应为 0.25")
	assert_almost_eq(float(weights.get("center", 0.0)), 0.25, 0.001, "C位权重应为 0.25")
	assert_almost_eq(float(weights.get("outfit", 0.0)), 0.25, 0.001, "服装权重应为 0.25")
	assert_almost_eq(float(weights.get("facing", 0.0)), 0.25, 0.001, "朝向权重应为 0.25")
