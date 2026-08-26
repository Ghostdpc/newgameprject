## 职责：Spring Bone 弹簧骨骼组件 —— 把「软糯 / 海绵 / 磕头」式动画过滤效果
## 叠加到任意角色的骨骼上，可随时启用/停用，与主流程解耦。
##
## 用法：
##   1. 实例化此节点，挂到角色下（需含 Skeleton3D + AnimationPlayer）
##   2. setup(skeleton) 绑定骨架
##   3. 设定各骨弹簧参数（k 刚度 / d 阻尼 / w 激励强度）——预设为「头大幅摆动」状态
##   4. set_active(true) 开启：每帧读动画目标 → 弹簧滞后 → 写回骨架
##      set_active(false) 关闭：骨架回到纯动画
##
## 本组件是纯数学二次动画（无 RigidBody，无物理引擎），永不坍塌、无离散震荡。
## 也可不依赖 AnimationPlayer：demo 只做优雅降级（找不到动画播放器就只跟骨骼 rest）。
##
## 记录参数（当前「头摆动很厉害」的软糯手感）：
##   部位        k(刚度)  d(阻尼)  w(激励)
##   hips        350      18       0.0
##   spine       220      13       0.6
##   chest       150      9        1.2
##   head        70       5        1.6
##   upperarm    160      11       0.3
##   lowerarm    110      8        0.4
##   upperleg    180      12       0.3
##   lowerleg    120      8.5      0.4
##   激励：root 加速度 lean (pitch/roll) + 步频正弦仅给 head/chest/spine
##   低通：exp(-1.2 * delta)

class_name SpringBoneRig
extends Node3D

const HumanBoneMap = preload("res://scripts/player/human_bone_map.gd")

## 参与弹簧的骨骼（KayKit Mannequin 命名）。可自订全组。
@export var bones: Array[String] = [
	"hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l", "upperleg.r", "lowerleg.r",
]

## Human 骨架（骨骼.00x 无语义骨）时经映射解析；由外部在 setup 前设置
var is_human: bool = false

