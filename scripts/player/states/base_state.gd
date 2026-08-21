## 職責：狀態基類，定義狀態介面

class_name BaseState
extends Node

var _player: CharacterBody3D

func init(player: CharacterBody3D) -> void:
	_player = player

func enter() -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass
