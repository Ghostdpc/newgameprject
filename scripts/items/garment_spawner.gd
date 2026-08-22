## 职责：服装刷新管理
## - 监听 battle_started：把所有服装各生成一件，从天而降
## - 监听 battle_ended：清场
## - 同 id 不重复在场（被拾取后记录解除，本战斗内不补刷）
## - 落点由 DropPlacement 统一分配（与道具共用热点，避免撞点）

extends Node

const GARMENT_PICKUP_SCRIPT: String = "res://scripts/items/garment_pickup.gd"

var _active_pickups: Array[Node] = []
## 当前在场的 garment_id 集合（防重复）
var _spawned_ids: Dictionary = {}

func _ready() -> void:
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)

func _on_battle_started() -> void:
	_active_pickups.clear()
	_spawned_ids.clear()

	var pickup_script := load(GARMENT_PICKUP_SCRIPT) as Script
	if pickup_script == null:
		push_warning("GarmentSpawner: cannot load garment_pickup.gd")
		return

	var ids := GarmentSystem._garment_config.all_ids()
	# 打乱顺序，避免每次同一件落到同一热点
	ids.shuffle()
	for garment_id in ids:
		_spawn_one(garment_id, pickup_script)

func _on_battle_ended() -> void:
	for pickup in _active_pickups:
		if is_instance_valid(pickup):
			pickup.queue_free()
	_active_pickups.clear()
	_spawned_ids.clear()

## 生成单件服装
func _spawn_one(garment_id: String, pickup_script: Script) -> void:
	if _spawned_ids.has(garment_id):
		return

	var pickup := Area3D.new()
	pickup.set_script(pickup_script)
	pickup.garment_id = garment_id
	var pos := DropPlacement.pick_position()
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	host.add_child(pickup)
	pickup.global_position = pos
	# 连接拾取销毁信号，解除 spawned_ids 记录
	pickup.tree_exited.connect(_on_pickup_removed.bind(garment_id))

	_active_pickups.append(pickup)
	_spawned_ids[garment_id] = true

func _on_pickup_removed(garment_id: String) -> void:
	_spawned_ids.erase(garment_id)
	_active_pickups = _active_pickups.filter(func(p): return is_instance_valid(p))