## ─── 命名预设 ─────────────────────────────────────────────────────────────
## 每个预设可被 apply_preset("名字") 套用，把 spring_k/d/wobble_force/pulse 等
## 一次性填好。预设只存数据，不改动 active 状态。
const PRESETS: Dictionary = {
	## 特殊效果：头大幅软糯（当时调出来「看起来像磕头」的参数）
	## 记录于 2026-08-22，demo active_ragdoll_demo 按 2 的状态
	"kowtow": {
		"k": {
			"hips": 350.0, "spine": 220.0, "chest": 150.0, "head": 70.0,
			"upperarm.l": 160.0, "lowerarm.l": 110.0,
			"upperarm.r": 160.0, "lowerarm.r": 110.0,
			"upperleg.l": 180.0, "lowerleg.l": 120.0,
			"upperleg.r": 180.0, "lowerleg.r": 120.0,
		},
		"d": {
			"hips": 18.0, "spine": 13.0, "chest": 9.0, "head": 5.0,
			"upperarm.l": 11.0, "lowerarm.l": 8.0,
			"upperarm.r": 11.0, "lowerarm.r": 8.0,
			"upperleg.l": 12.0, "lowerleg.l": 8.5,
			"upperleg.r": 12.0, "lowerleg.r": 8.5,
		},
		"w": {
			"hips": 0.0, "spine": 0.6, "chest": 1.2, "head": 1.6,
			"upperarm.l": 0.3, "lowerarm.l": 0.4,
			"upperarm.r": 0.3, "lowerarm.r": 0.4,
			"upperleg.l": 0.3, "lowerleg.l": 0.4,
			"upperleg.r": 0.3, "lowerleg.r": 0.4,
		},
		"pulse_bones": ["head", "chest", "spine"],
		"pulse_amp": 0.8,
		"extra_damp": 1.2,
		"speed_ref": 2.2,
	},
	## 常态预设：全身适度软糯（head.k=15, pulse=0.1 调定于 2026-08-22）
	"normal": {
		"k": {
			"hips": 350.0, "spine": 280.0, "chest": 200.0, "head": 15.0,
			"upperarm.l": 180.0, "lowerarm.l": 130.0,
			"upperarm.r": 180.0, "lowerarm.r": 130.0,
			"upperleg.l": 200.0, "lowerleg.l": 140.0,
			"upperleg.r": 200.0, "lowerleg.r": 140.0,
		},
		"d": {
			"hips": 20.0, "spine": 17.0, "chest": 13.0, "head": 9.0,
			"upperarm.l": 13.0, "lowerarm.l": 10.0,
			"upperarm.r": 13.0, "lowerarm.r": 10.0,
			"upperleg.l": 14.0, "lowerleg.l": 10.0,
			"upperleg.r": 14.0, "lowerleg.r": 10.0,
		},
		"w": {
			"hips": 0.0, "spine": 0.3, "chest": 0.6, "head": 0.8,
			"upperarm.l": 0.4, "lowerarm.l": 0.5,
			"upperarm.r": 0.4, "lowerarm.r": 0.5,
			"upperleg.l": 0.3, "lowerleg.l": 0.4,
			"upperleg.r": 0.3, "lowerleg.r": 0.4,
		},
		"pulse_bones": ["head", "chest", "spine"],
		"pulse_amp": 0.1,
		"extra_damp": 1.6,
		"speed_ref": 2.2,
		"breath_amp": 0.3,
		"breath_freq": 1.1,
	},
	## 果冻：比常态更软更甩（作对比用，非正式）
	"jello": {
		"k": {
			"hips": 260.0, "spine": 200.0, "chest": 140.0, "head": 10.0,
			"upperarm.l": 130.0, "lowerarm.l": 90.0,
			"upperarm.r": 130.0, "lowerarm.r": 90.0,
			"upperleg.l": 150.0, "lowerleg.l": 100.0,
			"upperleg.r": 150.0, "lowerleg.r": 100.0,
		},
		"d": {
			"hips": 16.0, "spine": 13.0, "chest": 10.0, "head": 5.0,
			"upperarm.l": 9.0, "lowerarm.l": 7.0,
			"upperarm.r": 9.0, "lowerarm.r": 7.0,
			"upperleg.l": 11.0, "lowerleg.l": 8.0,
			"upperleg.r": 11.0, "lowerleg.r": 8.0,
		},
		"w": {
			"hips": 0.0, "spine": 0.5, "chest": 1.0, "head": 1.2,
			"upperarm.l": 0.6, "lowerarm.l": 0.8,
			"upperarm.r": 0.6, "lowerarm.r": 0.8,
			"upperleg.l": 0.5, "lowerleg.l": 0.6,
			"upperleg.r": 0.5, "lowerleg.r": 0.6,
		},
		"pulse_bones": ["head", "chest", "spine"],
		"pulse_amp": 0.6,
		"extra_damp": 1.0,
		"speed_ref": 2.2,
	},
}

