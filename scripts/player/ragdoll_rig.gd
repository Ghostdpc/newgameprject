## 職責：為現有骨架綁定布娃娃物理骨，提供 ragdoll 控制介面
## 對接 KayKit Mannequin 模型骨架

class_name RagdollRig
extends Node3D

# 參與 ragdoll 的主要骨骼（KayKit Mannequin 命名）
const RIG_BONES: Array[String] = [
	"hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l",
	"upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l",
	"upperleg.r", "lowerleg.r",
]

@export var skeleton: Skeleton3D
@export var animation_player: AnimationPlayer

var _ragdoll_enabled: bool = false
var _simulator: PhysicalBoneSimulator3D
var _stand_from: Array[Transform3D] = []
var _stand_to: Array[Transform3D] = []
var _stand_timer: float = -1.0

const STAND_DURATION: float = 0.4

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	# 站起插值：骨骼從癱倒姿態平滑過渡到站立
	if _stand_timer < 0.0:
		if _ragdoll_enabled:
			_sync_physics_to_skeleton()
		return
	_stand_timer += delta
	var t := clampf(_stand_timer / STAND_DURATION, 0.0, 1.0)
	for i in skeleton.get_bone_count():
		skeleton.set_bone_global_pose(i, _stand_from[i].interpolate_with(_stand_to[i], t))
	if t >= 1.0:
		_stand_timer = -1.0
		if animation_player:
			animation_player.play("T-Pose")

## ragdoll 開啟時，把每個 PhysicalBone 的物理變換寫回對應骨骼，驅動 mesh 癱軟
func _sync_physics_to_skeleton() -> void:
	if not _simulator or not skeleton:
		return
	var inv := skeleton.global_transform.affine_inverse()
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		var pb := bone as PhysicalBone3D
		var bone_idx := skeleton.find_bone(pb.bone_name)
		if bone_idx == -1:
			continue
		# PhysicalBone 的全局變換（已含物理模擬結果）轉為骨架局部骨骼 pose
		skeleton.set_bone_global_pose(bone_idx, inv * pb.global_transform)
	skeleton.force_update_all_bone_transforms()

## 初始化：為骨架的 RIG_BONES 生成 PhysicalBone（掛在 simulator 下）
func setup(skel: Skeleton3D, anim: AnimationPlayer) -> void:
	skeleton = skel
	animation_player = anim
	_build_physical_bones()
	# 初始默認關閉：物理骨未模擬、碰撞已 disabled、_ragdoll_enabled=false
	# 不調 set_ragdoll_enabled(false)，避免誤觸發站起插值

func _build_physical_bones() -> void:
	if not skeleton:
		push_error("RagdollRig: no skeleton")
		return
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "RagdollSimulator"
	skeleton.add_child(_simulator)

	for bone_name in RIG_BONES:
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx == -1:
			push_warning("RagdollRig: bone '%s' not found" % bone_name)
			continue
		var phys := PhysicalBone3D.new()
		phys.name = "Phys_" + bone_name
		phys.bone_name = bone_name
		# PIN 球窩關節：無角度限位，身體可充分癱軟橫躺（6DOF 默認限位會阻止全倒）
		phys.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
		phys.mass = 0.5
		# 低阻尼 + 不睡眠：四肢受重力自然下垂/擺動（軟倒效果）
		phys.linear_damp = 0.5
		phys.angular_damp = 0.5
		phys.can_sleep = false
		# 物理骨僅與地面(1)和其他物理骨(4)碰撞，不與玩家 body(2)交互
		phys.collision_layer = 4
		phys.collision_mask = 5   # 1(地面) + 4(物理骨)
		_simulator.add_child(phys)
		var shape := CapsuleShape3D.new()
		shape.radius = 0.1
		shape.height = _bone_length(bone_idx)
		var coll := CollisionShape3D.new()
		coll.shape = shape
		coll.disabled = true   # 未啟用 ragdoll 前不參與碰撞，避免推擠玩家
		phys.add_child(coll)

