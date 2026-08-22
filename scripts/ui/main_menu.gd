## 職責：主界面，提供開始遊戲與退出

class_name MainMenu
extends Control

@onready var _start_button: Button = $Center/VBox/StartButton
@onready var _quit_button: Button  = $Center/VBox/QuitButton

func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/photo_stage.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
