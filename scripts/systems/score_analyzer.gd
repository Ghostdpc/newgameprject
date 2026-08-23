## 职责：快门帧四维评分纯算法（可脱离渲染单测）
## 输入：ID 掩码 Image + 每名演员元数据（颜色/朝向/服装绝对分）
## 输出：每名演员四维绝对分 + 0~100 总分 + 排名
##
## 画面比例：玩家像素 ÷ 所有玩家像素总和（玩家间相对占比，如 20/20 → 各 50%）
## C 位：    玩家中心加权 ÷ 所有玩家中心加权总和（相对归一），再乘距中心比例系数
## 服装/朝向：绝对分（0~1），不归一
##
## ratio / center 以玩家总量为基准归一，使 4 人时各维数量级与 outfit/facing 一致（~25 分区间）

class_name ScoreAnalyzer
extends RefCounted

const DIM_KEYS: Array[String] = ["ratio", "center", "outfit", "facing"]

## 四维权重（画面比例 / C位 / 服装 / 朝向），和恒为 1
var weights: Dictionary = {
	"ratio": 0.25, "center": 0.25, "outfit": 0.25, "facing": 0.25,
}
## 中心衰减方式：linear（1-d）或 gaussian（exp(-k·d²)）
var center_falloff: String = "linear"
var falloff_k: float = 4.0
var color_tolerance: float = 0.06
var min_visible_px: int = 20

## actor_meta: Array[Dictionary]
## 每项 { "player_index": int, "color": Color, "facing": float(0~1), "outfit": float(0~1) }
func analyze(mask: Image, actor_meta: Array, size: Vector2i) -> Dictionary:
	var w := size.x
	var h := size.y
	var center := Vector2(w, h) * 0.5
	var half_diag := Vector2(w, h).length() * 0.5

	# 像素统计
	var counts: Array[int] = []
	var center_weights: Array[float] = []
	for i in actor_meta.size():
		counts.append(0)
		center_weights.append(0.0)

	for y in h:
		for x in w:
			var c := mask.get_pixel(x, y)
			var i := _match_actor(c, actor_meta)
			if i < 0:
				continue
			counts[i] += 1
			center_weights[i] += _center_weight(Vector2(x, y), center, half_diag)

	# 所有玩家像素总和 / 中心加权总和（用于玩家间相对归一）
	var total_player_px: int = 0
	var total_player_cw: float = 0.0
	for i in actor_meta.size():
		if counts[i] >= min_visible_px:
			total_player_px += counts[i]
			total_player_cw += center_weights[i]

	# 逐演员四维
	var actor_results: Array = []
	for i in actor_meta.size():
		var meta: Dictionary = actor_meta[i]
		var idx: int = int(meta.get("player_index", -1))
		var color: Color = meta.get("color", Color.WHITE)
		var visible_px: int = counts[i]
		var in_photo: bool = visible_px >= min_visible_px

		# 画面比例：玩家像素 ÷ 所有玩家像素总和（玩家间相对占比，如 20/20 → 各 50%）
		var ratio: float = 0.0
		if in_photo and total_player_px > 0:
			ratio = float(visible_px) / float(total_player_px)

		# 占比分为 0（没被拍到/像素不足）时，其余三维一律 0：没入镜就没有任何得分
		var scored: bool = ratio > 0.0

		# C 位：相对中心加权归一 × 绝对中心距离系数
		# 绝对中心距离系数：玩家质心到图像中心的距离，中心=1，半对角线=0
		var center_norm: float = 0.0
		if scored and total_player_cw > 0.0:
			# 相对归一：该玩家中心加权 / 所有玩家中心加权和
			var relative_cw: float = center_weights[i] / total_player_cw
			# 绝对中心系数：玩家质心与图像中心的接近程度（0~1）
			var centroid := _compute_centroid(mask, meta.get("color", Color.WHITE), size)
			var dist_ratio: float = (centroid - center).length() / half_diag
			var proximity: float = clampf(1.0 - dist_ratio, 0.0, 1.0)
			# 综合：相对加权分 × 质心接近系数（两者都好才高分）
			center_norm = relative_cw * proximity

		# 占比为 0 的玩家四维全 0：没被拍到就没有任何得分（含服装分）
		var outfit: float = clampf(float(meta.get("outfit", 0.0)), 0.0, 1.0) if scored else 0.0
		var facing: float = clampf(float(meta.get("facing", 0.0)), 0.0, 1.0) if scored else 0.0

		var total01: float = weights.get("ratio", 0.0) * ratio \
			+ weights.get("center", 0.0) * center_norm \
			+ weights.get("outfit", 0.0) * outfit \
			+ weights.get("facing", 0.0) * facing
		# 负面效果（被炸）积分惩罚：从总分扣除，clamp 到 0 下限
		var penalty: int = int(meta.get("penalty", 0))
		var score := maxi(0, roundi(total01 * 100.0) - penalty)

		actor_results.append({
			"player_index": idx,
			"color": color,
			"in_photo": in_photo,
			"visible_px": visible_px,
			"percent": ratio,
			"ratio": ratio,
			"center": center_norm,
			"outfit": outfit,
			"facing": facing,
			"penalty": penalty,
			"dimensions": {
				"ratio": {"label": "画面比例", "score": ratio * 100.0},
				"center": {"label": "C位", "score": center_norm * 100.0},
				"outfit": {"label": "服装表现", "score": outfit * 100.0},
				"facing": {"label": "镜头朝向", "score": facing * 100.0},
			},
			"total": float(score),
		})

	actor_results.sort_custom(_sort_by_total)

	var rank := 1
	for r in actor_results:
		r["rank"] = rank
		rank += 1

	return {
		"actors": actor_results,
		"resolution": size,
	}

