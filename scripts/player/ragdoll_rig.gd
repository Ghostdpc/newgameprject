## 职责：为现有骨架绑定布娃娃物理骨，提供 ragdoll 控制介面
## 对接 KayKit Mannequin 模型骨架

class_name RagdollRig
extends Node3D

const HumanBoneMap = preload("res://scripts/player/human_bone_map.gd")

# 参与 ragdoll 的主要骨骼（KayKit Mannequin 命名）
const RIG_BONES: Array[String] = [
	"hips", "spine", "chest", "head",
	"upperarm.l", "lowerarm.l",
	"upperarm.r", "lowerarm.r",
	"upperleg.l", "lowerleg.l",
	"upperleg.r", "lowerleg.r",
]

@export var skeleton: Skeleton3D
@export var animation_player: AnimationPlayer

## Human 骨架使用无语义编号骨（骨骼.00x），需经 HumanBoneMap 解析部位名
var is_human: bool = false

## 玩家 body（可选）：起身前把 body 水平位置对齐 hips 物理骨实际落点，避免瞬移回原点
var body_root: Node3D

var _ragdoll_enabled: bool = false
var _simulator: PhysicalBoneSimulator3D
var _stand_from: Array[Transform3D] = []
var _stand_to: Array[Transform3D] = []
var _stand_timer: float = -1.0

## 起身插值完成、恢复动画/站姿后发出（外部如 SpringBoneRig 可借此重设弹簧状态）
signal stood_up

const STAND_DURATION: float = 0.4

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	# 站起插值：骨骼从瘫倒姿态平滑过渡到站立
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
			# human 无 T-Pose 动画，起身后回 Idle；mannequin 维持原 T-Pose
			var next := "T-Pose"
			for an in animation_player.get_animation_list():
				if an.ends_with("Idle"):
					next = an
					break
			animation_player.play(next)
		stood_up.emit()

## ragdoll 开启时，把每个 PhysicalBone 的物理变换写回对应骨骼，驱动 mesh 瘫软
func _sync_physics_to_skeleton() -> void:
	if not _simulator or not skeleton:
		return
	var inv := skeleton.global_transform.affine_inverse()
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		var pb := bone as PhysicalBone3D
		var bone_idx := skeleton.find_bone(pb.bone_name)
		if bone_idx == -1:
			continue
		# PhysicalBone 的全局变换（已含物理模拟结果）转为骨架局部骨骼 pose
		skeleton.set_bone_global_pose(bone_idx, inv * pb.global_transform)
	skeleton.force_update_all_bone_transforms()

## 初始化：为骨架的 RIG_BONES 生成 PhysicalBone（挂在 simulator 下）
func setup(skel: Skeleton3D, anim: AnimationPlayer) -> void:
	skeleton = skel
	animation_player = anim
	_build_physical_bones()
	# 初始默认关闭：物理骨未模拟、碰撞已 disabled、_ragdoll_enabled=false
	# 不调 set_ragdoll_enabled(false)，避免误触发站起插值

