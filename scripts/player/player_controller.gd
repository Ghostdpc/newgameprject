## 職責：玩家主控制器，整合輸入/狀態機/物理移動/動畫

class_name PlayerController
extends CharacterBody3D

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 6.0
const ACCELERATION: float = 15.0

const ANIM_IDLE: String = "T-Pose"
const ANIM_MOVE: String = "Running_A"
const ANIM_JUMP: String = "Jump_Full_Long"
const ANIM_DIVE: String = "Jump_Full_Short"

@export var jump_force: float = 10.0
@export var player_index: int = 0
@export var player_color: Color = Color.WHITE

var player_input: PlayerInput
var state_machine: PlayerStateMachine
var ragdoll_rig: RagdollRig

var _animation_player: AnimationPlayer
var _current_anim: String = ""

func _ready() -> void:
	player_input = PlayerInput.new(player_index)
	_setup_state_machine()
	_setup_model()
	_apply_player_color()
	add_to_group("players")

## 開關布娃娃（被擊倒時進入物理倒地）
func set_ragdoll(enabled: bool) -> void:
	if not ragdoll_rig:
		return
	ragdoll_rig.set_ragdoll_enabled(enabled)

## 擊飛：body 位移（不施加到物理骨，避免 mesh 脫離 body）
func knockback(direction: Vector3) -> void:
	velocity.x = direction.x
	velocity.z = direction.z
	velocity.y = direction.y

## 倒地後站起，由調用方確保已關閉 ragdoll
func stand_up() -> void:
	if ragdoll_rig:
		ragdoll_rig.reset()

func _process(delta: float) -> void:
	state_machine.update(delta)
	_update_animation()

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	state_machine.physics_update(delta)
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
	var target_velocity := Vector3(direction.x, 0.0, direction.y) * MOVE_SPEED
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * get_physics_process_delta_time())
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * get_physics_process_delta_time())
	if direction.length_squared() > 0.0:
		# 模型正面朝 +Z，looking_at 讓 -Z 指向移動方向，故取反使正面朝前
		var look_dir := Vector3(-direction.x, 0.0, -direction.y)
		var target_basis := Basis.looking_at(look_dir, Vector3.UP)
		global_basis = global_basis.slerp(target_basis, 0.2)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

func _setup_state_machine() -> void:
	state_machine = PlayerStateMachine.new()
	add_child(state_machine)

	var idle := IdleState.new()
	var move := MoveState.new()
	var jump := JumpState.new()
	var dive := DiveState.new()
	var stunned := StunnedState.new()

	idle.init(self)
	move.init(self)
	jump.init(self)
	dive.init(self)
	stunned.init(self)

	state_machine.register_state("Idle", idle)
	state_machine.register_state("Move", move)
	state_machine.register_state("Jump", jump)
	state_machine.register_state("Dive", dive)
	state_machine.register_state("Stunned", stunned)

	state_machine.start("Idle")

## 定位模型骨架與動畫播放器
func _setup_model() -> void:
	var model := get_node_or_null("Model")
	if not model:
		return
	_animation_player = _find_animation_player(model)
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

## 設定單個動畫循環
func _set_animation_looping(anim_name: String) -> void:
	if _animation_player and _animation_player.has_animation(anim_name):
		_animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

## 依當前狀態切換動畫
func _update_animation() -> void:
	if not _animation_player:
		return
	if state_machine.current_state_name == "Stunned":
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

func _apply_player_color() -> void:
	var model := get_node_or_null("Model")
	if not model:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = player_color
	_set_mesh_override(model, material)

func _set_mesh_override(n: Node, material: Material) -> void:
	if n is MeshInstance3D:
		for i in (n as MeshInstance3D).get_surface_override_material_count():
			(n as MeshInstance3D).set_surface_override_material(i, material)
	for c in n.get_children():
		_set_mesh_override(c, material)
