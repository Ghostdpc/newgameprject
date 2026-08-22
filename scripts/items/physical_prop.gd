## 職責：場景可互動物理物件（可被推動/碰撞/抓取）
## 掛到任意場景物件（需含 MeshInstance3D 或手動 CollisionShape3D）即獲得物理：
## - 玩家可推動（collision_layer=4，配合 PlayerController._push_contacted_props）
## - 可被 R 鍵抓取（group "physical_prop"）
## 探索性功能：若不需要，移除本腳本 + player_controller 的抓取/推動邏輯即可

class_name PhysicalProp
extends RigidBody3D

## 自動碰撞：從子 MeshInstance3D 生成 BoxShape（簡化）。false 時需手動放 CollisionShape3D
@export var auto_shape_from_mesh: bool = true
@export var prop_mass: float = 10.0
@export var prop_friction: float = 0.6
@export var prop_bounce: float = 0.1
## 玩家推動力（沿玩家推進方向施加，手動實現"推得動"而非卡住）
@export var push_strength: float = 30.0
## 線性阻尼（大=飛出後更快停下，防無限滑行/亂飛）
@export var prop_linear_damp: float = 0.5
## 角阻尼
@export var prop_angular_damp: float = 0.5
## 物品撞到玩家所需最小速度（低於此不算撞，避免被推時誤觸發）
@export var hit_player_min_speed: float = 4.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 7  # 地面(1) + 玩家(2) + 其他物品(4)：物品間也互相碰撞
	mass = prop_mass
	linear_damp = prop_linear_damp
	angular_damp = prop_angular_damp
	physics_material_override = _make_material(prop_friction, prop_bounce)
	add_to_group("physical_prop")
	# 飛出的物品撞到玩家 → 玩家被擊飛倒地（與被飛撲同等）
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	if auto_shape_from_mesh:
		_add_auto_shape()

## 飛出的物品撞到玩家：玩家進入 Fly 被擊飛 → 倒地
func _on_body_entered(body: Node) -> void:
	if freeze:
		return
	if body is PlayerController and linear_velocity.length() > hit_player_min_speed:
		var player := body as PlayerController
		var dir := linear_velocity.normalized()
		player.state_machine.transition_to("Fly")
		var fly := player.state_machine.get_current_state() as FlyState
		fly.launch(dir * (linear_velocity.length() * 0.8) + Vector3.UP * 3.0)

## 玩家推動：沿方向施加連續推力（解決 move_and_slide 卡住不推）
func push(direction: Vector3) -> void:
	if freeze:
		return
	apply_central_force(direction * push_strength * mass)

## 抓取：凍結物理，交給玩家控制（位置由玩家每幀更新）
func grab() -> void:
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func is_frozen() -> bool:
	return freeze

## 鬆開：恢復物理，可選拋出速度
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
		return  # 已有手動碰撞
	var mesh_nodes := find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		return
	var mesh := mesh_nodes[0] as MeshInstance3D
	if not mesh or not mesh.mesh:
		return
	# mesh 相對本 RigidBody 的變換（含房間烘焙的縮放/旋轉），碰撞盒須在此空間量測，
	# 否則 prop.scale=1 時碰撞盒會是 mesh 原始尺寸（放大數十倍）→ 卡人/頂飛。
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