## 每根骨的弹簧刚度（大 = 硬，贴动画；小 = 软，甩动）
@export var spring_k: Dictionary = {
	"hips": 350.0, "spine": 220.0, "chest": 150.0, "head": 70.0,
	"upperarm.l": 160.0, "lowerarm.l": 110.0,
	"upperarm.r": 160.0, "lowerarm.r": 110.0,
	"upperleg.l": 180.0, "lowerleg.l": 120.0,
	"upperleg.r": 180.0, "lowerleg.r": 120.0,
}
## 阻尼
@export var spring_d: Dictionary = {
	"hips": 18.0, "spine": 13.0, "chest": 9.0, "head": 5.0,
	"upperarm.l": 11.0, "lowerarm.l": 8.0,
	"upperarm.r": 11.0, "lowerarm.r": 8.0,
	"upperleg.l": 12.0, "lowerleg.l": 8.5,
	"upperleg.r": 12.0, "lowerleg.r": 8.5,
}
## 激励强度（加速度 lean + 步频；头/胸最强→显眼软糯，四肢靠层级传递）
@export var wobble_force: Dictionary = {
	"hips": 0.0, "spine": 0.6, "chest": 1.2, "head": 1.6,
	"upperarm.l": 0.3, "lowerarm.l": 0.4,
	"upperarm.r": 0.3, "lowerarm.r": 0.4,
	"upperleg.l": 0.3, "lowerleg.l": 0.4,
	"upperleg.r": 0.3, "lowerleg.r": 0.4,
}
## 步频正弦只叠加到这些头/上躯干骨（有静止基线才看得出软糯）
@export var pulse_bones: Array[String] = ["head", "chest", "spine"]
## 步频正弦幅度；0 = 关闭步频（只靠加速度 lean）
@export var pulse_amp: float = 0.8
## 步频基准速度（满速=4步/秒）；按使用角色 MOVE_SPEED 设
@export var speed_ref: float = 2.2
## 呼吸/持续微晃幅度（永远生效，含静止）；0 = 关闭。头最明显→像猛兽派对站著也摇头晃脑
@export var breath_amp: float = 0.0
## 呼吸微晃频率（Hz，慢一点像自然摇摆）
@export var breath_freq: float = 1.1

## 全身激励放大（外部可调，用于加强/减弱整个软糯）
@export var wobble_scale: float = 1.0
## 额外阻尼（指数低通，大 = 更稳 / 过冲少，小 = 甩动多）
@export var extra_damp: float = 1.2

var skeleton: Skeleton3D
## 目标骨架（读动画/rest 作弹簧目标）；缺省 = skeleton
var target_skeleton: Skeleton3D
## 外部提供的水平速度（用于步频正弦相位）；无 = 0
var velocity_hints: Vector2 = Vector2.ZERO
## 外部提供的根节点速度（加速度 lean 用）；不设 = 0
var root_velocity: Vector3 = Vector3.ZERO
var animation_player: AnimationPlayer
var _active: bool = false
var active: bool:
	get:
		return _active
	set(v):
		if v == _active:
			return
		_active = v
		if v:
			_init_spring()
		else:
			_reset_to_animation()

var _spring_rot: Dictionary = {}
var _spring_vel: Dictionary = {}
var _ready_flag: bool = false
var _prev_velocity: Vector3 = Vector3.ZERO
var _time: float = 0.0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	process_priority = 100   # 在 AnimationPlayer(priority 0) 之后处理，确保写回不被动画覆盖
	_ensure_skeleton()

func _ensure_skeleton() -> void:
	if skeleton:
		return
	for child in get_children():
		var sk := _find_skeleton(child)
		if sk:
			skeleton = sk
			break

func _process(delta: float) -> void:
	if not active or not skeleton or not _ready_flag:
		return
	_tick_springs(delta)

## 绑定骨架；anim 可选（提供步频相位），无则只跟骨骼 rest 作目标
func setup(skel: Skeleton3D, anim: AnimationPlayer = null) -> void:
	skeleton = skel
	animation_player = anim
	process_priority = 100
	_init_spring()
	set_process(true)
	set_physics_process(false)

## 整体开启/关闭
func set_active(on: bool) -> void:
	active = on

## 重新初始化弹簧状态（对齐当前骨骼 pose）。布娃娃软倒/起身后骨骼姿态大变，
## 若不重设，_spring_rot 残留软倒前基于旧姿态的角度，会与服装头骨缩放叠加导致帽子漂走。
func reinit() -> void:
	_init_spring()

