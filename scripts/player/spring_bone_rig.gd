## 職責：Spring Bone 彈簧骨骼組件 —— 把「軟糯 / 海綿 / 磕頭」式動畫過濾效果
## 疊加到任意角色的骨骼上，可隨時啟用/停用，與主流程解耦。
##
## 用法：
##   1. 實例化此節點，掛到角色下（需含 Skeleton3D + AnimationPlayer）
##   2. setup(skeleton) 綁定骨架
##   3. 設定各骨彈簧參數（k 剛度 / d 阻尼 / w 激勵強度）——預設為「頭大幅擺動」狀態
##   4. set_active(true) 開啟：每幀讀動畫目標 → 彈簧滯後 → 寫回骨架
##      set_active(false) 關閉：骨架回到純動畫
##
## 本組件是純數學二次動畫（無 RigidBody，無物理引擎），永不坍塌、無離散震盪。
## 也可不依賴 AnimationPlayer：demo 只做優雅降級（找不到動畫播放器就只跟骨骼 rest）。
##
## 記錄參數（當前「頭擺動很厲害」的軟糯手感）：
##   部位        k(剛度)  d(阻尼)  w(激勵)
##   hips        350      18       0.0
##   spine       220      13       0.6
##   chest       150      9        1.2
##   head        70       5        1.6
##   upperarm    160      11       0.3
##   lowerarm    110      8        0.4
##   upperleg    180      12       0.3
##   lowerleg    120      8.5      0.4
##   激勵：root 加速度 lean (pitch/roll) + 步頻正弦僅給 head/chest/spine
##   低通：exp(-1.2 * delta)

class_name SpringBoneRig
extends Node3D

## 參與彈簧的骨骼（KayKit Mannequin 命名）。可自訂全組。
@export var bones: Array[String] = [
	"hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l", "upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l", "upperleg.r", "lowerleg.r",
]

