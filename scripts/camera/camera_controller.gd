## 职责：相机控制器，管理行为堆叠并执行栈顶行为

class_name CameraController
extends Node

var _camera: Camera3D
var _behavior_stack: Array[CameraBehavior] = []
var _timers: Dictionary = {}

func init(camera: Camera3D) -> void:
	_camera = camera

func push_behavior(behavior: CameraBehavior, duration: float = 0.0) -> void:
	_behavior_stack.push_back(behavior)
	if duration > 0.0:
		_timers[behavior] = duration

func pop_behavior(behavior: CameraBehavior) -> void:
	_behavior_stack.erase(behavior)
	_timers.erase(behavior)

func _process(delta: float) -> void:
	_tick_timers(delta)
	if _camera and not _behavior_stack.is_empty():
		_behavior_stack.back().update(_camera, delta)

func _tick_timers(delta: float) -> void:
	var expired: Array = []
	for behavior in _timers:
		_timers[behavior] -= delta
		if _timers[behavior] <= 0.0:
			expired.append(behavior)
	for behavior in expired:
		pop_behavior(behavior)


func get_camera() -> Camera3D:
	return _camera

func get_render_viewport() -> Viewport:
	if _camera:
		return _camera.get_viewport()
	return null
