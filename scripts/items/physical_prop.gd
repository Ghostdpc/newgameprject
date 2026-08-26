## 职责：场景可互动物理物件（可被推动/碰撞/抓取）
## 挂到任意场景物件（需含 MeshInstance3D 或手动 CollisionShape3D）即获得物理：
## - 玩家可推动（collision_layer=4，配合 PlayerController._push_contacted_props）
## - 可被 R 键抓取（group "physical_prop"）
## 探索性功能：若不需要，移除本脚本 + player_controller 的抓取/推动逻辑即可

class_name PhysicalProp
extends RigidBody3D

## 自动碰撞：从子 MeshInstance3D 生成 BoxShape（简化）。false 时需手动放 CollisionShape3D
@export var auto_shape_from_mesh: bool = true
@export var prop_mass: float = 10.0
@export var prop_friction: float = 0.6
@export var prop_bounce: float = 0.1
## 玩家推动力（沿玩家推进方向施加，手动实现"推得动"而非卡住）
@export var push_strength: float = 30.0
## 线性阻尼（大=飞出后更快停下，防无限滑行/乱飞）
@export var prop_linear_damp: float = 0.5
## 角阻尼
@export var prop_angular_damp: float = 0.5
## 物品撞到玩家所需最小速度（低于此不算撞，避免被推时误触发）
@export var hit_player_min_speed: float = 4.0
## 被击飞后对该玩家冷却（毫秒）：同一玩家短时间内不重复被物品击飞
const LAUNCH_COOLDOWN_MS: int = 400

## 每个玩家最后被此物品击飞的时刻（instance_id -> msec），按玩家独立冷却
var _player_launch_msec: Dictionary = {}

func _ready() -> void:
	collision_layer = 4
	collision_mask = 7  # 地面(1) + 玩家(2) + 其他物品(4)：物品间也互相碰撞
	mass = prop_mass
	linear_damp = prop_linear_damp
	angular_damp = prop_angular_damp
	physics_material_override = _make_material(prop_friction, prop_bounce)
	add_to_group("physical_prop")
	# 飞出的物品撞到玩家 → 玩家被击飞倒地（与被飞扑同等）
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	if auto_shape_from_mesh:
		_add_auto_shape()

## 飞出的物品撞到玩家：玩家进入 Fly 被击飞 → 倒地
## 防反复：同一玩家击飞后冷却内不重复触发；玩家已在倒地态(Fly/Stunned)不叠加
func _on_body_entered(body: Node) -> void:
	if freeze:
		return
	if body is PlayerController and linear_velocity.length() > hit_player_min_speed:
		var player := body as PlayerController
		var pid := player.get_instance_id()
		var last: int = _player_launch_msec.get(pid, -100000)
		if Time.get_ticks_msec() - last < LAUNCH_COOLDOWN_MS:
			return
		var cur := player.state_machine.current_state_name
		if cur == "Fly" or cur == "Stunned":
			return
		var dir := linear_velocity.normalized()
		player.state_machine.transition_to("Fly")
		var fly := player.state_machine.get_current_state() as FlyState
		fly.launch(dir * (linear_velocity.length() * 0.8) + Vector3.UP * 3.0)
		_player_launch_msec[pid] = Time.get_ticks_msec()

## 玩家推动：沿方向施加连续推力（解决 move_and_slide 卡住不推）
func push(direction: Vector3) -> void:
	if freeze:
		return
	apply_central_force(direction * push_strength * mass)

## 抓取：冻结物理，交给玩家控制（位置由玩家每帧更新）
func grab() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func is_frozen() -> bool:
	return freeze

## 松开：恢复物理，可选抛出速度
func release(throw_velocity: Vector3 = Vector3.ZERO) -> void:
	freeze = false
	linear_velocity = throw_velocity
	angular_velocity = Vector3.ZERO

func _make_material(friction: float, bounce: float) -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.friction = friction
	mat.bounce = bounce
	return mat

func _add_auto_shape() -> void:
	if not find_children("*", "CollisionShape3D", true, false).is_empty():
		return  # 已有手动碰撞
	var mesh_nodes := find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		return
	var mesh := mesh_nodes[0] as MeshInstance3D
	if not mesh or not mesh.mesh:
		return
	# mesh 相对本 RigidBody 的变换（含房间烘焙的缩放/旋转），碰撞盒须在此空间量测，
	# 否则 prop.scale=1 时碰撞盒会是 mesh 原始尺寸（放大数十倍）→ 卡人/顶飞。
	var rel := global_transform.affine_inverse() * mesh.global_transform
	var aabb := mesh.get_aabb()
	var b := AABB(rel * aabb.position, Vector3.ZERO)
	for i in range(8):
		var corner := aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		b = b.expand(rel * corner)
	var box := BoxShape3D.new()
	box.size = b.size
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = b.get_center()
	add_child(cs)
