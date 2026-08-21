## 職責：管理主相機與攝影相機的行為堆疊

extends Node

const TARGET_MAIN: String = "main"
const TARGET_PHOTO: String = "photo"

var _main_controller: Node = null
var _photo_controller: Node = null

func _ready() -> void:
	EventBus.camera_behavior_push_requested.connect(_on_push_requested)
	EventBus.camera_behavior_pop_requested.connect(_on_pop_requested)

func register_main_camera(controller: Node) -> void:
	_main_controller = controller

func register_photo_camera(controller: Node) -> void:
	_photo_controller = controller

func push_behavior(target: String, behavior: Object, duration: float = 0.0) -> void:
	var controller := _get_controller(target)
	if controller:
		controller.push_behavior(behavior, duration)

func pop_behavior(target: String, behavior: Object) -> void:
	var controller := _get_controller(target)
	if controller:
		controller.pop_behavior(behavior)

func _get_controller(target: String) -> Node:
	if target == TARGET_MAIN:
		return _main_controller
	if target == TARGET_PHOTO:
		return _photo_controller
	return null

func _on_push_requested(target: String, behavior: Object) -> void:
	push_behavior(target, behavior)

func _on_pop_requested(target: String, behavior: Object) -> void:
	pop_behavior(target, behavior)
