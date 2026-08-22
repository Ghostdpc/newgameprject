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

## 初始化：為骨架的 RIG_BONES 生成 PhysicalBone（掛在 simulator 下）
func setup(skel: Skeleton3D, anim: AnimationPlayer) -> void:
	skeleton = skel
	animation_player = anim
	_build_physical_bones()
	# 初始確保關閉模擬，避免物理骨推擠玩家
	set_ragdoll_enabled(false)

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
		phys.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
		phys.mass = 1.0
		phys.linear_damp = 3.0
		phys.angular_damp = 3.0
		phys.can_sleep = true
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
		call_deferred("_start_sim")
		if animation_player:
			animation_player.stop()
	else:
		_set_collisions_enabled(false)
		call_deferred("_stop_sim")
		if animation_player:
			animation_player.play("T-Pose")

## 控制物理骨碰撞啟用（未 ragdoll 時禁用避免推擠玩家）
func _set_collisions_enabled(enabled: bool) -> void:
	if not _simulator:
		return
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		for child in (bone as PhysicalBone3D).get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not enabled

## 延遲關閉模擬並恢復站姿（保留骨架當前位置，避免站起彈回）
func _stop_sim() -> void:
	if not _simulator:
		return
	var saved_gt: Transform3D = skeleton.global_transform
	_simulator.physical_bones_stop_simulation()
	skeleton.reset_bone_poses()
	skeleton.global_transform = saved_gt

## 延遲啟動模擬（確保物理骨已入樹並初始化）
func _start_sim() -> void:
	if _simulator:
		_simulator.physical_bones_start_simulation()

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
