## 职责：玩家状态机，管理状态切换

class_name PlayerStateMachine
extends Node

var _states: Dictionary = {}
var _current_state: BaseState = null
var current_state_name: String = ""

func register_state(state_name: String, state: BaseState) -> void:
	_states[state_name] = state

func start(initial_state: String) -> void:
	transition_to(initial_state)

func transition_to(state_name: String) -> void:
	if state_name == current_state_name:
		return
	if not _states.has(state_name):
		push_error("PlayerStateMachine: unknown state '%s'" % state_name)
		return
	if _current_state:
		_current_state.exit()
	current_state_name = state_name
	_current_state = _states[state_name]
	_current_state.enter()

func update(delta: float) -> void:
	if _current_state:
		_current_state.update(delta)

func physics_update(delta: float) -> void:
	if _current_state:
		_current_state.physics_update(delta)

func get_current_state() -> BaseState:
	return _current_state

func get_state(state_name: String) -> BaseState:
	return _states.get(state_name, null)
