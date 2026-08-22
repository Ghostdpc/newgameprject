## 職責：猛獸派對式軟糯效果驗證 Demo —— Spring Bone 彈簧骨骼二次動畫
##
## 架構（雙骨架，動畫目標不被污染）：
##   - DriverModel（隱藏）：AnimationPlayer 播走路動畫 → 純動畫基準
##   - RenderModel（可見）：每幀把「彈簧骨骼結果」寫入其骨架 → mesh 軟糯跟隨
##   - 無 RigidBody / 無關節 / 無物理引擎：純數學彈簧-阻尼二次動畫
##
## 原理：
##   每根骨一個旋轉彈簧（剛度 k / 阻尼 d），目標 = 動畫局部旋轉。
##   動畫走動時骨骼目標改變 → 彈簧滯後 → 過衝回彈 → 軟糯甩動。
##   胯/胸高剛度（主體穩），頭/四肢低剛度（軟糯）。
##   根節點加速度注入擺動激勵 → 走/停有慣性甩動。
##   永不坍塌、無 60Hz 離散震盪（純連續積分）。
##
## 按鍵：WASD 移動/轉向 Space 跳
##   1 = 純動畫  2 = 軟糯  3 = 大軟糯
##   F2 = 骨骼可視化（青=動畫基準，橙=渲染骨架）
##   R = 重置

class_name ActiveRagdollDemo
extends CharacterBody3D

const GRAVITY: float = 20.0
const MOVE_SPEED: float = 2.2
const ACCELERATION: float = 10.0
const JUMP_VELOCITY: float = 7.0
const TURN_SPEED: float = 10.0
const ANIM_SPEED_FACTOR: float = 0.9
const ANIM_WALK: String = "Walking_A"

const BONES: Array[String] = [
	"hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l", "upperleg.r", "lowerleg.r",
]
const DRAW_EDGES: Array = [
	["hips", "spine"], ["spine", "chest"], ["chest", "head"],
	["chest", "upperarm.l"], ["upperarm.l", "lowerarm.l"],
	["chest", "upperarm.r"], ["upperarm.r", "lowerarm.r"],
	["hips", "upperleg.l"], ["upperleg.l", "lowerleg.l"],
	["hips", "upperleg.r"], ["upperleg.r", "lowerleg.r"],
]

enum Mode { ANIM, SOFT, SOFT_STRONG }

var _driver_model: Node3D
var _render_model: Node3D
var _driver_skel: Skeleton3D
var _render_skel: Skeleton3D
var _driver_anim: AnimationPlayer
var _mode: Mode = Mode.ANIM
var _preset: String = "normal"
var _hint: Label
var _jump_requested: bool = false
var _show_debug: bool = false
var _debug_mesh: MeshInstance3D
var _debug_mat: StandardMaterial3D
var _debug_anim_mat: StandardMaterial3D

## 彈簧骨骼組件（使用統一封裝，參數記錄在 spring_bone_rig.gd）
var _spring: SpringBoneRig

func _ready() -> void:
	_driver_model = $DriverModel
	_render_model = $RenderModel
	_hint = get_node_or_null("../UILayer/Hint") as Label
	_driver_model.visible = false
	_driver_skel = _find_skeleton(_driver_model)
	_render_skel = _find_skeleton(_render_model)
	_driver_anim = _find_animation_player(_driver_model)
	if not _driver_skel or not _render_skel or not _driver_anim:
		push_error("ActiveRagdollDemo: 模型缺骨架或動畫")
		return
	var render_anim := _find_animation_player(_render_model)
	if render_anim:
		render_anim.stop()
		render_anim.active = false
	_build_spring_rig()
	_set_looping(ANIM_WALK)
	_driver_anim.play(ANIM_WALK)
	_init_debug_overlay()
	_update_hint()

## 建立彈簧骨骼組件，綁定輸出骨架(Render)與目標動畫骨架(Driver)
func _build_spring_rig() -> void:
	_spring = SpringBoneRig.new()
	_spring.name = "SpringBoneRig"
	add_child(_spring)
	_spring.skeleton = _render_skel
	_spring.target_skeleton = _driver_skel
	_spring.animation_player = _driver_anim
	# 套用「常态」預設（後續以此為基準調軟糯）
	_spring.apply_preset("normal")
	_spring.setup(_render_skel, _driver_anim)

func _init_debug_overlay() -> void:
	_debug_mat = StandardMaterial3D.new()
	_debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_mat.albedo_color = Color(1.0, 0.6, 0.0, 1.0)
	_debug_mat.no_depth_test = true
	_debug_anim_mat = StandardMaterial3D.new()
	_debug_anim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_anim_mat.albedo_color = Color(0.5, 1.0, 1.0, 1.0)
	_debug_anim_mat.no_depth_test = true
	_debug_mesh = MeshInstance3D.new()
	_debug_mesh.name = "DebugSpringBones"
	_debug_mesh.mesh = ImmediateMesh.new()
	_debug_mesh.visible = false
	add_child(_debug_mesh)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2:
			_show_debug = not _show_debug
			if _debug_mesh:
				_debug_mesh.visible = _show_debug
			_update_hint()
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_1: _set_mode(Mode.ANIM)
			KEY_2: _set_mode(Mode.SOFT)
			KEY_3: _set_mode(Mode.SOFT_STRONG)
			KEY_4: _apply_preset("kowtow")
			KEY_5: _apply_preset("normal")
			KEY_6: _apply_preset("jello")
			KEY_EQUAL, KEY_KP_ADD: _nudge_head_k(8.0)
			KEY_MINUS, KEY_KP_SUBTRACT: _nudge_head_k(-8.0)
			KEY_BRACKETRIGHT: _nudge_pulse(0.05)
			KEY_BRACKETLEFT: _nudge_pulse(-0.05)
			KEY_SPACE: _jump_requested = true
			KEY_R: _reset()

