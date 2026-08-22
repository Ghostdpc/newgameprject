## 職責：遊戲場景初始化，生成玩家並設定相機

class_name Game
extends Node3D

const PLAYER_COUNT: int = 4
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2),
	Color(0.2, 0.4, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.8, 0.1),
]
const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-3.0, 1.0, -3.0),
	Vector3( 3.0, 1.0, -3.0),
	Vector3(-3.0, 1.0,  3.0),
	Vector3( 3.0, 1.0,  3.0),
]

const PHOTO_CAMERA_POSITION: Vector3 = Vector3(0.0, 1.5, 8.0)
const PHOTO_CAMERA_LOOK_TARGET: Vector3 = Vector3(0.0, 1.5, 0.0)

const FALL_Y: float = -5.0          ## 低於此高度視為出界死亡
const RESPAWN_DELAY: float = 2.0    ## 死亡到重生延遲
const RESPAWN_HEIGHT: float = 8.0   ## 重生時的空中高度（落地）
const SPAWN_RANGE: float = 12.0     ## 隨機複活點 xz 範圍（避開邊緣）

@export var player_scene: PackedScene

@onready var _players_root: Node3D = $Players
@onready var _main_camera: Camera3D = $MainCamera
@onready var _main_controller: CameraController = $MainCamera/CameraController
@onready var _photo_camera: Camera3D = $PhotoViewport/PhotoCamera
@onready var _photo_controller: CameraController = $PhotoViewport/PhotoCamera/CameraController

func _ready() -> void:
	_setup_main_camera()
	_setup_photo_camera()
	_spawn_players()
	GameManager.start_game()

func _setup_main_camera() -> void:
	_main_controller.init(_main_camera)
	var fixed := FixedShotBehavior.new()
	fixed.position = _main_camera.global_position
	fixed.look_target = Vector3.ZERO
	_main_controller.push_behavior(fixed)
	CameraSystem.register_main_camera(_main_controller)

func _setup_photo_camera() -> void:
	_photo_controller.init(_photo_camera)
	var fixed := FixedShotBehavior.new()
	fixed.position = PHOTO_CAMERA_POSITION
	fixed.look_target = PHOTO_CAMERA_LOOK_TARGET
	_photo_controller.push_behavior(fixed)
	CameraSystem.register_photo_camera(_photo_controller)

func _spawn_players() -> void:
	if not player_scene:
		push_error("Game: player_scene not assigned")
		return
	for i in PLAYER_COUNT:
		var player: PlayerController = player_scene.instantiate() as PlayerController
		player.player_index = i
		player.player_color = PLAYER_COLORS[i]
		player.position = SPAWN_POSITIONS[i]
		_players_root.add_child(player)

func _physics_process(_delta: float) -> void:
	for child in _players_root.get_children():
		var player := child as PlayerController
		if player and not player.is_dead and player.global_position.y < FALL_Y:
			_kill_and_respawn(player)

## 出界死亡→讀秒（顯示複活點標記）→隨機點空中落地
func _kill_and_respawn(player: PlayerController) -> void:
	player.die()
	var spot := _random_spawn_position()
	var marker := _create_respawn_marker(spot)
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	marker.queue_free()
	if not is_instance_valid(player):
		return
	player.respawn(Vector3(spot.x, RESPAWN_HEIGHT, spot.z))

## 場地範圍內隨機一點（xz 隨機，避開邊緣）
func _random_spawn_position() -> Vector3:
	var x := randf_range(-SPAWN_RANGE, SPAWN_RANGE)
	var z := randf_range(-SPAWN_RANGE, SPAWN_RANGE)
	return Vector3(x, 1.0, z)

## 讀秒期間在複活點顯示可見標記（黃色半透明光柱）
func _create_respawn_marker(pos: Vector3) -> Node3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = RESPAWN_HEIGHT
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color.YELLOW
	m.material_override = mat
	m.position = Vector3(pos.x, RESPAWN_HEIGHT * 0.5, pos.z)
	add_child(m)
	return m
