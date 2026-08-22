## 職責：官方 PhysicalBoneSimulator3D 方案的 Active Ragdoll 驗證 Demo
##
## 對比手寫物理鏈（set_bone_global_pose 不驅動 mesh → 失敗）：
## 官方 simulator 模擬時引擎直接把物理骨變換應用到骨架皮膚 → mesh 一定跟隨。
##
## 結構：
##   單一模型實例（動畫播放驅動 mesh）+ RagdollRig（建立/控制 PhysicalBone）
##   WASD 移動/轉向/跳，動畫隨速度切換 Walking/T-Pose
##   按鍵：
##     1 = 動畫模式（純動畫，mesh 跟動畫）
##     2 = 布娃娃（start_simulation 全骨物理 → mesh 真癱軟）
##     3 = 恢復站起（stop_simulation + 站起插值）
##     Space 跳 / R 重置
##
## 驗證目標：
##   a. 動畫播放時 mesh 正常跟隨（不再 idle）
##   b. 切 2 後 mesh 真的癱軟倒地（官方模擬生效）
##   c. 切 3 後從倒地平滑站起回動畫

class_name PhysicsRagdollDemo
extends CharacterBody3D

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 3.5
const ACCELERATION: float = 12.0
const JUMP_VELOCITY: float = 7.0
const TURN_SPEED: float = 10.0
const ANIM_SPEED_FACTOR: float = 1.6
const ANIM_WALK: String = "Walking_A"
const ANIM_IDLE: String = "T-Pose"

var _rig: RagdollRig
var _anim: AnimationPlayer
var _hint: Label
var _jump_requested: bool = false
var _was_ragdoll: bool = false

func _ready() -> void:
	_hint = get_node_or_null("../UILayer/Hint") as Label
	var model := $RigModel
	var skeleton := _find_skeleton(model)
	_anim = _find_animation_player(model)
	_rig = $RagdollRig as RagdollRig
	if not skeleton or not _anim or not _rig:
		push_error("PhysicsRagdollDemo: 缺骨架/動畫/rig")
		return
	_rig.setup(skeleton, _anim)
	_set_looping(ANIM_WALK)
	_anim.play(ANIM_WALK)
	_update_hint()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				# 純動畫
				_set_ragdoll(false)
				_anim.play(ANIM_WALK)
			KEY_2:
				# 低影響混合布娃娃：動畫+物理，走路帶軟糯感
				_rig.set_blended_simulation(0.35)
				_update_hint()
			KEY_3:
				# 全癱軟
				_set_ragdoll(true)
			KEY_SPACE: _jump_requested = true
			KEY_R: _reset()

func _physics_process(delta: float) -> void:
	_move_body(delta)
	_update_hint()
	if not _rig:
		return
	# ragdoll 開啟時動畫停、mesh 由物理接管；否則動畫驅動（AnimationPlayer 自身推進）
	if _rig.is_ragdoll_enabled():
		return
	_update_anim(delta)

func _set_ragdoll(enabled: bool) -> void:
	if not _rig:
		return
	_rig.set_ragdoll_enabled(enabled)
	if not enabled and _anim and not _rig.is_standing_up():
		_anim.play(ANIM_WALK)
	_update_hint()

func _move_body(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var dir := Vector3.ZERO
	if _key_down(KEY_W):
		dir.z -= 1.0
	if _key_down(KEY_S):
		dir.z += 1.0
	if _key_down(KEY_A):
		dir.x -= 1.0
	if _key_down(KEY_D):
		dir.x += 1.0
	dir = dir.normalized()
	velocity.x = move_toward(velocity.x, dir.x * MOVE_SPEED, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, dir.z * MOVE_SPEED, ACCELERATION * delta)
	if dir.length() > 0.01:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))
	if _jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_requested = false
	move_and_slide()

## 雙通道按鍵檢測：兼容輸入法/鍵盤佈局
func _key_down(key: Key) -> bool:
	return Input.is_key_pressed(key) or Input.is_physical_key_pressed(key)

## 依速度切換動畫（走/站），按速度變速
func _update_anim(_delta: float) -> void:
	if not _anim or _rig.is_ragdoll_enabled() or _rig.is_standing_up():
		return
	var h_speed := Vector2(velocity.x, velocity.z).length()
	var moving := h_speed > 0.2
	var want := ANIM_WALK if moving else ANIM_IDLE
	if _anim.current_animation != want:
		_anim.play(want)
	if moving:
		var speed := clampf(h_speed / MOVE_SPEED * ANIM_SPEED_FACTOR, 0.4, 2.0)
		if _anim.speed_scale != speed:
			_anim.speed_scale = speed

func _set_looping(anim_name: String) -> void:
	if _anim and _anim.has_animation(anim_name):
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func _reset() -> void:
	_set_ragdoll(false)
	_anim.play(ANIM_WALK)

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

func _update_hint() -> void:
	if not _hint:
		return
	var mode := "動畫" if not _rig or not _rig.is_ragdoll_enabled() else "布娃娃"
	var anim_info := "無"
	if _anim:
		anim_info = "%s @%.1f" % [_anim.current_animation, _anim.current_animation_position]
	var spd := Vector2(velocity.x, velocity.z).length()
	_hint.text = "PhysicsRagdollDemo [%s] anim=%s | 移動速度=%.1f | 1=動畫 2=布娃娃 3=站起 WASD Space R" % [mode, anim_info, spd]
