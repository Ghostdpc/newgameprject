## 職責：區域系統，追蹤哪些玩家在結算區域內

class_name ZoneSystem
extends Node

var players_in_zone: Array[int] = []

@onready var _zone_area: Area3D = $Area3D

func _ready() -> void:
	if _zone_area:
		_zone_area.body_entered.connect(_on_body_entered)
		_zone_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	var controller := body as PlayerController
	if controller and controller.player_index not in players_in_zone:
		players_in_zone.append(controller.player_index)
		EventBus.player_entered_zone.emit(controller.player_index)

func _on_body_exited(body: Node3D) -> void:
	var controller := body as PlayerController
	if controller:
		players_in_zone.erase(controller.player_index)
		EventBus.player_exited_zone.emit(controller.player_index)
