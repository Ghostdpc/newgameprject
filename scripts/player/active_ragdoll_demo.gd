## 職責：Active Ragdoll（主動布娃娃）技術驗證 Demo —— 完全自建版
##
## 結構（雙骨架）：
##   DriverModel   = 動畫播放器驅動的「目標骨架」（隱藏）
##   RenderModel   = 可見骨架（mesh），由物理剛體鏈驅動
##   物理鏈 = 每根目標骨一個 RigidBody3D + Generic6DOFJoint3D（球窩）
##
## 原理：動畫只提供「目標姿態」，每幀對每根物理骨施加虛擬肌肉
##   扭矩 = stiffness×(姿態誤差) + damping×(角速度誤差)
##   再把手動施加後的剛體位姿寫回 Render 骨架 → mesh 全程跟物理，軟糯有肉感
##
## 控制：WASD 移動 / Space 跳 / R 重置
## 模式：1=FOLLOW(肌肉力強) 2=RELAXED(力≈0癱軟) 3=SPRING(力回漲彈簧爬起)
## 4=切換走路/站立動畫

class_name ActiveRagdollDemo
extends CharacterBody3D

enum Mode { FOLLOW, RELAXED, SPRING }

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 3.5
const ACCELERATION: float = 12.0
const JUMP_VELOCITY: float = 7.0
const TURN_SPEED: float = 10.0    ## 轉向插值速率
const ANIM_SPEED_FACTOR: float = 1.6  ## 走動畫隨速度變速的倍率

@export var stiffness_follow: float = 35.0
@export var damping_follow: float = 6.0
@export var stiffness_spring: float = 120.0
@export var damping_spring: float = 10.0
@export var strength_relaxed: float = 0.8

## 位置肌肉 PD 參數（N/m，軟跟隨動畫，阻尼高防抖）
@export var pos_kp: float = 20.0
@export var pos_kd: float = 12.0
## 旋轉肌肉 PD 參數（Nm/rad，軟跟隨）
@export var rot_kp: float = 18.0
@export var rot_kd: float = 8.0
@export var max_force: float = 40.0
@export var max_torque: float = 20.0

## 骨骼樹：name -> parent
const BONE_TREE: Dictionary = {
	"hips": "root", "spine": "hips", "chest": "spine", "head": "chest",
	"upperarm.l": "chest", "lowerarm.l": "upperarm.l",
	"upperarm.r": "chest", "lowerarm.r": "upperarm.r",
	"upperleg.l": "hips", "lowerleg.l": "upperleg.l",
	"upperleg.r": "hips", "lowerleg.r": "upperleg.r",
}
const LEAD_BONES: Array[String] = [
	"spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l", "upperleg.r", "lowerleg.r",
]

const ANIM_WALK: String = "Walking_A"
const ANIM_IDLE: String = "T-Pose"

var _driver_model: Node3D
var _render_model: Node3D
var _driver_skel: Skeleton3D
var _render_skel: Skeleton3D
var _driver_anim: AnimationPlayer
var _anchor: RigidBody3D
var _bodies: Dictionary = {}        # bone_name -> RigidBody3D
var _anim_targets: Dictionary = {}  # bone_name -> Transform3D(動畫當前全局位姿)
var _prev_force: Dictionary = {}    # bone_name -> Vector3 平滑肌肉力
var _prev_torque: Dictionary = {}   # bone_name -> Vector3 平滑肌肉力矩
var _mode: Mode = Mode.FOLLOW
var _hint: Label
var _use_walk: bool = true
var _jump_requested: bool = false

func _ready() -> void:
	_driver_model = $DriverModel
	_render_model = $RenderModel
	_hint = get_node_or_null("../UILayer/Hint") as Label
	_driver_model.visible = false
	_driver_skel = _find_skeleton(_driver_model)
	_render_skel = _find_skeleton(_render_model)
	_driver_anim = _find_animation_player(_driver_model)
	if not _driver_skel or not _render_skel or not _driver_anim:
		push_error("ActiveRagdollDemo: 模型缺 Skeleton3D 或 AnimationPlayer")
		return
	_build_chain()
	_set_looping(ANIM_WALK)
	_driver_anim.play(ANIM_WALK)
	_update_hint()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_mode(Mode.FOLLOW)
			KEY_2: _set_mode(Mode.RELAXED)
			KEY_3: _set_mode(Mode.SPRING)
			KEY_SPACE: _jump_requested = true
			KEY_R: _reset()

