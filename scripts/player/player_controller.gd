## 職責：玩家主控制器，整合輸入/狀態機/物理移動/動畫

class_name PlayerController
extends CharacterBody3D

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 6.0
const ACCELERATION: float = 15.0
## 拾取有效距離（米）
const PICKUP_RANGE: float = 1.5

const ANIM_IDLE: String = "Idle_A"
const ANIM_MOVE: String = "Running_A"
const ANIM_JUMP: String = "Jump_Full_Long"
const ANIM_DIVE: String = "Jump_Full_Short"

const IDLE_SOURCE: String = "res://assets/models/mannequin/animations/Rig_Medium_General.glb"

## 拾取長按時長（秒，策划要求 0.8）
const PICKUP_HOLD_TIME: float = 0.8

@export var jump_force: float = 10.0
@export var player_index: int = 0
@export var player_color: Color = Color.WHITE

signal item_picked_up(item_id: String)
signal item_used(item_id: String)
signal item_cleared()
signal death_started(player: PlayerController)

var player_input: PlayerInput
var state_machine: PlayerStateMachine
var ragdoll_rig: RagdollRig
var outfit_manager: OutfitManager
var character_effects: CharacterEffects

## 持有的道具 id，空字符串表示无道具（每次最多持有一个）
var held_item_id: String = ""
## 移速乘數（1.0 = 正常；由 player_speed_effect 臨時修改）
var speed_multiplier: float = 1.0

var _animation_player: AnimationPlayer
var _current_anim: String = ""

var _pickup_hold_time: float = 0.0

## 是否處於死亡/復活流程（非正常對戰狀態）
func is_dead() -> bool:
	var st := state_machine.current_state_name
	return st == "Death" or st == "RespawnWaiting" or st == "RespawnFall"

func _ready() -> void:
	player_input = PlayerInput.new(player_index)
	_setup_state_machine()
	_setup_model()
	_setup_outfit()
	apply_player_color(player_color)
	add_to_group("players")

## 開關布娃娃（被擊倒時進入物理倒地）
func set_ragdoll(enabled: bool) -> void:
	if not ragdoll_rig:
		return
	ragdoll_rig.set_ragdoll_enabled(enabled)

## 擊飛：body 位移（模型跟 body，姿態由 ragdoll 提供）
func knockback(direction: Vector3) -> void:
	velocity = direction

## 站起前把 body 移到 ragdoll 倒地落點（避免站起瞬移）
func sync_body_to_ragdoll() -> void:
	if not ragdoll_rig:
		return
	var hips_pos := ragdoll_rig.get_hips_position()
	if hips_pos == Vector3.ZERO:
		return
	global_position = Vector3(hips_pos.x, global_position.y, hips_pos.z)

## 出界死亡：進入死亡狀態（清道具、藏體、停物理）
func die() -> void:
	if state_machine.current_state_name == "Death":
		return
	death_started.emit(self)
	state_machine.transition_to("Death")

## 配置重生（由 LevelBase 設定復活點與讀秒時長）
func configure_respawn(spawn_pos: Vector3, wait_duration: float) -> void:
	var waiting := state_machine.get_state("RespawnWaiting") as RespawnWaitingState
	if waiting:
		waiting.configure(spawn_pos, wait_duration)

## 倒地後站起，由調用方確保已關閉 ragdoll
func stand_up() -> void:
	if ragdoll_rig:
		ragdoll_rig.reset()

## 拾取道具（覆盖式：新道具直接替换当前持有；ON_PICKUP 触发器立即使用）
func pickup_item(item_id: String) -> void:
	held_item_id = item_id
	item_picked_up.emit(item_id)
	EventBus.item_picked_up.emit(player_index, item_id)
	var def := ItemSystem._item_config.get_item(item_id) if ItemSystem else null
	if def and def.trigger == ItemTypes.Trigger.ON_PICKUP:
		use_held_item()

## 使用当前持有的道具（供输入系统或外部调用）
func use_held_item() -> void:
	if held_item_id.is_empty():
		return
	var id := held_item_id
	held_item_id = ""
	item_used.emit(id)
	ItemSystem.use_item(self, id)

