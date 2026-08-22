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
