## 職責：道具箱生成管理（監聽 battle_started/ended，維持 max_active 上限）

extends Node

var _item_ids: Array[String] = []
var _hotspots: Array[Node3D] = []
var _active_boxes: Array[Node] = []
var _respawn_timer: float = 0.0
var _max_active: int = 5
var _respawn_interval: float = 8.0
var _running: bool = false

const ITEM_BOX_SCRIPT: String = "res://scripts/items/item_box.gd"

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
	for i in range(_max_active):
		_try_spawn()

func _try_spawn() -> void:
	if _item_ids.is_empty():
		push_warning("ItemSpawner: no item_ids loaded")
		return
	var spot := _pick_free_hotspot()
	if spot == null:
		# 無熱點時回退到場景原點附近隨機位置
		spot = _make_fallback_spot()
	var box_script := load(ITEM_BOX_SCRIPT) as Script
	if box_script == null:
		push_warning("ItemSpawner: cannot load item_box.gd")
		return
	var box := Area3D.new()
	box.set_script(box_script)
	var chosen_id: String = _item_ids[randi() % _item_ids.size()]
	get_tree().current_scene.add_child(box)
	box.item_id = chosen_id
	box.global_position = (spot as Node3D).global_position + Vector3(0.0, 0.25, 0.0)
	_active_boxes.append(box)
	EventBus.item_spawned.emit(chosen_id, box.global_position)

## 找一個當前沒有 box 佔用的熱點（簡單距離判斷）
func _pick_free_hotspot() -> Node3D:
	if _hotspots.is_empty():
		return null
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

## 無熱點時在舞台範圍內隨機生成臨時位置節點（不 queue_free，由調用方用完後 box 替代它）
func _make_fallback_spot() -> Node3D:
	var dummy := Node3D.new()
	dummy.position = Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
	get_tree().current_scene.add_child(dummy)
	# 用完後延遲釋放（等 _try_spawn 讀完 global_position）
	dummy.call_deferred("queue_free")
	return dummy