## 丢弃持有的道具（不触发效果）
func clear_item() -> void:
	if held_item_id.is_empty():
		return
	held_item_id = ""
	item_cleared.emit()

func _process(delta: float) -> void:
	if is_dead():
		return
	state_machine.update(delta)
	_update_animation()
	if player_input.is_use_item_just_pressed():
		if not held_item_id.is_empty():
			# 身上有道具：立即使用
			use_held_item()
		else:
			# 身上無道具：嘗試拾取附近道具
			_try_pickup()

## 长按拾取逻辑：按住 0.8s 触发；移动/受控 打断
func _update_pickup_hold(delta: float) -> void:
	# 拾取可被打断：移动 / 非 Idle/Move 状态
	var st := state_machine.current_state_name
	var can_pickup := (st == "Idle" or st == "Move") and _pickup_movement_blocked() == false
	if not can_pickup:
		_pickup_hold_time = 0.0
		return
	if player_input.is_pickup_held():
		_pickup_hold_time += delta
		if _pickup_hold_time >= PICKUP_HOLD_TIME:
			_pickup_hold_time = 0.0
			_try_pickup()
	else:
		_pickup_hold_time = 0.0

## 拾取長按時如果正在移動則中斷（策划：移動會打斷拾取）
func _pickup_movement_blocked() -> bool:
	return player_input.get_move_direction().length_squared() > 0.0

func _try_pickup() -> void:
	var id := _pickup_item_id()
	if not id.is_empty():
		pickup_item(id)

## 拾取：讓地上道具實體自己把 id 告訴我們（實體未實現，返回空）
func _pickup_item_id() -> String:
	if not held_item_id.is_empty():
		return ""
	var items := get_tree().get_nodes_in_group("pickup_items")
	if items.is_empty():
		return ""
	# 取拾取範圍內最近的一個
	var nearest: Node3D = null
	var best_d := INF
	var range_sq := PICKUP_RANGE * PICKUP_RANGE
	for item in items:
		var n := item as Node3D
		if not n:
			continue
		var d := global_position.distance_squared_to(n.global_position)
		if d < range_sq and d < best_d:
			best_d = d
			nearest = n
	if nearest and nearest.has_method("pickup_for"):
		return nearest.pickup_for(self)
	return ""

func _physics_process(delta: float) -> void:
	# 死亡/復活狀態也需物理幀推進（Death→Waiting→Fall），故不整體跳過
	_apply_gravity(delta)
	state_machine.physics_update(delta)
	if is_dead():
		move_and_slide()
		return
	move_and_slide()
	_check_dive_hit()

## 飛撲狀態碰撞檢測：命中其他玩家則擊飛
func _check_dive_hit() -> void:
	if state_machine.current_state_name != "Dive":
		return
	var dive := state_machine.get_current_state() as DiveState
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PlayerController:
			dive.hit_target(collider as PlayerController)

func apply_move(direction: Vector2) -> void:
	var target_velocity := Vector3(direction.x, 0.0, direction.y) * MOVE_SPEED * speed_multiplier
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * get_physics_process_delta_time())
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * get_physics_process_delta_time())
	if direction.length_squared() > 0.0:
		# 模型正面朝 +Z，looking_at 讓 -Z 指向移動方向，故取反使正面朝前
		var look_dir := Vector3(-direction.x, 0.0, -direction.y)
		var target_basis := Basis.looking_at(look_dir, Vector3.UP)
		global_basis = global_basis.slerp(target_basis, 0.2)

func _apply_gravity(delta: float) -> void:
	if is_dead():
		return
	if not is_on_floor():
		# Fly 階段由 FlyState 自行管理重力（可自定義下墜）
		if state_machine.current_state_name == "Fly":
			return
		# 被擊飛期間用更大重力，讓上升/下降都更快
		var g := GRAVITY
		if state_machine.current_state_name == "Stunned":
			g = TuneConfig.stun_gravity
		velocity.y -= g * delta

