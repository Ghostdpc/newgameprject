## 职责：道具特效总控。
## 世界层只保留脚底能量圈与眩晕星；时间道具由边缘 UIMask 完成全屏反馈。

class_name PropVfxLayer
extends Node

const WORLD_VFX_SCENE := preload("res://scenes/fx/world_item_vfx.tscn")
const FULLSCREEN_POST_SCENE := preload("res://scenes/fx/fullscreen_item_post.tscn")
const SPEED_DURATION := 3.0

var _overlay: FullscreenItemPost

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = FULLSCREEN_POST_SCENE.instantiate() as FullscreenItemPost
	add_child(_overlay)
	EventBus.item_used.connect(_on_item_used)
	EventBus.trap_triggered.connect(_on_trap_triggered)
	EventBus.time_effect_applied.connect(_on_time_effect_applied)

func _on_item_used(player_index: int, item_id: String) -> void:
	var player := _player_for_index(player_index)
	match item_id:
		"energy_drink":
			_spawn_ring(player, SPEED_DURATION, Color(1.0, 0.56, 0.06, 1.0))
		"banana_peel":
			_spawn_ring(player, 0.52, Color(1.0, 0.82, 0.08, 1.0))
		"fast_forward_crank":
			_spawn_ring(player, 0.62, Color(1.0, 0.12, 0.04, 1.0))
			_overlay.play("fast", SPEED_DURATION)
		"slow_hourglass":
			_spawn_ring(player, 0.62, Color(0.14, 0.66, 1.0, 1.0))
			_overlay.play("slow", SPEED_DURATION)
		"time_battery":
			_spawn_ring(player, 0.72, Color(0.20, 1.0, 0.38, 1.0))
			_overlay.play("add", 0.58)
		"time_scissors":
			_spawn_ring(player, 0.72, Color(1.0, 0.06, 0.04, 1.0))
			_overlay.play("sub", 0.58)
		"camera_remote":
			_spawn_ring(player, 2.5, Color(1.0, 0.76, 0.16, 1.0))
			_overlay.play("camera", 2.5)

func _on_trap_triggered(trap_id: String, player_index: int) -> void:
	if trap_id == "banana_peel":
		_spawn_stun(_player_for_index(player_index))

func _on_time_effect_applied(effect_type: int, value: float) -> void:
	if effect_type == 0 and value <= 0.0:
		_overlay.clear_mode("fast")
	elif effect_type == 1 and value <= 0.0:
		_overlay.clear_mode("slow")

func _spawn_ring(target: Node3D, duration: float, color: Color) -> void:
	if target == null:
		return
	var effect := WORLD_VFX_SCENE.instantiate() as WorldItemVfx
	effect.configure(WorldItemVfx.Kind.FEET_RING, duration, target, color)
	_world_parent().add_child(effect)

func _spawn_stun(target: Node3D) -> void:
	if target == null:
		return
	var effect := WORLD_VFX_SCENE.instantiate() as WorldItemVfx
	effect.configure(WorldItemVfx.Kind.BANANA_STUN, 1.5, target)
	_world_parent().add_child(effect)

## 撞击爆闪（撞到玩家/墙/道具）—— 在指定位置命中处生成短促白黄火光
func spawn_hit_shockwave(world_pos: Vector3, color: Color = Color(1.0, 0.85, 0.35, 1.0)) -> void:
	var parent := get_tree().current_scene if get_tree().current_scene else get_tree().root
	BombInstance.spawn_explosion_fx(world_pos, parent, 2.0, true)

func _player_for_index(player_index: int) -> PlayerController:
	if player_index < 0:
		return null
	for node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController and (node as PlayerController).player_index == player_index:
			return node as PlayerController
	return null

func _world_parent() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_tree().root