## 镜头朝向绝对分：正脸朝镜头 = 1，背对 = 0
static func compute_facing(forward: Vector3, to_cam: Vector3) -> float:
	if forward.length_squared() < 0.0001 or to_cam.length_squared() < 0.0001:
		return 0.0
	var dot := forward.normalized().dot(to_cam.normalized())
	return (dot + 1.0) * 0.5

## 计算指定颜色玩家的像素质心（加权中心位置）
## 用于 C 位绝对中心距离判断
func _compute_centroid(mask: Image, target_color: Color, size: Vector2i) -> Vector2:
	var sum_x: float = 0.0
	var sum_y: float = 0.0
	var count: int = 0
	for y in size.y:
		for x in size.x:
			var c := mask.get_pixel(x, y)
			var dist := absf(c.r - target_color.r) + absf(c.g - target_color.g) + absf(c.b - target_color.b)
			if dist < color_tolerance * 3.0:
				sum_x += float(x)
				sum_y += float(y)
				count += 1
	if count == 0:
		# 出镜时质心放到角落（最低 proximity）
		return Vector2(0.0, 0.0)
	return Vector2(sum_x / float(count), sum_y / float(count))

func _center_weight(p: Vector2, center: Vector2, half_diag: float) -> float:
	var d := (p - center).length() / half_diag
	if d >= 1.0:
		return 0.0
	if center_falloff == "gaussian":
		return exp(-falloff_k * d * d)
	return 1.0 - d

## 最近 ID 色匹配，返回演员索引；无匹配（背景/黑）返回 -1
func _match_actor(c: Color, actor_meta: Array) -> int:
	var best_i := -1
	var best_d := color_tolerance * 3.0
	for i in actor_meta.size():
		var t: Color = actor_meta[i].get("color", Color.WHITE)
		var dist := absf(c.r - t.r) + absf(c.g - t.g) + absf(c.b - t.b)
		if dist < best_d:
			best_d = dist
			best_i = i
	return best_i

func _sort_by_total(a: Dictionary, b: Dictionary) -> bool:
	var ta: float = a.get("total", 0.0)
	var tb: float = b.get("total", 0.0)
	if ta != tb:
		return ta > tb
	return a.get("ratio", 0.0) > b.get("ratio", 0.0)