## ─── 命名預設 ─────────────────────────────────────────────────────────────
## 每個預設可被 apply_preset("名字") 套用，把 spring_k/d/wobble_force/pulse 等
## 一次性填好。預設只存數據，不改動 active 狀態。
const PRESETS: Dictionary = {
	## 特殊效果：頭大幅軟糯（當時調出來「看起來像磕頭」的參數）
	## 記錄於 2026-08-22，demo active_ragdoll_demo 按 2 的狀態
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
	## 常态預設：全身適度軟糯（head.k=15, pulse=0.1 調定於 2026-08-22）
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
	## 果凍：比常态更軟更甩（作對比用，非正式）
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

## 每根骨的彈簧剛度（大 = 硬，貼動畫；小 = 軟，甩動）
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
## 激勵強度（加速度 lean + 步頻；頭/胸最強→顯眼軟糯，四肢靠層級傳遞）
@export var wobble_force: Dictionary = {
	"hips": 0.0, "spine": 0.6, "chest": 1.2, "head": 1.6,
	"upperarm.l": 0.3, "lowerarm.l": 0.4,
	"upperarm.r": 0.3, "lowerarm.r": 0.4,
	"upperleg.l": 0.3, "lowerleg.l": 0.4,
	"upperleg.r": 0.3, "lowerleg.r": 0.4,
}
## 步頻正弦只疊加到這些頭/上軀幹骨（有靜止基線才看得出軟糯）
@export var pulse_bones: Array[String] = ["head", "chest", "spine"]
## 步頻正弦幅度；0 = 關閉步頻（只靠加速度 lean）
@export var pulse_amp: float = 0.8
## 步頻基準速度（滿速=4步/秒）；按使用角色 MOVE_SPEED 設
@export var speed_ref: float = 2.2
## 呼吸/持續微晃幅度（永遠生效，含靜止）；0 = 關閉。頭最明顯→像猛獸派對站著也搖頭晃腦
@export var breath_amp: float = 0.0
## 呼吸微晃頻率（Hz，慢一點像自然搖擺）
@export var breath_freq: float = 1.1

## 全身激勵放大（外部可調，用於加強/減弱整個軟糯）
@export var wobble_scale: float = 1.0
## 額外阻尼（指數低通，大 = 更穩 / 過衝少，小 = 甩動多）
@export var extra_damp: float = 1.2

var skeleton: Skeleton3D
## 目標骨架（讀動畫/rest 作彈簧目標）；缺省 = skeleton
var target_skeleton: Skeleton3D
## 外部提供的水平速度（用於步頻正弦相位）；無 = 0
var velocity_hints: Vector2 = Vector2.ZERO
## 外部提供的根節點速度（加速度 lean 用）；不設 = 0
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
	process_priority = 100   # 在 AnimationPlayer(priority 0) 之後處理，確保寫回不被動畫覆蓋
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

## 綁定骨架；anim 可選（提供步頻相位），無則只跟骨骼 rest 作目標
func setup(skel: Skeleton3D, anim: AnimationPlayer = null) -> void:
	skeleton = skel
	animation_player = anim
	process_priority = 100
	_init_spring()
	set_process(true)
	set_physics_process(false)

## 整體開啟/關閉
func set_active(on: bool) -> void:
	active = on

## 套用命名預設（見 PRESETS）。返回是否成功。
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
	# 切換參數後重取樣，避免彈簧用舊參數跳變
	if _ready_flag:
		_init_spring()
	return true

## 採樣：從骨架當前實際姿態初始化彈簧，避免開啟剎那跳變
func _init_spring() -> void:
	_spring_rot.clear()
	_spring_vel.clear()
	if not skeleton:
		return
	for bone_name in bones:
		var idx := skeleton.find_bone(bone_name)
		if idx == -1:
			continue
		_spring_rot[bone_name] = skeleton.get_bone_pose_rotation(idx)
		_spring_vel[bone_name] = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	_ready_flag = true

## 目標骨骼旋轉：優先動畫 pose，其次 rest（讀自 target_skeleton，缺省 = skeleton）
func _target_rotation(bone_name: String) -> Quaternion:
	var src := target_skeleton if target_skeleton else skeleton
	var idx := src.find_bone(bone_name)
	if idx == -1:
		return Quaternion.IDENTITY
	var q: Quaternion
	if animation_player and animation_player.is_playing():
		q = src.get_bone_pose_rotation(idx) as Quaternion
	else:
		q = src.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	return q

## 彈簧骨骼主迴圈
func _tick_springs(delta: float) -> void:
	_time += delta
	# 加速度 lean（用外部 root_velocity 差分，與原 demo 行為一致）
	var acc := (root_velocity - _prev_velocity) / maxf(delta, 0.0001)
	_prev_velocity = root_velocity
	var inv_basis := global_basis.inverse()
	var acc_local := inv_basis * acc
	var lean_pitch := clampf(-acc_local.z * 0.02, -0.12, 0.12)
	var lean_roll := clampf(acc_local.x * 0.02, -0.12, 0.12)

	# 步頻正弦（與原 demo：h_speed>0.3 才觸發，步頻隨速度線性）
	var step_swing: float = 0.0
	if pulse_amp > 0.0 and animation_player and animation_player.is_playing():
		var h_speed := velocity_hints.length()
		if h_speed > 0.3:
			var step_freq: float = h_speed / speed_ref * 4.0
			step_swing = sin(animation_player.current_animation_position * step_freq) * pulse_amp

	# 呼吸/持續微晃（含靜止）；低速慢正弦，頭甩最明顯
	# 立體：pitch(前後) 為主，roll(左右) 次之且錯相，微 yaw(扭轉)
	var breath_pitch: float = 0.0
	var breath_roll: float = 0.0
	var breath_yaw: float = 0.0
	if breath_amp > 0.0:
		breath_pitch = sin(_time * TAU * breath_freq) * breath_amp
		breath_roll = sin(_time * TAU * breath_freq * 0.83 + 1.3) * breath_amp * 0.7
		breath_yaw = sin(_time * TAU * breath_freq * 0.61 + 2.6) * breath_amp * 0.4

	for bone_name in bones:
		var idx := skeleton.find_bone(bone_name)
		if idx == -1:
			continue
		var k: float = spring_k.get(bone_name, 200.0)
		var damp: float = spring_d.get(bone_name, 12.0)
		var wf: float = wobble_force.get(bone_name, 0.5)
		var target := _target_rotation(bone_name)
		# 三軸激勵：pitch=前後點頭 / roll=左右搖擺 / yaw=扭轉
		var pulse_extra := step_swing if pulse_bones.has(bone_name) else 0.0
		var excite_pitch := (lean_pitch + pulse_extra) * wf + breath_pitch * wf
		var excite_roll := lean_roll * wf * 0.5 + breath_roll * wf
		var excite_yaw := breath_yaw * wf
		excite_pitch *= wobble_scale
		excite_roll *= wobble_scale
		excite_yaw *= wobble_scale
		var excite_q := (Quaternion(Vector3.RIGHT, excite_pitch)
			* Quaternion(Vector3(0, 0, 1), excite_roll)
			* Quaternion(Vector3.UP, excite_yaw))
		var target_rot := (target * excite_q).normalized()

		var cur: Quaternion = _spring_rot.get(bone_name) as Quaternion
		var rel := cur.inverse() * target_rot
		var err_angle := rel.get_angle()
		var err_axis := rel.get_axis()
		var ang_acc := err_axis * (k * err_angle) - (_spring_vel.get(bone_name) as Vector3) * damp
		var vel: Vector3 = (_spring_vel.get(bone_name) as Vector3) + ang_acc * delta
		vel *= exp(-extra_damp * delta)
		_spring_vel[bone_name] = vel

		var ang: Vector3 = vel * delta
		var dv := Quaternion.IDENTITY
		if ang.length() > 0.000001:
			dv = Quaternion(ang.normalized(), ang.length())
		cur = (cur * dv).normalized()
		_spring_rot[bone_name] = cur
		skeleton.set_bone_pose_rotation(idx, cur)
	skeleton.force_update_all_bone_transforms()

## 停用時：清空到純動畫，不殘留彈簧姿態（避免角色永久彎著）
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
