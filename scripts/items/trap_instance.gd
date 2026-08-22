## 職責：放置物實例，Area3D 節點，檢測踩踏後觸發效果（單次觸發）

class_name TrapInstance
extends Area3D

var trap_def: TrapDef
var owner_player: PlayerController

var _lifetime_timer: float = 0.0
var _triggered: bool = false
## 生成後延遲激活，避免放置者同幀自觸發
var _activation_timer: float = 0.5
## 放置者是否已離開過本區域：離開前放置者踩到不觸發（避免原地放置即自滑倒/自消失）
var _owner_armed: bool = false

func setup(def: TrapDef, placer: PlayerController) -> void:
	trap_def    = def
	owner_player = placer
	_lifetime_timer = def.lifetime

	collision_layer = 0  # 放置物自身不占物理層
	collision_mask  = 2  # 檢測 layer=2（玩家層）
	monitoring = false   # 延遲激活，_activation_timer 歸零後才開啟

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.9, 0.3, 0.9)
	shape.shape = box_shape
	add_child(shape)

	# 放置物视觉：优先配置模型（香蕉皮），失败回退紫色 Cube 占位
	var visual: Node3D = null
	if not def.model.is_empty():
		visual = PropModelBuilder.build(def.model, def.texture, 0.6, def.model_scale, true)
	if visual == null:
		var mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 0.6, 0.6)
		mesh_inst.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.1, 1.0)
		mesh_inst.material_override = mat
		mesh_inst.position.y = 0.3  # 半高偏移，使方塊底部貼地
		visual = mesh_inst
	add_child(visual)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("traps")

func _process(delta: float) -> void:
	if _triggered:
		return
	if _activation_timer > 0.0:
		_activation_timer -= delta
		if _activation_timer <= 0.0:
			monitoring = true  # 延遲後才開始偵測
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
	var player := body as PlayerController
	# 放置者在離開本區域前不觸發：避免原地放置後 0.5s 激活即自踩，香蕉皮瞬間消失
	if player == owner_player and not _owner_armed:
		return
	_triggered = true

	_spawn_trigger_vfx(player.global_position)

	for effect in trap_def.effects:
		var targets := _resolve_targets(effect.target, player)
		for target_player in targets:
			var ctx := ItemContext.new()
			ctx.source_player = target_player
			ctx.item_id       = trap_def.id
			effect.apply(ctx)

	EventBus.trap_triggered.emit(trap_def.id, player.player_index)
	queue_free()

func _spawn_trigger_vfx(spawn_pos: Vector3) -> void:
	if trap_def.use_vfx.is_empty():
		return
	var scene: PackedScene = load(trap_def.use_vfx)
	if scene == null:
		return
	var vfx: Node3D = scene.instantiate() as Node3D
	if vfx == null:
		return
	if "autoplay" in vfx:
		vfx.autoplay = false
	if "one_shot" in vfx:
		vfx.one_shot = true
	# 放置物觸發固定在世界坐標（觸發點）播放
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = spawn_pos
	if vfx.has_method("play"):
		vfx.play()
	var anim: AnimationPlayer = vfx.get_node_or_null("AnimationPlayer")
	if anim:
		await anim.animation_finished
	else:
		await get_tree().create_timer(0.5).timeout
	if is_instance_valid(vfx):
		vfx.queue_free()

## 放置者離開後武裝：之後再踩（含放置者自己）才會觸發
func _on_body_exited(body: Node3D) -> void:
	if body == owner_player:
		_owner_armed = true

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
