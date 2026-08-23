## 職責：道具箱生成管理（監聽 battle_started/ended，維持 max_active 上限）
## 落點由 DropPlacement 統一分配（與服裝共用熱點，避免撞點）

extends Node

var _item_ids: Array[String] = []
var _active_boxes: Array[Node] = []
var _respawn_timer: float = 0.0
var _max_active: int = 5
var _respawn_interval: float = 8.0
var _initial_multiplier: float = 1.5
var _refresh_batch: int = 2
var _running: bool = false

const ITEM_BOX_SCRIPT: String = "res://scripts/items/item_box.gd"

func _ready() -> void:
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)

func _on_battle_started() -> void:
	var cfg: Dictionary = ItemSystem._item_config.get_spawn_config()
	_max_active         = int(cfg.get("max_active", 5))
	_respawn_interval   = float(cfg.get("respawn_interval", 8.0))
	_initial_multiplier = float(cfg.get("initial_multiplier", 1.5))
	_refresh_batch      = int(cfg.get("refresh_batch", 2))
	_item_ids           = ItemSystem._item_config.all_ids()
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
		for i in range(_refresh_batch):
			_try_spawn()

## 開局一次性填滿到 max_active * initial_multiplier
func _fill_initial() -> void:
	for i in range(int(_max_active * _initial_multiplier)):
		_try_spawn()

func _try_spawn() -> void:
	if _item_ids.is_empty():
		push_warning("ItemSpawner: no item_ids loaded")
		return
	var box_script := load(ITEM_BOX_SCRIPT) as Script
	if box_script == null:
		push_warning("ItemSpawner: cannot load item_box.gd")
		return
	var box := Area3D.new()
	box.set_script(box_script)
	var chosen_id: String = _item_ids[randi() % _item_ids.size()]
	box.item_id = chosen_id
	var pos := DropPlacement.pick_position() + Vector3(0.0, 0.25, 0.0)
	get_tree().current_scene.add_child(box)
	box.global_position = pos
	_active_boxes.append(box)
	EventBus.item_spawned.emit(chosen_id, box.global_position)