func _physics_process(delta: float) -> void:
	_move_body(delta)
	if not _render_skel:
		return
	_sample_targets()
	_tick_muscles(delta)
	_write_back_mesh()

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
	# 轉向：面向移動方向（模型前 = -Z），平滑插值
	if dir.length() > 0.01:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 10.0 * delta))
	if _jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_requested = false
	move_and_slide()
	_update_anim(delta)

## 雙通道按鍵檢測：兼容輸入法/鍵盤佈局（邏輯鍵 or 物理鍵）
func _key_down(key: Key) -> bool:
	return Input.is_key_pressed(key) or Input.is_physical_key_pressed(key)

## 依速度切換動畫（走/站），並按速度變速播放 → 動畫隨移動變化
func _update_anim(_delta: float) -> void:
	if not _driver_anim:
		return
	var h_speed := Vector2(velocity.x, velocity.z).length()
	var moving := h_speed > 0.2
	var want := ANIM_WALK if moving else ANIM_IDLE
	if _driver_anim.current_animation != want:
		_driver_anim.play(want)
	if moving:
		var speed := clampf(h_speed / MOVE_SPEED * ANIM_SPEED_FACTOR, 0.4, 2.0)
		if _driver_anim.speed_scale != speed:
			_driver_anim.speed_scale = speed

func _set_mode(m: Mode) -> void:
	_mode = m
	# 骨盆錨點：FOLLOW/SPRING 凍結跟 body（站），RELAXED 解凍（癱）
	if _anchor:
		_anchor.freeze = (m != Mode.RELAXED)
	_update_hint()

## 構建物理鏈：每根目標骨一個 RigidBody，6DOF 球窩連父體
## hips 錨點：凍結跟 body（站姿）；RELAXED 時解凍 → 全身癱軟
func _build_chain() -> void:
	_anchor = _make_body("hips", 2.0)
	_anchor.freeze = true
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	_render_skel.add_child(_anchor)
	_bodies["hips"] = _anchor

	for bone_name in LEAD_BONES:
		var parent_name: String = BONE_TREE[bone_name]
		var bone_idx := _driver_skel.find_bone(bone_name)
		if bone_idx == -1:
			push_warning("ActiveRagdollDemo: bone '%s' not found" % bone_name)
			continue
		var body := _make_body(bone_name, 0.5)
		var r_gt: Transform3D = _render_skel.get_bone_global_rest(_render_skel.find_bone(bone_name))
		body.position = r_gt.origin
		body.basis = r_gt.basis
		_render_skel.add_child(body)
		_bodies[bone_name] = body
		_attach_joint(body, parent_name)