func _setup_state_machine() -> void:
	state_machine = PlayerStateMachine.new()
	add_child(state_machine)

	var idle := IdleState.new()
	var move := MoveState.new()
	var jump := JumpState.new()
	var dive := DiveState.new()
	var fly := FlyState.new()
	var stunned := StunnedState.new()
	var death := DeathState.new()
	var respawn_waiting := RespawnWaitingState.new()
	var respawn_fall := RespawnFallState.new()

	idle.init(self)
	move.init(self)
	jump.init(self)
	dive.init(self)
	fly.init(self)
	stunned.init(self)
	death.init(self)
	respawn_waiting.init(self)
	respawn_fall.init(self)

	state_machine.register_state("Idle", idle)
	state_machine.register_state("Move", move)
	state_machine.register_state("Jump", jump)
	state_machine.register_state("Dive", dive)
	state_machine.register_state("Fly", fly)
	state_machine.register_state("Stunned", stunned)
	state_machine.register_state("Death", death)
	state_machine.register_state("RespawnWaiting", respawn_waiting)
	state_machine.register_state("RespawnFall", respawn_fall)

	state_machine.start("Idle")

## 定位模型骨架與動畫播放器
func _setup_model() -> void:
	var model := get_node_or_null("Model")
	if not model:
		return
	_animation_player = _find_animation_player(model)
	_merge_idle_animation()
	_set_animation_looping(ANIM_IDLE)
	_set_animation_looping(ANIM_MOVE)
	_set_animation_looping(ANIM_JUMP)
	_set_animation_looping(ANIM_DIVE)
	# 初始化布娃娃（綁定模型骨架）
	ragdoll_rig = get_node_or_null("RagdollRig") as RagdollRig
	if ragdoll_rig:
		var skeleton := _find_skeleton(model)
		if skeleton and _animation_player:
			ragdoll_rig.setup(skeleton, _animation_player)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

## 從 General.glb 合併 Idle 動畫（MovementBasic 無待機動畫）
func _merge_idle_animation() -> void:
	if not _animation_player or _animation_player.has_animation(ANIM_IDLE):
		return
	var glb := load(IDLE_SOURCE) as PackedScene
	if not glb:
		return
	var inst := glb.instantiate()
	var src_ap := _find_animation_player(inst)
	if src_ap and src_ap.has_animation(ANIM_IDLE):
		var anim: Animation = src_ap.get_animation(ANIM_IDLE).duplicate()
		var lib := _animation_player.get_animation_library("")
		if lib:
			lib.add_animation(ANIM_IDLE, anim)
	inst.queue_free()

## 設定單個動畫循環
func _set_animation_looping(anim_name: String) -> void:
	if _animation_player and _animation_player.has_animation(anim_name):
		_animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

## 依當前狀態切換動畫
func _update_animation() -> void:
	if not _animation_player:
		return
	if is_dead():
		return
	if state_machine.current_state_name == "Stunned":
		return
	if ragdoll_rig and ragdoll_rig.is_standing_up():
		return
	var anim_name := _anim_for_state(state_machine.current_state_name)
	if anim_name != _current_anim:
		_animation_player.play(anim_name)
		_current_anim = anim_name

func _anim_for_state(state_name: String) -> String:
	match state_name:
		"Move":
			return ANIM_MOVE
		"Jump":
			return ANIM_JUMP
		"Dive":
			return ANIM_DIVE
		"Fly":
			# 被擊飛姿態（暫用飛撲動畫，後續可加專用被擊動畫 / 翻滾）
			return ANIM_DIVE
		_:
			return ANIM_IDLE

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null

## 定位換裝系統與角色效果組件
func _setup_outfit() -> void:
	outfit_manager = get_node_or_null("OutfitManager") as OutfitManager
	character_effects = get_node_or_null("CharacterEffects") as CharacterEffects

## 設定玩家顏色（走 OutfitManager + CharacterEffects 統一處理）
func apply_player_color(color: Color) -> void:
	player_color = color
	if outfit_manager:
		outfit_manager.player_color = color
	if character_effects:
		character_effects.base_color = color