func _build_physical_bones() -> void:
	if not skeleton:
		push_error("RagdollRig: no skeleton")
		return
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "RagdollSimulator"
	skeleton.add_child(_simulator)

	var bone_list: Array[String] = []
	if is_human:
		# human 骨架骨链中间夹杂无语义编号骨（.003/.005 等）及 _end 尾骨。
		# 只对语义骨建物理骨会因链中断而撕裂。改为沿整条链「全部骨」建物理骨，
		# 保证物理骨链连续，瘫软时不撕裂（_end 是头/手/脚链的必要连接，不跳过）。
		for i in skeleton.get_bone_count():
			bone_list.append(String(skeleton.get_bone_name(i)))
	else:
		bone_list = RIG_BONES.duplicate()

	for bone_name in bone_list:
		var real_name := HumanBoneMap.resolve(bone_name, is_human)
		var bone_idx := skeleton.find_bone(real_name)
		if bone_idx == -1:
			push_warning("RagdollRig: bone '%s' not found" % bone_name)
			continue
		var phys := PhysicalBone3D.new()
		phys.name = "Phys_" + bone_name
		phys.bone_name = real_name
		# PIN 球窝关节：无角度限位，身体可充分瘫软横躺（6DOF 默认限位会阻止全倒）
		phys.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
		phys.mass = 0.5
		# 低阻尼 + 不睡眠：四肢受重力自然下垂/摆动（软倒效果）
		phys.linear_damp = 0.5
		phys.angular_damp = 0.5
		phys.can_sleep = false
		# 物理骨碰撞：
		# mannequin 骨稀疏，允许骨间(4)互碰；human 骨密集重叠（手/脚/头 _end 链），
		# 骨间互碰会互相推挤→撕裂/爆开，故 human 只与地面(1)碰撞、骨间穿透不互推，聚成团。
		phys.collision_layer = 4
		phys.collision_mask = 5 if not is_human else 1   # 1(地面); mannequin 加 4(物理骨)
		_simulator.add_child(phys)
		var shape := CapsuleShape3D.new()
		if is_human:
			# human 骨架中段较细且密集；放大碰撞体防止下坠穿透地面
			shape.radius = 0.15
			shape.height = maxf(_bone_length(bone_idx), 0.08)
			phys.mass = 0.3
		else:
			shape.radius = 0.1
			shape.height = _bone_length(bone_idx)
		var coll := CollisionShape3D.new()
		coll.shape = shape
		coll.disabled = true   # 未启用 ragdoll 前不参与碰撞，避免推挤玩家
		phys.add_child(coll)

## 依骨骼 rest 姿势计算段长（骨到父骨距离）
func _bone_length(bone_idx: int) -> float:
	var parent_idx := skeleton.get_bone_parent(bone_idx)
	if parent_idx == -1:
		return 0.3
	var bone_pos: Vector3 = skeleton.get_bone_global_rest(bone_idx).origin
	var parent_pos: Vector3 = skeleton.get_bone_global_rest(parent_idx).origin
	return maxf(bone_pos.distance_to(parent_pos), 0.1)

## 开关布娃娃物理模拟（启用时停止动画驱动，交由物理接管，mesh 由物理瘫软）
func set_ragdoll_enabled(enabled: bool) -> void:
	_ragdoll_enabled = enabled
	if not _simulator:
		push_error("RagdollRig: setup() 尚未调用")
		return
	if enabled:
		_set_collisions_enabled(true)
		# 先重置骨架到 rest 姿势，让物理骨从标准站姿自由瘫软（避免从动画中间帧卡住）
		if skeleton:
			skeleton.reset_bone_poses()
		call_deferred("_start_sim")
		if animation_player:
			animation_player.stop()
	else:
		_set_collisions_enabled(false)
		call_deferred("_stop_sim")

## 控制物理骨碰撞启用（未 ragdoll 时禁用避免推挤玩家）
func _set_collisions_enabled(enabled: bool) -> void:
	if not _simulator:
		return
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		for child in (bone as PhysicalBone3D).get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not enabled

## 延迟关闭模拟，启动站起插值（避免瞬移）
func _stop_sim() -> void:
	if not _simulator:
		return
	var saved_gt: Transform3D = skeleton.global_transform
	# 先记录当前（瘫倒）姿态 stop 之前，stop 会立即恢复站姿
	_stand_from.clear()
	for i in skeleton.get_bone_count():
		_stand_from.append(skeleton.get_bone_global_pose(i))
	# 起身前把玩家 body 水平对齐到 hips 物理骨实际落点（不倒偏回原点）
	if body_root:
		var hips_pos := get_hips_position()
		if hips_pos != Vector3.ZERO:
			body_root.global_position.x = hips_pos.x
			body_root.global_position.z = hips_pos.z
	_simulator.physical_bones_stop_simulation()
	skeleton.reset_bone_poses()
	# 记录目标（站立）姿态
	_stand_to.clear()
	for i in skeleton.get_bone_count():
		_stand_to.append(skeleton.get_bone_global_pose(i))
	skeleton.global_transform = saved_gt
	_stand_timer = 0.0

