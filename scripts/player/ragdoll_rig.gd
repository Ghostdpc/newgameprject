## 職責：為現有骨架綁定布娃娃物理骨，提供 ragdoll 控制介面
## 對接 KayKit Mannequin 模型骨架

class_name RagdollRig
extends Node3D

const HumanBoneMap = preload("res://scripts/player/human_bone_map.gd")

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

## Human 骨架使用無語義編號骨（骨骼.00x），需經 HumanBoneMap 解析部位名
var is_human: bool = false

## 玩家 body（可選）：起身前把 body 水平位置對齊 hips 物理骨實際落點，避免瞬移回原點
var body_root: Node3D

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
			# human 無 T-Pose 動畫，起身後回 Idle；mannequin 維持原 T-Pose
			var next := "T-Pose"
			for an in animation_player.get_animation_list():
				if an.ends_with("Idle"):
					next = an
					break
			animation_player.play(next)

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

	var bone_list: Array[String] = []
	if is_human:
		# human 骨架骨鏈中間夾雜無語義編號骨（.003/.005 等）及 _end 尾骨。
		# 只對語義骨建物理骨會因鏈中斷而撕裂。改為沿整條鏈「全部骨」建物理骨，
		# 保證物理骨鏈連續，癱軟時不撕裂（_end 是頭/手/腳鏈的必要連接，不跳過）。
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
		# PIN 球窩關節：無角度限位，身體可充分癱軟橫躺（6DOF 默認限位會阻止全倒）
		phys.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
		phys.mass = 0.5
		# 低阻尼 + 不睡眠：四肢受重力自然下垂/擺動（軟倒效果）
		phys.linear_damp = 0.5
		phys.angular_damp = 0.5
		phys.can_sleep = false
		# 物理骨碰撞：
		# mannequin 骨稀疏，允許骨間(4)互碰；human 骨密集重疊（手/腳/頭 _end 鏈），
		# 骨間互碰會互相推擠→撕裂/爆開，故 human 只與地面(1)碰撞、骨間穿透不互推，聚成團。
		phys.collision_layer = 4
		phys.collision_mask = 5 if not is_human else 1   # 1(地面); mannequin 加 4(物理骨)
		_simulator.add_child(phys)
		var shape := CapsuleShape3D.new()
		if is_human:
			# human 骨架中段較細且密集；放大碰撞體防止下墜穿透地面
			shape.radius = 0.15
			shape.height = maxf(_bone_length(bone_idx), 0.08)
			phys.mass = 0.3
		else:
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

## 開關布娃娃物理模拟（啟用時停止動畫驅動，交由物理接管，mesh 由物理癱軟）
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
	# 起身前把玩家 body 水平對齊到 hips 物理骨實際落點（不倒偏回原點）
	if body_root:
		var hips_pos := get_hips_position()
		if hips_pos != Vector3.ZERO:
			body_root.global_position.x = hips_pos.x
			body_root.global_position.z = hips_pos.z
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
	if is_human:
		for i in skeleton.get_bone_count():
			sim_bones.append(String(skeleton.get_bone_name(i)))
	else:
		for bone_name in RIG_BONES:
			sim_bones.append(bone_name)
	# 啟動前確保骨架回到 rest 並強制更新，物理骨從乾淨站姿初始化（避免動畫 pose 殘留導致不全癱軟）
	if skeleton:
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	# 應用最新調試阻尼（軟倒手感可運行時調）；TuneConfig 為 autoload，無則用默認
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

## 對全身施以衝量（僅主幹骨，避免四肢放大位移）
func apply_impulse(direction: Vector3) -> void:
	if not _ragdoll_enabled or not _simulator:
		return
	var core_names := ["Phys_hips", "Phys_spine", "Phys_chest"]
	for bone in _simulator.find_children("*", "PhysicalBone3D", true, false):
		if (bone as PhysicalBone3D).name in core_names:
			(bone as PhysicalBone3D).apply_impulse(direction)

## 對單根物理骨施以衝量（磕头：head 骨向前下砸）
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

## 查詢布娃娃是否啟用
func is_ragdoll_enabled() -> bool:
	return _ragdoll_enabled

## 取得 hips 物理骨當前世界位置（用於站起時同步 body）
func get_hips_position() -> Vector3:
	if not _simulator:
		return Vector3.ZERO
	var hips_name := "Phys_hips"
	if is_human:
		# human 全部骨建物理骨，無 Phys_hips 命名；用根骨（骨骼.001）對應的物理骨
		if skeleton and skeleton.get_bone_count() > 0:
			hips_name = "Phys_" + String(skeleton.get_bone_name(0))
	var hips: Node = _simulator.get_node_or_null(hips_name)
	if hips:
		return (hips as PhysicalBone3D).global_position
	return Vector3.ZERO