## 套用命名预设（见 PRESETS）。返回是否成功。
func apply_preset(preset_name: String) -> bool:
	var p: Dictionary = PRESETS.get(preset_name, {})
	if p.is_empty():
		push_warning("SpringBoneRig: unknown preset '%s'" % preset_name)
		return false
	spring_k = (p.get("k", spring_k) as Dictionary).duplicate()
	spring_d = (p.get("d", spring_d) as Dictionary).duplicate()
	wobble_force = (p.get("w", wobble_force) as Dictionary).duplicate()
	if p.has("pulse_bones"):
		var arr: Array = p.get("pulse_bones", []) as Array
		pulse_bones.clear()
		for s in arr:
			pulse_bones.append(str(s))
	pulse_amp = float(p.get("pulse_amp", pulse_amp))
	extra_damp = float(p.get("extra_damp", extra_damp))
	speed_ref = float(p.get("speed_ref", speed_ref))
	breath_amp = float(p.get("breath_amp", breath_amp))
	breath_freq = float(p.get("breath_freq", breath_freq))
	# 切换参数后重取样，避免弹簧用旧参数跳变
	if _ready_flag:
		_init_spring()
	return true

## 采样：从骨架当前实际姿态初始化弹簧，避免开启刹那跳变
func _init_spring() -> void:
	_spring_rot.clear()
	_spring_vel.clear()
	if not skeleton:
		return
	for bone_name in bones:
		var idx := _fb(bone_name)
		if idx == -1:
			continue
		_spring_rot[bone_name] = skeleton.get_bone_pose_rotation(idx)
		_spring_vel[bone_name] = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	_ready_flag = true

## 依骨名找骨架索引（Human 经映射解析）
func _fb(bone_name: String) -> int:
	if not skeleton:
		return -1
	return skeleton.find_bone(HumanBoneMap.resolve(bone_name, is_human))

## 目标骨骼旋转：优先动画 pose，其次 rest（读自 target_skeleton，缺省 = skeleton）
func _target_rotation(bone_name: String) -> Quaternion:
	var src := target_skeleton if target_skeleton else skeleton
	var idx := _fb_in(src, bone_name)
	if idx == -1:
		return Quaternion.IDENTITY
	var q: Quaternion
	if animation_player and animation_player.is_playing():
		q = src.get_bone_pose_rotation(idx) as Quaternion
	else:
		q = src.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	return q

## 在指定骨架依骨名找索引（Human 经映射解析）
func _fb_in(src: Skeleton3D, bone_name: String) -> int:
	if not src:
		return -1
	return src.find_bone(HumanBoneMap.resolve(bone_name, is_human))

