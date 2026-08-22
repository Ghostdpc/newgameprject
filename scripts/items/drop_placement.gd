## 职责：掉落物落点统一分配器（autoload）
## 道具箱与服装共用同一批 item_hotspot；分配时全局统计所有已落物占用，避免撞点。
## ItemSpawner / GarmentSpawner 均调 pick_position() 取点，不再各自选点。

extends Node

## 视为"已占用"的掉落物分组（新增掉落物类型时在此登记）
const OCCUPY_GROUPS: Array[String] = ["item_boxes", "garment_pickups"]
## 两个落点之间的最小水平间距（米，低于此视为占用）
const MIN_SPACING: float = 1.5
## 无空闲热点时的回退随机范围（米）
const FALLBACK_RANGE: float = 4.0

var _hotspots: Array[Node3D] = []

func _ready() -> void:
	EventBus.battle_started.connect(refresh_hotspots)

## 重新收集场景中的 item_hotspot（战斗开始时刷新）
func refresh_hotspots() -> void:
	_hotspots.clear()
	for node in get_tree().get_nodes_in_group("item_hotspot"):
		if node is Node3D:
			_hotspots.append(node as Node3D)

## 取一个空闲落点世界坐标（避开所有已落物）；无空闲热点时回退随机位置
func pick_position() -> Vector3:
	if _hotspots.is_empty():
		refresh_hotspots()
	var occupied := _occupied_positions()

	var candidates: Array[Vector3] = []
	for spot in _hotspots:
		if is_instance_valid(spot) and not _is_occupied(spot.global_position, occupied):
			candidates.append(spot.global_position)

	if candidates.is_empty():
		return _fallback_position(occupied)
	return candidates[randi() % candidates.size()]

## 统计所有已落物的当前位置（跨类型）
func _occupied_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for group in OCCUPY_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				result.append((node as Node3D).global_position)
	return result

## 水平（xz）距离判断是否被占用（忽略 y，兼容掉落动画抬高）
func _is_occupied(pos: Vector3, occupied: Array[Vector3]) -> bool:
	var min_sq := MIN_SPACING * MIN_SPACING
	for o in occupied:
		var dx := pos.x - o.x
		var dz := pos.z - o.z
		if dx * dx + dz * dz < min_sq:
			return true
	return false

## 回退：随机撒点，尝试避开已占用；多次失败则直接返回随机点
func _fallback_position(occupied: Array[Vector3]) -> Vector3:
	for i in range(20):
		var p := Vector3(
			randf_range(-FALLBACK_RANGE, FALLBACK_RANGE),
			0.0,
			randf_range(-FALLBACK_RANGE, FALLBACK_RANGE))
		if not _is_occupied(p, occupied):
			return p
	return Vector3(
		randf_range(-FALLBACK_RANGE, FALLBACK_RANGE),
		0.0,
		randf_range(-FALLBACK_RANGE, FALLBACK_RANGE))
