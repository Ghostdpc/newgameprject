## 职责：结算接入组合测试 —— 直接调 SettlementSystem._analyze 验证四维评分链
## 不依赖真实渲染：合成掩码（使用 ID 纯色）+ mock 演员/服装

extends GutTest

const SETTLE := preload("res://scripts/systems/settlement_system.gd")

const SIZE := Vector2i(16, 16)

## P0=纯红 P1=纯绿（与 score_config id_colors 一致）
const ID_RED    := Color(1.0, 0.0, 0.0)
const ID_GREEN  := Color(0.0, 1.0, 0.0)

class MockActor extends Node3D:
	var player_index: int = 0
	var player_color: Color = Color.WHITE

class MockOutfit extends Node:
	var equipped: int = 0
	var ids: Dictionary = {}
	func equipped_slot_count() -> int:
		return equipped
	func get_equipped_ids() -> Dictionary:
		return ids

# ---- 辅助 ----

func _harness() -> Dictionary:
	var settle = SETTLE.new()
	add_child_autofree(settle)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 10)
	add_child_autofree(cam)
	return {"settle": settle, "cam": cam}

func _make_actor(index: int, pos: Vector3, outfit: MockOutfit = null) -> MockActor:
	var a := MockActor.new()
	a.player_index = index
	a.player_color = Color.WHITE
	a.position = pos
	if outfit:
		outfit.name = "OutfitManager"
		a.add_child(outfit)
	add_child_autofree(a)
	return a

func _blank_mask() -> Image:
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	return img

func _fill_rect(img: Image, color: Color, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			img.set_pixel(x, y, color)

func _actor(results: Dictionary, index: int) -> Dictionary:
	for a in results["actors"]:
		if int(a["player_index"]) == index:
			return a
	return {}

# ---- 四维齐全 ----

func test_results_contain_four_dimensions() -> void:
	var h := _harness()
	var settle = h["settle"]
	var img := _blank_mask()
	_fill_rect(img, ID_RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var actors: Array = [_make_actor(0, Vector3.ZERO)]
	var results: Dictionary = settle._analyze(img, img, h["cam"], actors)
	var a := _actor(results, 0)
	assert_true(a.has("ratio") and a.has("center") and a.has("outfit") and a.has("facing"),
		"结算结果应含四维")
	assert_true(a["dimensions"].has("ratio") and a["dimensions"].has("center")
		and a["dimensions"].has("outfit") and a["dimensions"].has("facing"),
		"dimensions 应含四维 key")

# ---- 0~100 总分 ----

func test_total_is_100_for_full_score() -> void:
	var h := _harness()
	var img := _blank_mask()
	_fill_rect(img, ID_RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var outfit := MockOutfit.new()
	outfit.equipped = 3
	outfit.ids = {"hat_slot": "outfit_cap"}
	var actors: Array = [_make_actor(0, Vector3.ZERO, outfit)]
	var results: Dictionary = h["settle"]._analyze(img, img, h["cam"], actors)
	var a := _actor(results, 0)
	assert_eq(a["total"], 100.0, "四维满分应为 100")

# ---- 排名 ----

func test_rank_descending_by_total() -> void:
	var h := _harness()
	var img := _blank_mask()
	# P0(红)中心 6x6；P1(绿)角落 6x6，像素数相同，P0 C位更高
	_fill_rect(img, ID_RED,   Rect2i(5, 5, 6, 6))
	_fill_rect(img, ID_GREEN, Rect2i(0, 0, 6, 6))
	var actors: Array = [
		_make_actor(0, Vector3.ZERO),
		_make_actor(1, Vector3(5, 0, 0)),
	]
	var results: Dictionary = h["settle"]._analyze(img, img, h["cam"], actors)
	var r0 := _actor(results, 0)
	var r1 := _actor(results, 1)
	assert_gt(r0["total"], r1["total"], "中心演员总分应高于角落演员")
	assert_eq(r0["rank"], 1)
	assert_eq(r1["rank"], 2)

# ---- 服装读取 ----

func test_outfit_reads_equipped_slots() -> void:
	var h := _harness()
	var img := _blank_mask()
	_fill_rect(img, ID_RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var outfit := MockOutfit.new()
	outfit.equipped = 2
	outfit.ids = {"hat_slot": "outfit_cap"}
	var actors: Array = [_make_actor(0, Vector3.ZERO, outfit)]
	var results: Dictionary = h["settle"]._analyze(img, img, h["cam"], actors)
	var a := _actor(results, 0)
	assert_gt(a["outfit"], 0.5, "2 槽 + 加成应大于 0.5")

func test_outfit_zero_without_manager() -> void:
	var h := _harness()
	var img := _blank_mask()
	_fill_rect(img, ID_RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var actors: Array = [_make_actor(0, Vector3.ZERO)]
	var results: Dictionary = h["settle"]._analyze(img, img, h["cam"], actors)
	var a := _actor(results, 0)
	assert_eq(a["outfit"], 0.0, "无 OutfitManager 时服装应为 0")

# ---- 朝向读取 ----

func test_facing_reads_actor_forward() -> void:
	var h := _harness()
	var img := _blank_mask()
	var actors: Array = [_make_actor(0, Vector3.ZERO)]
	var results: Dictionary = h["settle"]._analyze(img, img, h["cam"], actors)
	var a := _actor(results, 0)
	assert_almost_eq(a["facing"], 1.0, 0.001, "正脸朝镜头朝向应为 1")

# ---- 完全出镜 ----

func test_out_of_photo_zeroes_pixel_dims() -> void:
	var h := _harness()
	var img := _blank_mask()
	_fill_rect(img, ID_RED, Rect2i(0, 0, 2, 2))  # 4px < min_visible_px=20
	var actors: Array = [_make_actor(0, Vector3.ZERO)]
	var results: Dictionary = h["settle"]._analyze(img, img, h["cam"], actors)
	var a := _actor(results, 0)
	assert_false(a["in_photo"], "像素不足应判完全出镜")
	assert_eq(a["ratio"], 0.0)
	assert_eq(a["center"], 0.0)

# ---- override 还原 ----

func test_id_override_reverts_layers_and_material() -> void:
	var settle = SETTLE.new()
	add_child_autofree(settle)

	# 构造带 MeshInstance3D 的 mock 演员
	var a := MockActor.new()
	a.player_index = 0
	add_child_autofree(a)
	var mi := MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	mi.layers = 1                     # 原始：layer 1
	var orig_mat := StandardMaterial3D.new()
	mi.material_override = orig_mat   # 原始 override
	a.add_child(mi)

	var actors: Array = [a]
	var table: Array = settle._apply_id_overrides(actors)

	# 染色后：只在 MASK 层（移除原 layer 1）；override = ID 材质
	assert_eq(mi.layers, settle.MASK_LAYER_BIT, "染色后应只在 MASK 层")
	assert_ne(mi.material_override, orig_mat, "染色后应换成 ID 材质")

	settle._revert_id_overrides(table)

	# 还原后：layers 和 override 均恢复
	assert_eq(mi.layers, 1, "还原后 layers 应恢复 layer 1")
	assert_eq(mi.material_override, orig_mat, "还原后 override 应还原原值")