## 依骨骼 rest 姿勢計算段長（骨到父骨距離）
func _bone_length(bone_idx: int) -> float:
	var parent_idx := skeleton.get_bone_parent(bone_idx)
	if parent_idx == -1:
		return 0.3
	var bone_pos: Vector3 = skeleton.get_bone_global_rest(bone_idx).origin
	var parent_pos: Vector3 = skeleton.get_bone_global_rest(parent_idx).origin
	return maxf(bone_pos.distance_to(parent_pos), 0.1)

## 開關布娃娃物理模拟（啟用時停止動畫驅動，交由物理接管）
func set_ragdoll_enabled(enabled: bool) -> void:
	_ragdoll_enabled = enabled
	if not _simulator:
		push_error("RagdollRig: setup() 尚未調用")
		return
	if enabled:
		_set_collisions_enabled(true)
		# 先重置骨架到 rest 姿勢，讓物理骨從標準站姿自由癱軟（避免從動畫中間幀卡住）
		if skeleton:
			skeleton.reset_bone_poses()
		call_deferred("_start_sim")
		if animation_player:
			animation_player.stop()
	else:
		_set_collisions_enabled(false)
		call_deferred("_stop_sim")

## 控制物理骨碰撞啟用（未 ragdoll 時禁用避免推擠玩家）
func _set_collisions_enabled(enabled: bool) -> void:
	if not _simulator:
		return
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		for child in (bone as PhysicalBone3D).get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not enabled

## 延遲關閉模擬，啟動站起插值（避免瞬移）
func _stop_sim() -> void:
	if not _simulator:
		return
	var saved_gt: Transform3D = skeleton.global_transform
	# 先記錄當前（癱倒）姿態 stop 之前，stop 會立即恢復站姿
	_stand_from.clear()
	for i in skeleton.get_bone_count():
		_stand_from.append(skeleton.get_bone_global_pose(i))
	_simulator.physical_bones_stop_simulation()
	skeleton.reset_bone_poses()
	# 記錄目標（站立）姿態
	_stand_to.clear()
	for i in skeleton.get_bone_count():
		_stand_to.append(skeleton.get_bone_global_pose(i))
	skeleton.global_transform = saved_gt
	_stand_timer = 0.0

## 是否正在站起插值（插值期間動畫播放器不應接管骨骼）
func is_standing_up() -> bool:
	return _stand_timer >= 0.0

## 延遲啟動模擬（全骨參與，讓角色整隻癱軟）
func _start_sim() -> void:
	if not _simulator:
		return
	var sim_bones: Array = []
	for bone_name in RIG_BONES:
		sim_bones.append(bone_name)
	# 啟動前確保骨架回到 rest 並強制更新，物理骨從乾淨站姿初始化（避免動畫 pose 殘留導致不全癱軟）
	if skeleton:
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	# 應用最新調試阻尼（軟倒手感可運行時調）
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		var pb := bone as PhysicalBone3D
		pb.linear_damp = TuneConfig.ragdoll_linear_damp
		pb.angular_damp = TuneConfig.ragdoll_angular_damp
	_simulator.physical_bones_start_simulation(sim_bones)

## 對全身施以衝量（僅主幹骨，避免四肢放大位移）
func apply_impulse(direction: Vector3) -> void:
	if not _ragdoll_enabled or not _simulator:
		return
	var core_names := ["Phys_hips", "Phys_spine", "Phys_chest"]
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		if (bone as PhysicalBone3D).name in core_names:
			(bone as PhysicalBone3D).apply_impulse(direction)

## 重置布娃娃
func reset() -> void:
	set_ragdoll_enabled(false)

## 查詢布娃娃是否啟用
func is_ragdoll_enabled() -> bool:
	return _ragdoll_enabled

## 取得 hips 物理骨當前世界位置（用於站起時同步 body）
func get_hips_position() -> Vector3:
	if not _simulator:
		return Vector3.ZERO
	var hips: Node = _simulator.get_node_or_null("Phys_hips")
	if hips:
		return (hips as PhysicalBone3D).global_position
	return Vector3.ZERO
