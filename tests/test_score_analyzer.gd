## 职责：测试 ScoreAnalyzer 四维评分纯算法（画面比例 / C位 / 服装 / 朝向 / 0~100 总分）

extends GutTest

const SA := preload("res://scripts/systems/score_analyzer.gd")

const SIZE := Vector2i(10, 10)

func _meta(index: int, color: Color, facing: float, outfit: float) -> Dictionary:
	return {"player_index": index, "color": color, "facing": facing, "outfit": outfit}

func _image_with_region(color: Color, rect: Rect2i) -> Image:
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			img.set_pixel(x, y, color)
	return img

# --- 画面比例 ---

func test_ratio_equals_visible_fraction() -> void:
	# 单玩家全屏 → ratio = 自身像素/全部玩家像素 = 1.0
	var img := _image_with_region(Color.RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [_meta(0, Color.RED, 0.5, 0.0)], SIZE)
	var actor: Dictionary = results["actors"][0]
	assert_almost_eq(actor["ratio"], 1.0, 0.01, "单玩家全屏时画面比例应为 1")

func test_ratio_two_equal_players() -> void:
	# 两玩家各占一半 → 各 0.5
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in SIZE.y:
		for x in SIZE.x / 2:
			img.set_pixel(x, y, Color.RED)
		for x in range(SIZE.x / 2, SIZE.x):
			img.set_pixel(x, y, Color.GREEN)
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [
		_meta(0, Color.RED, 0.5, 0.0),
		_meta(1, Color.GREEN, 0.5, 0.0),
	], SIZE)
	var r := _actor_by_index(results, 0)
	var g := _actor_by_index(results, 1)
	assert_almost_eq(r["ratio"], 0.5, 0.02, "两人均分时画面比例应接近 0.5")
	assert_almost_eq(g["ratio"], 0.5, 0.02, "两人均分时画面比例应接近 0.5")

# --- C位 ---

func test_center_scores_higher_for_center_pixels() -> void:
	# 红：中心 5x5；绿：角落 5x5，像素数相同（均 >= min_visible_px）
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in range(3, 8):
		for x in range(3, 8):
			img.set_pixel(x, y, Color.RED)
	for y in range(5):
		for x in range(5):
			img.set_pixel(x, y, Color.GREEN)
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [
		_meta(0, Color.RED, 0.5, 0.0),
		_meta(1, Color.GREEN, 0.5, 0.0),
	], SIZE)
	var red_actor: Dictionary = _actor_by_index(results, 0)
	var green_actor: Dictionary = _actor_by_index(results, 1)
	assert_gt(red_actor["center"], green_actor["center"], "中心像素 C 位应高于角落像素")

# --- 服装 / 朝向 透传 ---

func test_outfit_and_facing_passthrough() -> void:
	var img := _image_with_region(Color.RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [_meta(0, Color.RED, 1.0, 0.5)], SIZE)
	var actor: Dictionary = results["actors"][0]
	assert_almost_eq(actor["facing"], 1.0, 0.001, "朝向绝对分应透传")
	assert_almost_eq(actor["outfit"], 0.5, 0.001, "服装绝对分应透传")

# --- 0~100 总分 ---

func test_total_max_is_100() -> void:
	# 全屏红 + 正脸 + 满服装 → 四维各 1.0 → 总分 100
	var img := _image_with_region(Color.RED, Rect2i(0, 0, SIZE.x, SIZE.y))
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [_meta(0, Color.RED, 1.0, 1.0)], SIZE)
	var actor: Dictionary = results["actors"][0]
	assert_eq(actor["total"], 100.0, "四维满分应为 100")

func test_total_min_is_zero() -> void:
	# 全黑（无可见像素）+ 背对 + 无服装 → 总分 0
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [_meta(0, Color.RED, 0.0, 0.0)], SIZE)
	var actor: Dictionary = results["actors"][0]
	assert_eq(actor["total"], 0.0, "四维零分应为 0")

# --- 完全出镜 ---

func test_out_of_photo_zeroes_pixel_dims() -> void:
	# 仅 5px 可见（低于 min_visible_px=20）→ 画面比例/C位/朝向归零，服装保留
	var img := _image_with_region(Color.RED, Rect2i(0, 0, 2, 2))
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [_meta(0, Color.RED, 0.8, 0.6)], SIZE)
	var actor: Dictionary = results["actors"][0]
	assert_false(actor["in_photo"], "可见像素不足应判完全出镜")
	assert_eq(actor["ratio"], 0.0, "出镜后画面比例应为 0")
	assert_eq(actor["center"], 0.0, "出镜后 C 位应为 0")
	assert_eq(actor["facing"], 0.0, "出镜后朝向应为 0")
	assert_almost_eq(actor["outfit"], 0.6, 0.001, "服装不受出镜影响")

func test_facing_zero_when_ratio_zero() -> void:
	# ratio=0 时 facing 强制为 0，即使 meta 中 facing=1.0
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [_meta(0, Color.RED, 1.0, 0.5)], SIZE)
	var actor: Dictionary = results["actors"][0]
	assert_eq(actor["ratio"], 0.0, "无像素时 ratio 应为 0")
	assert_eq(actor["facing"], 0.0, "ratio=0 时 facing 应强制为 0")

# --- 排名 ---

func test_rank_descending_by_total() -> void:
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for y in range(3, 8):
		for x in range(3, 8):
			img.set_pixel(x, y, Color.RED)
	for y in range(5):
		for x in range(5):
			img.set_pixel(x, y, Color.GREEN)
	var analyzer = SA.new()
	var results: Dictionary = analyzer.analyze(img, [
		_meta(0, Color.RED, 0.5, 0.0),
		_meta(1, Color.GREEN, 0.5, 0.0),
	], SIZE)
	var actors: Array = results["actors"]
	assert_eq(actors[0]["player_index"], 0, "总分高者（中心）应排第一")
	assert_eq(actors[1]["player_index"], 1, "总分低者（角落）应排第二")
	assert_eq(actors[0]["rank"], 1)
	assert_eq(actors[1]["rank"], 2)

# --- 朝向数学 ---

func test_facing_forward_is_one() -> void:
	assert_almost_eq(SA.compute_facing(Vector3.FORWARD, Vector3.FORWARD), 1.0, 0.001, "正脸朝镜头应为 1")

func test_facing_backward_is_zero() -> void:
	assert_almost_eq(SA.compute_facing(Vector3.FORWARD, Vector3.BACK), 0.0, 0.001, "背对镜头应为 0")

func test_facing_sideways_is_half() -> void:
	assert_almost_eq(SA.compute_facing(Vector3.FORWARD, Vector3.RIGHT), 0.5, 0.001, "侧对镜头应为 0.5")

func test_facing_zero_vector_returns_zero() -> void:
	assert_eq(SA.compute_facing(Vector3.ZERO, Vector3.FORWARD), 0.0, "零向量应返回 0")

# --- 辅助 ---

func _actor_by_index(results: Dictionary, player_index: int) -> Dictionary:
	for actor in results["actors"]:
		if int(actor["player_index"]) == player_index:
			return actor
	return {}
