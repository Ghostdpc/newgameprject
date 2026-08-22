## 職責：Human 模型測試台 —— 驗證縮放/朝向/動畫是否正確
## WASD 移動、Space 跳躍。模型自動轉向移動方向，播放 Idle/Walk/jump。
class_name HumanDemoController
extends CharacterBody3D

const MODEL_PATH: String = "res://assets/models/human/human.fbx"
## human.fbx 原始高度約 4.456，縮放到 1.0m 精確係數
const MODEL_SCALE: float = 1.0 / 4.456
const MOVE_SPEED: float = 3.0
const JUMP_VELOCITY: float = 5.0
const TURN_RATE: float = 12.0

var _model: Node3D
var _anim: AnimationPlayer
var _yaw: float = 0.0
## 動畫真實名（後綴匹配找到後填入），key 用 Idle/Walk/jump
var _anim_names: Dictionary = {}
## 模型本體朝向補償（deg）。human 前向可能朝 +X 或 -X，用 Q/E 現場微調到朝 +Z
var _model_yaw_deg: float = 0.0

## 動畫名 → 是否循環（human 動畫全名帶「骨架|」前綴，這裡用後綴匹配）
const ANIM_SUFFIX: Dictionary = {
	"Idle": {"suffix": "Idle", "loop": true},
	"Walk": {"suffix": "Walk", "loop": true},
	"jump": {"suffix": "jump", "loop": false},
}

func _ready() -> void:
	collision_layer = 2
	var ps: PackedScene = load(MODEL_PATH)
	if not ps:
		push_error("HumanDemo: 載入模型失敗 " + MODEL_PATH)
		return
	_model = ps.instantiate()
	_model.name = "Model"
	add_child(_model)
	_model.scale = Vector3.ONE * MODEL_SCALE
	# 腳底對齊玩家根源（骨骼骨盆在模型內 y≈1.49，頂點腳底在 y=0）
	_model.position.y = 0.0
	_anim = _find_animation_player(_model)
	if not _anim:
		push_error("HumanDemo: 模型無 AnimationPlayer")
		return
	for key in ANIM_SUFFIX:
		var found := _find_anim_name(_anim, ANIM_SUFFIX[key].suffix)
		if found != "":
			_anim_names[key] = found
	_play_anim("Idle")

func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	dir = dir.normalized()

	# 重力
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	# 跳躍
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_play_anim("jump")

	var move := Vector3(dir.x, 0.0, dir.y)
	velocity.x = move.x * MOVE_SPEED
	velocity.z = move.z * MOVE_SPEED

	# Q/E 現場微調模型朝向（補償 human 前向與移動方向的偏差）
	if Input.is_key_pressed(KEY_Q):
		_model_yaw_deg += 3.0
	if Input.is_key_pressed(KEY_E):
		_model_yaw_deg -= 3.0
	if _model:
		_model.rotation.y = deg_to_rad(_model_yaw_deg)

	# 動畫狀態：空中播 jump，地面按移動播 Walk / Idle
	if not is_on_floor():
		_play_anim("jump")
	elif move.length_squared() > 0.001:
		var target_yaw := atan2(move.x, move.z)
		_yaw = lerp_angle(_yaw, target_yaw, minf(1.0, TURN_RATE * delta))
		rotation.y = _yaw
		_play_anim("Walk")
	else:
		_play_anim("Idle")

	move_and_slide()

func _play_anim(key: String) -> void:
	if not _anim:
		return
	if not _anim_names.has(key):
		return
	var nm: String = _anim_names[key]
	if _anim.current_animation == nm and _anim.is_playing():
		return
	_anim.play(nm)
	if ANIM_SUFFIX[key].loop:
		_anim.get_animation(nm).loop_mode = Animation.LOOP_LINEAR

func _find_anim_name(ap: AnimationPlayer, suffix: String) -> String:
	for an in ap.get_animation_list():
		if an.ends_with(suffix) or an.ends_with("|" + suffix):
			return an
	return ""

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null