## 弹簧骨骼主回圈
func _tick_springs(delta: float) -> void:
	# 弹簧积分固定步长：显式欧拉在低帧率（双开/卡顿，delta 大）下会越过稳定性边界
	# （h*ω<2，ω=√k），导致弹簧自激振荡发散、骨骼乱颤。clamp 到 1/60 与 60fps 行为等价。
	var step := minf(delta, 1.0 / 60.0)
	_time += delta
	# 加速度 lean（用外部 root_velocity 差分，与原 demo 行为一致）
	var acc := (root_velocity - _prev_velocity) / maxf(delta, 0.0001)
	_prev_velocity = root_velocity
	var inv_basis := global_basis.inverse()
	var acc_local := inv_basis * acc
	var lean_pitch := clampf(-acc_local.z * 0.02, -0.12, 0.12)
	var lean_roll := clampf(acc_local.x * 0.02, -0.12, 0.12)

	# 步频正弦（与原 demo：h_speed>0.3 才触发，步频随速度线性）
	var step_swing: float = 0.0
	if pulse_amp > 0.0 and animation_player and animation_player.is_playing():
		var h_speed := velocity_hints.length()
		if h_speed > 0.3:
			var step_freq: float = h_speed / speed_ref * 4.0
			step_swing = sin(animation_player.current_animation_position * step_freq) * pulse_amp

	# 呼吸/持续微晃（含静止）；低速慢正弦，头甩最明显
	# 立体：pitch(前后) 为主，roll(左右) 次之且错相，微 yaw(扭转)
	var breath_pitch: float = 0.0
	var breath_roll: float = 0.0
	var breath_yaw: float = 0.0
	if breath_amp > 0.0:
		breath_pitch = sin(_time * TAU * breath_freq) * breath_amp
		breath_roll = sin(_time * TAU * breath_freq * 0.83 + 1.3) * breath_amp * 0.7
		breath_yaw = sin(_time * TAU * breath_freq * 0.61 + 2.6) * breath_amp * 0.4

	for bone_name in bones:
		var idx := _fb(bone_name)
		if idx == -1:
			continue
		var k: float = spring_k.get(bone_name, 200.0)
		var damp: float = spring_d.get(bone_name, 12.0)
		var wf: float = wobble_force.get(bone_name, 0.5)
		var target := _target_rotation(bone_name)
		# 三轴激励：pitch=前后点头 / roll=左右摇摆 / yaw=扭转
		var pulse_extra := step_swing if pulse_bones.has(bone_name) else 0.0
		var excite_pitch := (lean_pitch + pulse_extra) * wf + breath_pitch * wf
		var excite_roll := lean_roll * wf * 0.5 + breath_roll * wf
		var excite_yaw := breath_yaw * wf
		excite_pitch *= wobble_scale
		excite_roll *= wobble_scale
		excite_yaw *= wobble_scale
		# excite_q 用骨骼局部轴施加激励。预设(mannequin) head 局部轴与世界对齐：
		#   pitch点头=绕worldX(左右) → 用 localX(RIGHT)；roll左右摇=绕worldZ(前后) → localZ；
		#   yaw转体=绕worldY(竖直) → localY(UP)。
		# human 骨架因额外 Y 旋转/轴转换，head 局部轴相对世界旋转了：
		#   localX→world+Z、localY→world+Y、localZ→world-X。
		#   故要对齐世界语义需：pitch→绕 localZ(-X)、roll→绕 localX(+Z)、yaw→绕 localY(+Y)。
		#   即human下互换 pitch/roll 轴。
		var pitch_axis := Vector3.RIGHT
		var roll_axis := Vector3(0, 0, 1)
		var yaw_axis := Vector3.UP
		if is_human:
			pitch_axis = Vector3(0, 0, -1)   # 世界-X → 点头
			roll_axis = Vector3.RIGHT         # 世界+Z → 左右摇
			yaw_axis = Vector3.UP             # 世界+Y → 转体
		var excite_q := (Quaternion(pitch_axis, excite_pitch)
			* Quaternion(roll_axis, excite_roll)
			* Quaternion(yaw_axis, excite_yaw))
		var target_rot := (target * excite_q).normalized()

		var cur: Quaternion = _spring_rot.get(bone_name) as Quaternion
		var rel := cur.inverse() * target_rot
		var err_angle := rel.get_angle()
		var err_axis := rel.get_axis()
		var ang_acc := err_axis * (k * err_angle) - (_spring_vel.get(bone_name) as Vector3) * damp
		var vel: Vector3 = (_spring_vel.get(bone_name) as Vector3) + ang_acc * step
		vel *= exp(-extra_damp * step)
		_spring_vel[bone_name] = vel

		var ang: Vector3 = vel * step
		var dv := Quaternion.IDENTITY
		if ang.length() > 0.000001:
			dv = Quaternion(ang.normalized(), ang.length())
		cur = (cur * dv).normalized()
		_spring_rot[bone_name] = cur
		skeleton.set_bone_pose_rotation(idx, cur)
	skeleton.force_update_all_bone_transforms()

## 停用时：清空到纯动画，不残留弹簧姿态（避免角色永久弯著）
func _reset_to_animation() -> void:
	_spring_rot.clear()
	_spring_vel.clear()
	_ready_flag = false
	_prev_velocity = Vector3.ZERO

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null
