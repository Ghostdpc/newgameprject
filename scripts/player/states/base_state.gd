## 职责：状态基类，定义状态介面

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