func _physics_process(delta: float) -> void:
	_move_body(delta)
	_update_hint()
	if not _render_skel or not _driver_anim:
		return
	if _driver_anim.is_playing():
		_driver_anim.advance(delta)
	if _spring:
		_spring.velocity_hints = Vector2(velocity.x, velocity.z)
		_spring.root_velocity = velocity
	# 彈簧模式 → 組件在自身 _physics_process 寫 render 骨架；
	# 純動畫 → 關組件 + 拷貝 driver pose 到 render
	if _mode == Mode.ANIM or not _spring:
		if _spring:
			_spring.set_active(false)
		_copy_anim_to_render()
	if _show_debug and _debug_mesh:
		_rebuild_debug_lines()

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
		var target_yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, TURN_SPEED * delta))
	if _jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_requested = false
	move_and_slide()
	_update_anim()

func _key_down(key: Key) -> bool:
	return Input.is_key_pressed(key) or Input.is_physical_key_pressed(key)

func _update_anim() -> void:
	if not _driver_anim:
		return
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if _driver_anim.current_animation != ANIM_WALK:
		_driver_anim.play(ANIM_WALK)
	var rate := clampf(0.15 + h_speed / MOVE_SPEED * ANIM_SPEED_FACTOR, 0.15, 2.0)
	if not is_equal_approx(_driver_anim.speed_scale, rate):
		_driver_anim.speed_scale = rate

func _set_mode(m: Mode) -> void:
	_mode = m
	if _spring:
		_spring.set_active(m != Mode.ANIM)
		_spring.wobble_scale = 1.0 if m == Mode.SOFT else 1.8
	_update_hint()

## 切換命名的彈簧預設（kowtow 特殊 / normal 常态 / jello 果凍）
func _apply_preset(name: String) -> void:
	_preset = name
	if _spring:
		_spring.apply_preset(name)
	if _mode != Mode.ANIM and _spring:
		_spring.set_active(true)
	_update_hint()

## 微調 head 骨剛度（自定義常态手感用）
func _nudge_head_k(dk: float) -> void:
	if not _spring:
		return
	var k: Dictionary = _spring.spring_k.duplicate()
	k["head"] = maxf(k.get("head", 70.0) + dk, 15.0)
	_spring.spring_k = k
	_preset = "custom"
	_update_hint()

## 微調步頻正弦幅度
func _nudge_pulse(dp: float) -> void:
	if not _spring:
		return
	_spring.pulse_amp = clampf(_spring.pulse_amp + dp, 0.0, 3.0)
	_preset = "custom"
	_update_hint()

## 純動畫：直接把 Driver 局部 pose 複製到 Render 骨架
func _copy_anim_to_render() -> void:
	for bone_name in BONES:
		var idx := _render_skel.find_bone(bone_name)
		var d_idx := _driver_skel.find_bone(bone_name)
		if idx == -1 or d_idx == -1:
			continue
		_render_skel.set_bone_pose_rotation(idx, _driver_skel.get_bone_pose_rotation(d_idx))
	_render_skel.force_update_all_bone_transforms()

## F2 可視化：青=動畫基準骨架，橙=渲染骨架
func _rebuild_debug_lines() -> void:
	var imm: ImmediateMesh = _debug_mesh.mesh as ImmediateMesh
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _debug_anim_mat)
	for e in DRAW_EDGES:
		var a_idx := _driver_skel.find_bone(e[0])
		var b_idx := _driver_skel.find_bone(e[1])
		if a_idx == -1 or b_idx == -1:
			continue
		imm.surface_add_vertex(_driver_skel.global_transform * _driver_skel.get_bone_global_pose(a_idx).origin)
		imm.surface_add_vertex(_driver_skel.global_transform * _driver_skel.get_bone_global_pose(b_idx).origin)
	imm.surface_end()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _debug_mat)
	for e in DRAW_EDGES:
		var a_idx := _render_skel.find_bone(e[0])
		var b_idx := _render_skel.find_bone(e[1])
		if a_idx == -1 or b_idx == -1:
			continue
		imm.surface_add_vertex(_render_skel.global_transform * _render_skel.get_bone_global_pose(a_idx).origin)
		imm.surface_add_vertex(_render_skel.global_transform * _render_skel.get_bone_global_pose(b_idx).origin)
	imm.surface_end()

func _reset() -> void:
	_mode = Mode.ANIM
	if _spring:
		_spring.set_active(false)
		_spring.setup(_render_skel, _driver_anim)
	_driver_anim.play(ANIM_WALK)
	_update_hint()

func _set_looping(anim_name: String) -> void:
	if _driver_anim and _driver_anim.has_animation(anim_name):
		_driver_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

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
	var names := {Mode.ANIM: "1=動畫", Mode.SOFT: "2=軟糯", Mode.SOFT_STRONG: "3=大軟糯"}
	var dbg := "F2骨骼線開" if _show_debug else "F2骨骼線關"
	var k_head := 0.0
	var pa := 0.0
	if _spring:
		k_head = _spring.spring_k.get("head", 0.0)
		pa = _spring.pulse_amp
	_hint.text = "[%s|%s] kHead=%.0f pulse=%.2f | %s\n4/5/6預設 kowtow/normal/jello  +/-調kHead  [ ]調pulse  WASD R" % [names.get(_mode, "?"), _preset, k_head, pa, dbg]
