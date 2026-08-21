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

@export var player_scene: PackedScene

@onready var _players_root: Node3D = $Players
@onready var _main_camera: Camera3D = $MainCamera
@onready var _main_controller: CameraController = $MainCamera/CameraController

func _ready() -> void:
	_setup_main_camera()
	_spawn_players()

func _setup_main_camera() -> void:
	_main_controller.init(_main_camera)
	_main_controller.push_behavior(GroupFollowBehavior.new())
	CameraSystem.register_main_camera(_main_controller)

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