## 建立一個 RigidBody（質量/形狀/碰撞）
## 骨間不碰撞（mask 不含 4），只碰地面(1) —— active ragdoll 標準做法，
## 形狀由 joint 鏈約束，避免各骨自我互頂把身體頂亂
func _make_body(bone_name: String, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "AB_" + bone_name
	body.mass = mass
	body.can_sleep = false
	body.linear_damp = 0.5
	body.angular_damp = 0.1
	body.collision_layer = 4
	body.collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.07
	shape.height = _bone_length(bone_name)
	var coll := CollisionShape3D.new()
	coll.shape = shape
	body.add_child(coll)
	return body

## 6DOF 球窩：旋轉自由，線性鬆約束（允許小幅伸縮，由位置肌肉維持形狀）
func _attach_joint(body: RigidBody3D, parent_bone: String) -> void:
	var parent_body: RigidBody3D = _bodies.get(parent_bone)
	if not parent_body:
		return
	var joint := Generic6DOFJoint3D.new()
	joint.name = "Joint_" + body.name
	var idx := _render_skel.find_bone(body.name.trim_prefix("AB_"))
	if idx != -1:
		joint.position = _render_skel.get_bone_global_rest(idx).origin
	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_" + axis + "/enabled", true)
		joint.set("linear_limit_" + axis + "/upper_distance", 0.4)
		joint.set("linear_limit_" + axis + "/lower_distance", -0.4)
	joint.set_node_a(body.get_path())
	joint.set_node_b(parent_body.get_path())
	_render_skel.add_child(joint)

## 採樣動畫目標位姿（Driver 骨架，動畫每幀更新）
## 目標 = 骨架全局變換 × 骨全局姿勢（世界座標）
## hips 錨點（凍結時）直接跟動畫 hips 位姿 → body 站
func _sample_targets() -> void:
	_anim_targets.clear()
	for bone_name in _bodies.keys():
		var idx := _driver_skel.find_bone(bone_name)
		if idx == -1:
			continue
		_anim_targets[bone_name] = _driver_skel.global_transform * _driver_skel.get_bone_global_pose(idx)
	if _anchor and _anchor.freeze:
		var hips_idx := _driver_skel.find_bone("hips")
		if hips_idx != -1:
			_anchor.global_transform = _driver_skel.global_transform * _driver_skel.get_bone_global_pose(hips_idx)

## 虛擬肌肉（PD 控制器）：每根物理體往動畫目標姿態拉（位置 + 旋轉）
## force = kp*err - kd*vel；輸出經指數低通濾波 → 平滑跟隨、防抽搐
func _tick_muscles(delta: float) -> void:
	var kp := pos_kp
	var kd := pos_kd
	var rkp := rot_kp
	var rkd := rot_kd
	match _mode:
		Mode.RELAXED:
			kp *= strength_relaxed
			kd = 2.0
			rkp *= strength_relaxed
			rkd = 1.0
		Mode.SPRING:
			kp = stiffness_spring * 0.3
			kd = damping_spring
			rkp = stiffness_spring * 0.3
			rkd = damping_spring
	# 濾波係數（0~1，越小越平滑越軟；≈1 越硬跟越快）
	var smooth := clampf(1.0 - 20.0 * delta, 0.0, 1.0)
	for bone_name in _bodies.keys():
		var body: RigidBody3D = _bodies.get(bone_name)
		var target: Transform3D = _anim_targets.get(bone_name)
		if not body or target == null:
			continue
		var cur := body.global_transform
		# 旋轉肌肉（往動畫姿態，限幅 + 平滑）
		var torque := Vector3.ZERO
		var rel := cur.basis.inverse() * target.basis
		var q := rel.get_rotation_quaternion()
		var angle := q.get_angle()
		var axis := q.get_axis()
		if angle >= 0.001:
			torque = (axis * (rkp * angle) - body.angular_velocity * rkd).limit_length(max_torque)
		# 位置肌肉（往動畫位置，限幅 + 平滑）
		var err := target.origin - cur.origin
		var force := (err * kp - body.linear_velocity * kd).limit_length(max_force)
		# 低通濾波：與前幀力混合
		var pfx: Vector3 = _prev_force.get(bone_name, force)
		var ptx: Vector3 = _prev_torque.get(bone_name, torque)
		torque = ptx.lerp(torque, 1.0 - smooth)
		force = pfx.lerp(force, 1.0 - smooth)
		_prev_force[bone_name] = force
		_prev_torque[bone_name] = torque
		body.apply_torque(torque)
		body.apply_central_force(force)

## 把物理剛體位姿寫回 Render 骨架 → mesh 跟物理
func _write_back_mesh() -> void:
	var inv := _render_skel.global_transform.affine_inverse()
	for bone_name in _bodies.keys():
		var idx := _render_skel.find_bone(bone_name)
		if idx == -1:
			continue
		var body: RigidBody3D = _bodies[bone_name]
		_render_skel.set_bone_global_pose(idx, inv * body.global_transform)
	_render_skel.force_update_all_bone_transforms()

func _reset() -> void:
	if not _render_skel:
		return
	for bone_name in _bodies.keys():
		var body: RigidBody3D = _bodies[bone_name]
		var idx := _render_skel.find_bone(bone_name)
		if idx != -1:
			body.global_transform = _render_model.global_transform * _render_skel.get_bone_global_rest(idx)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	_mode = Mode.FOLLOW
	_use_walk = true
	_driver_anim.play(ANIM_WALK)
	_update_hint()

func _set_looping(anim_name: String) -> void:
	if _driver_anim and _driver_anim.has_animation(anim_name):
		_driver_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

func _bone_length(bone_name: String) -> float:
	var bone_idx := _render_skel.find_bone(bone_name)
	var parent_idx := _render_skel.get_bone_parent(bone_idx)
	if parent_idx == -1:
		return 0.3
	return maxf(_render_skel.get_bone_global_rest(bone_idx).origin.distance_to(_render_skel.get_bone_global_rest(parent_idx).origin), 0.1)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null

func _update_hint() -> void:
	var names := {Mode.FOLLOW: "1=FOLLOW 軟糯跟動畫", Mode.RELAXED: "2=RELAXED 癱軟", Mode.SPRING: "3=SPRING 彈簧爬起"}
	if _hint:
		_hint.text = "ActiveRagdollDemo | %s | WASD移動/轉向 Space跳 R重置" % names[_mode]
