## 職責：放置物實例，Area3D 節點，檢測踩踏後觸發效果（單次觸發）

class_name TrapInstance
extends Area3D

var trap_def: TrapDef
var owner_player: PlayerController

var _lifetime_timer: float = 0.0
var _triggered: bool = false

func setup(def: TrapDef, placer: PlayerController) -> void:
	trap_def    = def
	owner_player = placer
	_lifetime_timer = def.lifetime

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 0.2
	shape.shape = capsule
	add_child(shape)

	body_entered.connect(_on_body_entered)
	add_to_group("traps")

func _process(delta: float) -> void:
	if _triggered:
		return
	if trap_def == null or trap_def.lifetime <= 0.0:
		return
	_lifetime_timer -= delta
	if _lifetime_timer <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	if not (body is PlayerController):
		return
	_triggered = true

	var player := body as PlayerController
	for effect in trap_def.effects:
		var targets := _resolve_targets(effect.target, player)
		for target_player in targets:
			var ctx := ItemContext.new()
			ctx.source_player = target_player
			ctx.item_id       = trap_def.id
			effect.apply(ctx)

	EventBus.trap_triggered.emit(trap_def.id, player.player_index)
	queue_free()

func _resolve_targets(target: ItemTypes.Target, stepper: PlayerController) -> Array:
	if target == ItemTypes.Target.WORLD:
		return [null]
	var all_players: Array[PlayerController] = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is PlayerController:
			all_players.append(node as PlayerController)
	match target:
		ItemTypes.Target.SELF:
			return [stepper]
		ItemTypes.Target.OTHERS:
			return all_players.filter(func(p): return p != stepper)
		ItemTypes.Target.ALL:
			return all_players
	return []
