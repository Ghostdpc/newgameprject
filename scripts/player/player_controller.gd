## 職責：玩家主控制器，整合輸入/狀態機/物理移動

class_name PlayerController
extends CharacterBody3D

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 6.0
const ACCELERATION: float = 15.0

@export var jump_force: float = 10.0
@export var player_index: int = 0
@export var player_color: Color = Color.WHITE

var player_input: PlayerInput
var state_machine: PlayerStateMachine

@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	player_input = PlayerInput.new(player_index)
	_setup_state_machine()
	_apply_player_color()
	add_to_group("players")

func _process(delta: float) -> void:
	state_machine.update(delta)

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	state_machine.physics_update(delta)
	move_and_slide()

func apply_move(direction: Vector2) -> void:
	var target_velocity := Vector3(direction.x, 0.0, direction.y) * MOVE_SPEED
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * get_physics_process_delta_time())
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * get_physics_process_delta_time())
	if direction.length_squared() > 0.0:
		var look_dir := Vector3(direction.x, 0.0, direction.y)
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

	idle.init(self)
	move.init(self)
	jump.init(self)
	dive.init(self)

	state_machine.register_state("Idle", idle)
	state_machine.register_state("Move", move)
	state_machine.register_state("Jump", jump)
	state_machine.register_state("Dive", dive)

	state_machine.start("Idle")

func _apply_player_color() -> void:
	if not _mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	_mesh.set_surface_override_material(0, mat)