## 是否正在站起插值（插值期间动画播放器不应接管骨骼）
func is_standing_up() -> bool:
	return _stand_timer >= 0.0

## 延迟启动模拟（全骨参与，让角色整只瘫软）
func _start_sim() -> void:
	if not _simulator:
		return
	var sim_bones: Array = []
	if is_human:
		for i in skeleton.get_bone_count():
			sim_bones.append(String(skeleton.get_bone_name(i)))
	else:
		for bone_name in RIG_BONES:
			sim_bones.append(bone_name)
	# 启动前确保骨架回到 rest 并强制更新，物理骨从干净站姿初始化（避免动画 pose 残留导致不全瘫软）
	if skeleton:
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	# 应用最新调试阻尼（软倒手感可运行时调）；TuneConfig 为 autoload，无则用默认
	var tc := get_node_or_null("/root/TuneConfig")
	var lin_damp := 0.3
	var ang_damp := 0.3
	if tc:
		lin_damp = tc.ragdoll_linear_damp
		ang_damp = tc.ragdoll_angular_damp
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		var pb := bone as PhysicalBone3D
		pb.linear_damp = lin_damp
		pb.angular_damp = ang_damp
	_simulator.physical_bones_start_simulation(sim_bones)
	# 启动后清除残留线/角速度：否则击飞动量让链末端(头)甩开，身体被拉长
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		var pb := bone as PhysicalBone3D
		pb.linear_velocity = Vector3.ZERO
		pb.angular_velocity = Vector3.ZERO

## 对全身施以冲量（仅主干骨，避免四肢放大位移）
func apply_impulse(direction: Vector3) -> void:
	if not _ragdoll_enabled or not _simulator:
		return
	var core_names := ["Phys_hips", "Phys_spine", "Phys_chest"]
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		if (bone as PhysicalBone3D).name in core_names:
			(bone as PhysicalBone3D).apply_impulse(direction)

## 对单根物理骨施以冲量（磕头：head 骨向前下砸）
func apply_bone_impulse(bone_name: String, direction: Vector3) -> void:
	if not _ragdoll_enabled or not _simulator:
		return
	var target := _simulator.get_node_or_null("Phys_" + bone_name) as PhysicalBone3D
	if target:
		target.apply_impulse(direction)

## 驱动所有物理骨沿水平方向匀速滑行（香蕉皮滑倒用）。speed<=0 停止滑行。
## 每帧重置水平骨速以克服地面摩擦，保持滑行；垂直速度保持物理守恒（接触地面）。
func drive_bones_horizontal(dir: Vector3, speed: float) -> void:
	if not _ragdoll_enabled or not _simulator:
		return
	var h := (Vector3(dir.x, 0.0, dir.z)).normalized()
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		var pb := bone as PhysicalBone3D
		var v := pb.linear_velocity
		if speed <= 0.0:
			# 停止滑行：只清水平部分，保留垂直（落回地面）
			pb.linear_velocity = Vector3(0.0, v.y, 0.0)
		else:
			# 维持前方恒定水平速度
			var target_v := h * speed
			# 平滑逼近而非瞬置，避免抖动
			pb.linear_velocity = Vector3(target_v.x, v.y, target_v.z)

## 重置布娃娃
func reset() -> void:
	set_ragdoll_enabled(false)

## 查询布娃娃是否启用
func is_ragdoll_enabled() -> bool:
	return _ragdoll_enabled

## 取得 hips 物理骨当前世界位置（用于站起时同步 body）
func get_hips_position() -> Vector3:
	if not _simulator:
		return Vector3.ZERO
	var hips_name := "Phys_hips"
	if is_human:
		# human 全部骨建物理骨，无 Phys_hips 命名；用根骨（骨骼.001）对应的物理骨
		if skeleton and skeleton.get_bone_count() > 0:
			hips_name = "Phys_" + String(skeleton.get_bone_name(0))
	var hips: Node = _simulator.get_node_or_null(hips_name)
	if hips:
		return (hips as PhysicalBone3D).global_position
	return Vector3.ZERO
