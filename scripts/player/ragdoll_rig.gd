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
		phys.linear_damp = 0.5
		phys.angular_damp = 0.5
		phys.can_sleep = true
		_simulator.add_child(phys)
		var shape := CapsuleShape3D.new()
		shape.radius = 0.1
		shape.height = _bone_length(bone_idx)
		var coll := CollisionShape3D.new()
		coll.shape = shape
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
		call_deferred("_start_sim")
		if animation_player:
			animation_player.stop()
	else:
		call_deferred("_stop_sim")
		if skeleton:
			skeleton.reset_bone_poses()
		if animation_player:
			animation_player.play("T-Pose")

## 延遲啟動模擬（確保物理骨已入樹並初始化）
func _start_sim() -> void:
	if _simulator:
		_simulator.physical_bones_start_simulation()

func _stop_sim() -> void:
	if _simulator:
		_simulator.physical_bones_stop_simulation()

## 對全身施以衝量
func apply_impulse(direction: Vector3) -> void:
	if not _ragdoll_enabled or not _simulator:
		return
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		(bone as PhysicalBone3D).apply_impulse(direction)

## 重置布娃娃
func reset() -> void:
	set_ragdoll_enabled(false)
