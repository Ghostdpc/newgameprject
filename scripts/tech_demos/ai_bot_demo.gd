## 職責：時間流速測試 AI 機器人 —— 左右來回移動 + 週期性飛撲
## 復用 SpringBoneRig 軟糯裝配（同 active_ragdoll_demo），由 AI 狀態機驅動移動。
## 目的：暫停 / 子弹時間下觀察 AI 動作（走路軟糯、飛撲空中停格）被時間流速影響。
##
## AI 狀態：WALK(左右來回) → DIVE(向前飛撲拋起) → RECOVER(落地站起) → WALK...
## 方向：飛撲朝當前移動方向衝刺。

class_name AiBotDemo
extends CharacterBody3D

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 2.2
const ACCELERATION: float = 8.0
const DIVE_SPEED: float = 8.0
const DIVE_UP: float = 4.0
const ANIM_SPEED_FACTOR: float = 0.9
const ANIM_WALK: String = "Walking_A"

const BONES: Array[String] = [
	"hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l", "upperleg.r", "lowerleg.r",
]

enum BotState { WALK, DIVE, RECOVER }

var _driver_model: Node3D
var _render_model: Node3D
var _driver_skel: Skeleton3D
var _render_skel: Skeleton3D
var _driver_anim: AnimationPlayer
var _spring: SpringBoneRig

var _state: BotState = BotState.WALK
var _move_dir: float = 1.0
@export var walk_left: float = -3.0
@export var walk_right: float = 3.0
var _next_dive_time: float = 3.0
var _dive_elapsed: float = 0.0
var _turn_scale: float = 6.0

func _ready() -> void:
	_driver_model = $DriverModel
	_render_model = $RenderModel
	_driver_model.visible = false
	_driver_skel = _find_skeleton(_driver_model)
	_render_skel = _find_skeleton(_render_model)
	_driver_anim = _find_animation_player(_driver_model)
	if not _driver_skel or not _render_skel or not _driver_anim:
		push_error("AiBotDemo: 模型缺骨架或動畫")
		return
	var render_anim := _find_animation_player(_render_model)
	if render_anim:
		render_anim.stop()
		render_anim.active = false
	_spring = SpringBoneRig.new()
	_spring.name = "SpringBoneRig"
	add_child(_spring)
	_spring.skeleton = _render_skel
	_spring.target_skeleton = _driver_skel
	_spring.animation_player = _driver_anim
	_spring.apply_preset("normal")
	_spring.setup(_render_skel, _driver_anim)
	_spring.set_active(true)
	if _driver_anim.has_animation(ANIM_WALK):
		_driver_anim.get_animation(ANIM_WALK).loop_mode = Animation.LOOP_LINEAR
	_driver_anim.play(ANIM_WALK)
	_next_dive_time = randf_range(2.0, 4.0)

func _physics_process(delta: float) -> void:
	match _state:
		BotState.WALK:
			_walk(delta)
		BotState.DIVE:
			_dive(delta)
		BotState.RECOVER:
			_recover(delta)
	if _spring:
		_spring.velocity_hints = Vector2(velocity.x, velocity.z)
		_spring.root_velocity = velocity

func _walk(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var dir := Vector3(_move_dir, 0.0, 0.0)
	velocity.x = move_toward(velocity.x, dir.x * MOVE_SPEED, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, dir.z * MOVE_SPEED, ACCELERATION * delta)
	_turn_toward(atan2(dir.x, dir.z), delta)
	_next_dive_time -= delta
	if _next_dive_time <= 0.0:
		_start_dive()
		return
	if global_position.x <= walk_left:
		_move_dir = 1.0
	elif global_position.x >= walk_right:
		_move_dir = -1.0
	move_and_slide()
	_update_anim()

func _start_dive() -> void:
	_state = BotState.DIVE
	_dive_elapsed = 0.0
	velocity.y = DIVE_UP
	velocity.x = _move_dir * DIVE_SPEED
	velocity.z = 0.0
	_next_dive_time = randf_range(2.5, 4.5)

func _dive(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	_dive_elapsed += delta
	if _dive_elapsed > 0.5:
		_state = BotState.RECOVER
	move_and_slide()

func _recover(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, 0.0, ACCELERATION * delta)
	if is_on_floor() and absf(velocity.x) < 0.1:
		_state = BotState.WALK
	move_and_slide()

func _turn_toward(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, _turn_scale * delta))

func _update_anim() -> void:
	if not _driver_anim:
		return
	if _driver_anim.current_animation != ANIM_WALK:
		_driver_anim.play(ANIM_WALK)
	var h_speed := Vector2(velocity.x, velocity.z).length()
	var rate := clampf(0.15 + h_speed / MOVE_SPEED * ANIM_SPEED_FACTOR, 0.15, 2.0)
	if not is_equal_approx(_driver_anim.speed_scale, rate):
		_driver_anim.speed_scale = rate

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var q := _find_skeleton(c)
		if q:
			return q
	return null

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var q := _find_animation_player(c)
		if q:
			return q
	return null
