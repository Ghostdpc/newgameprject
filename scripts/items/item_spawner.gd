## 職責：道具箱生成管理（監聽 battle_started/ended，維持 max_active 上限）

extends Node

var _item_ids: Array[String] = []
var _hotspots: Array[Node3D] = []
var _active_boxes: Array[Node] = []
var _respawn_timer: float = 0.0
var _max_active: int = 5
var _respawn_interval: float = 8.0
var _running: bool = false

const BOX_SCENE_PATH: String = "res://scenes/items/item_box.tscn"

func _ready() -> void:
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)

func _on_battle_started() -> void:
	var cfg: Dictionary = ItemSystem._item_config.get_spawn_config()
	_max_active       = int(cfg.get("max_active", 5))
	_respawn_interval = float(cfg.get("respawn_interval", 8.0))
	_item_ids         = ItemSystem._item_config.all_ids()
	_hotspots.clear()
	for node in get_tree().get_nodes_in_group("item_hotspot"):
		if node is Node3D:
			_hotspots.append(node as Node3D)
	_respawn_timer = 0.0
	_running       = true
	_fill_initial()

func _on_battle_ended() -> void:
	_running = false
	for box in _active_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_active_boxes.clear()
	for trap in get_tree().get_nodes_in_group("traps"):
		trap.queue_free()

func _process(delta: float) -> void:
	if not _running:
		return
	_active_boxes = _active_boxes.filter(func(b): return is_instance_valid(b))
	if _active_boxes.size() >= _max_active:
		return
	_respawn_timer += delta
	if _respawn_timer >= _respawn_interval:
		_respawn_timer = 0.0
		_try_spawn()

## 開局一次性填滿到 max_active
func _fill_initial() -> void:
	var needed: int = _max_active
	for i in range(needed):
		_try_spawn()

func _try_spawn() -> void:
	if _item_ids.is_empty() or _hotspots.is_empty():
		return
	var spot := _pick_free_hotspot()
	if spot == null:
		return
	if not ResourceLoader.exists(BOX_SCENE_PATH):
		push_warning("ItemSpawner: item_box.tscn not found at '%s'" % BOX_SCENE_PATH)
		return
	var box_scene := load(BOX_SCENE_PATH) as PackedScene
	if box_scene == null:
		return
	var box: Node = box_scene.instantiate()
	box.set("item_id", _item_ids[randi() % _item_ids.size()])
	get_tree().current_scene.add_child(box)
	if box is Node3D:
		(box as Node3D).global_position = (spot as Node3D).global_position
	_active_boxes.append(box)
	EventBus.item_spawned.emit(box.get("item_id"), (spot as Node3D).global_position)

## 找一個當前沒有 box 佔用的熱點（簡單距離判斷）
func _pick_free_hotspot() -> Node3D:
	var used_positions: Array[Vector3] = []
	for box in _active_boxes:
		if is_instance_valid(box) and box is Node3D:
			used_positions.append((box as Node3D).global_position)

	var candidates: Array[Node3D] = []
	for spot in _hotspots:
		var occupied := false
		for pos in used_positions:
			if (spot as Node3D).global_position.distance_to(pos) < 1.0:
				occupied = true
				break
		if not occupied:
			candidates.append(spot as Node3D)

	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]
