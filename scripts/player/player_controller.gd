## 職責：玩家主控制器，整合輸入/狀態機/物理移動/動畫

class_name PlayerController
extends CharacterBody3D

const GRAVITY: float = 20.0
const ACCELERATION: float = 15.0
## 轉向速率（rad/s；大=轉得快，小=平滑慢轉）
const TURN_RATE: float = 12.0
## 拾取有效距離（米）
const PICKUP_RANGE: float = 1.5

const ANIM_IDLE: String = "Idle_A"
const ANIM_MOVE: String = "Running_A"
const ANIM_JUMP: String = "Jump_Full_Long"
const ANIM_DIVE: String = "Jump_Full_Short"

const IDLE_SOURCE: String = "res://assets/models/mannequin/animations/Rig_Medium_General.glb"
const HumanBoneMap = preload("res://scripts/player/human_bone_map.gd")

## human 動畫 FPS（模型導入 30fps）
const HUMAN_ANIM_FPS: float = 30.0
## human「主動畫」內部的子段（帧號）——所有動作統一塞在同一個動畫裡，按帧號拆：
## 美術後續加動作時，直接在這個表裡加一行即可，程式自動拆出可點播的子動畫。
## {子動畫名: [起始幀, 結束幀]}
const HUMAN_ANIM_SLOTS: Dictionary = {
	"Human_Idle":  [0, 30],    # 待機
	"Human_Move":  [40, 60],   # 移動
	"Human_Dive":  [70, 105],  # 飛撲
	# 之後美術把更多動作塞進主動畫時，在此加一行即可（如 "Human_Jump": [106,119]）
}

## 主動畫的後綴識別（美術可能命名 Idle/Walk/… 各種，取「存在」的那個）
const HUMAN_MASTER_SUFFIXES: Array[String] = ["Idle", "Walk", "Main", "Master"]

## human.fbx 原始高度約 4.456（實測），縮放到 1.0m 的精確係數
const HUMAN_MODEL_SCALE: float = 1.0 / 4.456
## human 動畫名帶「骨架|」前綴，用後綴匹配（Idle/Walk/jump）
const HUMAN_ANIM_IDLE: String = "Idle"
const HUMAN_ANIM_MOVE: String = "Walk"
const HUMAN_ANIM_JUMP: String = "jump"

## 拾取長按時長（秒，策划要求 0.8）
const PICKUP_HOLD_TIME: float = 0.8

## 拾取到可使用之間的間隔（秒）：撿起後需等待才能用，避免同鍵誤觸立即使用
const PICKUP_USE_GAP: float = 0.3

## 抓取距離 / 拋出速度 / 被抓起物體跟隨位置（探索性功能，可刪）
const GRAB_RANGE: float = 2.5
const GRAB_LIFT: float = 1.6
const THROW_SPEED: float = 5.0
## 抓取吸向手的速度（大=更快抓到；小=緩慢飛來）
const GRAB_LERP: float = 8.0

@export var jump_force: float = 8.16
## 二段跳高度（相對 jump_force 的比例；0 = 關閉二段跳）
@export var double_jump_ratio: float = 0.9

## 本空中週期是否可用二段跳（JumpState 管理）
var double_jump_available: bool = false
@export var player_index: int = 0
@export var player_color: Color = Color.WHITE
## human 模型本體 Y 軸朝向補償（deg）。若走路側身，在 player.tscn 調整讓模型正面朝移動方向。
@export var human_model_yaw_deg: float = -90.0

signal item_picked_up(item_id: String)
signal item_used(item_id: String)
signal item_cleared()
signal death_started(player: PlayerController)

var player_input: PlayerInput
var state_machine: PlayerStateMachine
var ragdoll_rig: RagdollRig
var outfit_manager: OutfitManager
var character_effects: CharacterEffects
var spring_rig: SpringBoneRig
var face: PlayerFaceController

## 進入對局：隨機一個表情（每輪開始調用）
func enter_match_random_face() -> void:
	if face and face.count() > 0:
		face.show_expression(randi() % face.count())

## 動作觸發時輪換到下一表情
func cycle_face() -> void:
	if not face or face.count() <= 0:
		return
	var next: int = int(face.get("_current_index")) + 1
	if next >= face.count():
		next = 0
	face.show_expression(next)

## 持有的道具 id，空字符串表示无道具（每次最多持有一个）
var held_item_id: String = ""
## 被炸等负面效果累计的积分惩罚，快门结算时从总分扣除（clamp 到 0）
var score_penalty: int = 0
## 移速乘數（1.0 = 正常；由 player_speed_effect 臨時修改）
var speed_multiplier: float = 1.0
## 身材缩放（服装效果）：head_scale 放大头部 / body_scale 放大身躯 / body_width 加宽
var head_scale: float = 1.0
var body_scale: float = 1.0
var body_width: float = 1.0
## 当前装备的服装（槽位名 -> garment_id），由 GarmentSystem 维护，评分读取用
var equipped_garments: Dictionary = {}

var _animation_player: AnimationPlayer
var _current_anim: String = ""
## 凍結（表情調試用）：暫停動畫更新與狀態機，角色定住
var frozen: bool = false
var _is_human_model: bool = false
var _suicide_was_pressed: bool = false
var _model_skeleton: Skeleton3D
var _head_bone_idx: int = -1
var _body_bone_idx: int = -1
var _model_node: Node3D
var _body_collision: CollisionShape3D
var _body_mask_saved: int = -1

var _pickup_hold_time: float = 0.0
## 撿起後剩餘的使用冷卻（秒），>0 時 O 鍵不觸發使用
var _use_gap_time: float = 0.0
var _grabbed_prop: PhysicalProp = null
var _head_icon: PlayerHeadIcon

## 是否處於死亡/復活流程（非正常對戰狀態）
func is_dead() -> bool:
	var st := state_machine.current_state_name
	return st == "Death" or st == "RespawnWaiting" or st == "RespawnFall"

## 香蕉皮踩中：进入倒地滑行状态（沿途撞人，类似飞扑）
func start_banana_slide() -> void:
	if is_dead():
		return
	state_machine.transition_to("BananaSlide")

func _ready() -> void:
	player_input = PlayerInput.new(player_index)
	# 身材缩放要排在动画(priority 0)与弹簧骨骼(100)之后，避免骨骼 scale 被动画覆盖
	process_priority = 100
	_setup_state_machine()
	_setup_model()
	_setup_outfit()
	_head_icon = get_node_or_null("PlayerHeadIcon") as PlayerHeadIcon
	apply_player_color(player_color)
	add_to_group("players")
	EventBus.battle_started.connect(func(): score_penalty = 0)

## 開關布娃娃（被擊倒時進入物理倒地）
func set_ragdoll(enabled: bool) -> void:
	if ragdoll_rig:
		ragdoll_rig.set_ragdoll_enabled(enabled)
	# 布娃娃時關閉彈簧骨骼，避免與物理姿態搶寫骨架
	if spring_rig:
		spring_rig.set_active(not enabled)
	# 物理骨 layer=4 啟用碰撞後會擋住/推開玩家碰撞體（玩家 mask 含 4）。
	# ragdoll 期間把玩家 mask 移除物理骨層，讓碰撞體不被癱軟的骨骼擠開/擋路。
	if enabled:
		_body_mask_saved = collision_mask
		collision_mask = _body_mask_saved & ~4
	else:
		if _body_mask_saved != -1:
			collision_mask = _body_mask_saved
			_body_mask_saved = -1

## 擊飛：body 位移（模型跟 body，姿態由 ragdoll 提供）
func knockback(direction: Vector3) -> void:
	velocity = direction

## 癱軟時 body 跟隨物理骨落點（貼地），站起前也用它對齊避免漂移
func sync_body_to_ragdoll() -> void:
	if not ragdoll_rig:
		return
	var hips_pos := ragdoll_rig.get_hips_position()
	if hips_pos == Vector3.ZERO:
		return
	# 對齊 hips 水平位置；Y 限制在地面之上（≥0），避免碰撞體穿到地面下
	var body_y := maxf(hips_pos.y, 0.0)
	global_position = Vector3(hips_pos.x, body_y, hips_pos.z)
	velocity.y = 0.0

## 出界死亡：進入死亡狀態（清道具、藏體、停物理）
func die() -> void:
	SoundMgr.play("die")
	if state_machine.current_state_name == "Death":
		return
	death_started.emit(self)
	state_machine.transition_to("Death")

## 配置重生（由 LevelBase 設定復活點與讀秒時長）
func configure_respawn(spawn_pos: Vector3, wait_duration: float) -> void:
	var waiting := state_machine.get_state("RespawnWaiting") as RespawnWaitingState
	if waiting:
		waiting.configure(spawn_pos, wait_duration)

## 倒地後站起，由調用方確保已關閉 ragdoll
func stand_up() -> void:
	if ragdoll_rig:
		ragdoll_rig.reset()

## 拾取道具（覆盖式：新道具直接替换当前持有；ON_PICKUP 触发器立即使用）
func pickup_item(item_id: String) -> void:
	held_item_id = item_id
	_use_gap_time = PICKUP_USE_GAP
	item_picked_up.emit(item_id)
	EventBus.item_picked_up.emit(player_index, item_id)
	_show_head_icon(item_id)
	var def := ItemSystem._item_config.get_item(item_id) if ItemSystem else null
	if def and def.trigger == ItemTypes.Trigger.ON_PICKUP:
		use_held_item()

## 头顶显示道具图标（约 2 秒出现→消失）
func _show_head_icon(item_id: String) -> void:
	if not _head_icon:
		return
	if not ItemSystem or not ItemSystem._item_config:
		return
	var icon_key: String = ItemSystem._item_config.get_item_icon(item_id)
	if icon_key == "":
		return
	var tex := ItemIcons.load_icon(icon_key)
	if tex:
		_head_icon.show_item(tex)

## 使用当前持有的道具（供输入系统或外部调用）
func use_held_item() -> void:
	if held_item_id.is_empty():
		return
	var id := held_item_id
	held_item_id = ""
	item_used.emit(id)
	ItemSystem.use_item(self, id)

## 丢弃持有的道具（不触发效果）
func clear_item() -> void:
	if held_item_id.is_empty():
		return
	held_item_id = ""
	item_cleared.emit()

func _process(delta: float) -> void:
	if is_dead():
		return
	if frozen:
		return
	if spring_rig:
		spring_rig.velocity_hints = Vector2(velocity.x, velocity.z)
		spring_rig.root_velocity = velocity
	if GameManager.current_stage == GameManager.GameStage.SCORING:
		return
	state_machine.update(delta)
	_update_animation()
	_apply_body_scale()
	if _use_gap_time > 0.0:
		_use_gap_time -= delta
	if player_input.is_use_item_just_pressed():
		if not held_item_id.is_empty():
			# 身上有道具：撿起後需過間隔才能使用
			if _use_gap_time <= 0.0:
				use_held_item()
		else:
			# 身上無道具：嘗試拾取附近道具
			_try_pickup()

## 长按拾取逻辑：按住 0.8s 触发；移动/受控 打断
func _update_pickup_hold(delta: float) -> void:
	# 拾取可被打断：移动 / 非 Idle/Move 状态
	var st := state_machine.current_state_name
	var can_pickup := (st == "Idle" or st == "Move") and _pickup_movement_blocked() == false
	if not can_pickup:
		_pickup_hold_time = 0.0
		return
	if player_input.is_pickup_held():
		_pickup_hold_time += delta
		if _pickup_hold_time >= PICKUP_HOLD_TIME:
			_pickup_hold_time = 0.0
			_try_pickup()
	else:
		_pickup_hold_time = 0.0

## 拾取長按時如果正在移動則中斷（策划：移動會打斷拾取）
func _pickup_movement_blocked() -> bool:
	return player_input.get_move_direction().length_squared() > 0.0

func _try_pickup() -> void:
	var result := _pickup_nearest()
	if result.is_empty():
		return
	var id: String = result["id"]
	var is_garment: bool = result.get("is_garment", false)
	if is_garment:
		GarmentSystem.equip_garment(self, id)
	else:
		pickup_item(id)

## 拾取：找最近的 pickup_items 成员，返回 { id, is_garment } 或 {}
func _pickup_nearest() -> Dictionary:
	var items := get_tree().get_nodes_in_group("pickup_items")
	if items.is_empty():
		return {}
	var fwd := global_basis.z
	var range_sq := PICKUP_RANGE * PICKUP_RANGE
	var nearest: Node3D = null
	var best_score := -INF
	for item in items:
		var n := item as Node3D
		if not n:
			continue
		var to := n.global_position - global_position
		to.y = 0.0
		var d_sq := to.length_squared()
		if d_sq > range_sq:
			continue
		if d_sq < 0.0001:
			d_sq = 0.0001
		var dist := sqrt(d_sq)
		var facing := to.normalized().dot(fwd)
		if facing < 0.15:
			continue
		var score := facing - dist / PICKUP_RANGE * 0.5
		if score > best_score:
			best_score = score
			nearest = n
	if nearest == null or not nearest.has_method("pickup_for"):
		return {}
	var id: String = nearest.pickup_for(self)
	if id.is_empty():
		return {}
	var is_garment := nearest.is_in_group("garment_pickups")
	return { "id": id, "is_garment": is_garment }

func _physics_process(delta: float) -> void:
	# 死亡/復活狀態也需物理幀推進（Death→Waiting→Fall），故不整體跳過
	_apply_gravity(delta)
	if is_dead():
		state_machine.physics_update(delta)
		move_and_slide()
		return
	_handle_suicide()
	if GameManager.current_stage == GameManager.GameStage.SCORING:
		velocity.x = move_toward(velocity.x, 0.0, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCELERATION * delta)
		move_and_slide()
		return
	state_machine.physics_update(delta)
	move_and_slide()
	_check_dive_hit()
	_push_contacted_props()
	_update_grab(delta)

## 自殺快捷鍵（測試用）：P1=O / P2=P，按下立即觸發完整死亡+重生流程
func _handle_suicide() -> void:
	var pressed := player_input.is_suicide_just_pressed()
	if pressed and not _suicide_was_pressed:
		# 把玩家移到出界下方，讓 LevelBase._physics_process 接管重生流程
		global_position.y = -100.0
	_suicide_was_pressed = pressed

## 玩家移動時推動接觸到的場景物理物（解決 move_and_slide 卡住不推）
func _push_contacted_props() -> void:
	# 用輸入方向而非 velocity（頂住箱子時 velocity 會被歸零，輸入方向仍有效）
	var input_dir := player_input.get_move_direction()
	if input_dir.length_squared() < 0.01:
		return
	var push_dir := to_world_dir(input_dir)
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PhysicalProp:
			(collider as PhysicalProp).push(push_dir)

## 抓取更新：R 鍵按住 → 抓起/跟隨面前物理物；鬆開 → 拋出
func _update_grab(delta: float) -> void:
	if _grabbed_prop != null:
		# 抓取點隨物品尺寸：前置距離=深度一半+間隙，抬升=高度/2（避免大件卡身位）
		var size := _prop_half_extents(_grabbed_prop)
		var depth := size.z  # 沿前向的半深
		var height := size.y # 半高
		var target := global_position + Vector3.UP * (GRAB_LIFT + height) + global_basis.z * (depth + 0.5)
		var diff := target - _grabbed_prop.global_position
		if diff.length() > 0.05:
			_grabbed_prop.global_position += diff * clampf(GRAB_LERP * delta, 0.0, 1.0)
		else:
			_grabbed_prop.global_position = target
		if not player_input.is_grab_pressed():
			# 鬆開：跑動中 = 帶著玩家速度拋出；靜止 = 原地放下（只留很小前向）
			var carry := Vector3(velocity.x, 0.0, velocity.z)
			var throw_dir := global_basis.z.normalized()
			var speed := carry.length()
			var release_velocity: Vector3
			if speed > 0.5:
				release_velocity = throw_dir * THROW_SPEED + carry + Vector3.UP * 2.0
			else:
				release_velocity = carry + throw_dir * 0.5 + Vector3.UP * 1.0
			_grabbed_prop.release(release_velocity)
			SoundMgr.play("throw_prop", true)
			_grabbed_prop = null
		return
	# 未抓取：R 按下 → 抓最近的物理物件
	if player_input.is_grab_pressed():
		_grabbed_prop = _find_nearest_prop()
		if _grabbed_prop:
			_grabbed_prop.grab()
			SoundMgr.play("grab", true)

## 物品碰撞半尺寸（xyz），用於調整抓取點位置避免大件卡身位。無碰撞/未知時返回原固定檔位。
func _prop_half_extents(prop: PhysicalProp) -> Vector3:
	for cs in prop.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (cs as CollisionShape3D).shape
		if shape is BoxShape3D:
			return (shape as BoxShape3D).size * 0.5
		if shape is CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			return Vector3(cap.radius, cap.height * 0.5, cap.radius)
	var mesh_nodes := prop.find_children("*", "MeshInstance3D", true, false)
	if not mesh_nodes.is_empty():
		var mi := mesh_nodes[0] as MeshInstance3D
		if mi and mi.mesh:
			return mi.get_aabb().size * 0.5
	return Vector3(1.1, 0.8, 1.1)

## 找最近的可抓取場景物件（group "physical_prop"，距離內）
func _find_nearest_prop() -> PhysicalProp:
	var props := get_tree().get_nodes_in_group("physical_prop")
	var nearest: PhysicalProp = null
	var best := INF
	for node in props:
		var prop := node as PhysicalProp
		if not prop:
			continue
		var d := global_position.distance_to(prop.global_position)
		if d < best:
			best = d
			nearest = prop
	if nearest and best <= GRAB_RANGE:
		return nearest
	return null

## 飛撲狀態碰撞檢測：撞到玩家→擊飛對方倒地；撞到場景物理物→擊飛物品 + 自己倒地
func _check_dive_hit() -> void:
	if state_machine.current_state_name != "Dive":
		return
	var dive := state_machine.get_current_state() as DiveState
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PlayerController:
			dive.hit_target(collider as PlayerController)
		elif collider is PhysicalProp:
			dive.knock_prop(collider as PhysicalProp)
			# 撞到物品自己也立刻停下並進入倒地（與被撞同等）
			SoundMgr.play("hit")
			_knocked_down_by_prop(dive)
			return

## 撞到物品後自己倒地：立即停下 + 進入 Stunned（布娃娃癱軟）
func _knocked_down_by_prop(dive: DiveState) -> void:
	velocity = Vector3.ZERO
	state_machine.transition_to("Stunned")

func apply_move(direction: Vector2) -> void:
	var world_dir := to_world_dir(direction)
	var target_velocity := world_dir * TuneConfig.move_speed * speed_multiplier
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * get_physics_process_delta_time())
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * get_physics_process_delta_time())
	if direction.length_squared() > 0.0:
		_turn_toward(world_dir)

## 把屏幕直觉的输入方向（x=右, y=下=远离相机）换算成世界水平方向（相机相对）。
## W=向相机前方，S=远离，A=相机左，D=相机右。
func to_world_dir(input: Vector2) -> Vector3:
	var cam := _get_main_camera()
	if cam == null:
		return Vector3(input.x, 0.0, input.y).normalized()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var right := cam.global_basis.x
	right.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	return (right * input.x - fwd * input.y).normalized()

func _get_main_camera() -> Camera3D:
	var ctrl := CameraSystem.get_main_controller()
	if ctrl and ctrl.has_method("get_camera"):
		var cam: Camera3D = ctrl.get_camera()
		if cam and is_instance_valid(cam):
			return cam
	return get_viewport().get_camera_3d()

## 平滑轉身：模型正面朝 +Z，用 yaw 角度插值（避免 slerp 在 180° 退化導致瞬移）
func _turn_toward(direction: Vector3) -> void:
	var move_dir := direction
	move_dir.y = 0.0
	if move_dir.length_squared() < 0.0001:
		return
	move_dir = move_dir.normalized()
	var target_yaw := atan2(move_dir.x, move_dir.z)
	var cur_yaw := rotation.y
	if is_equal_approx(cur_yaw, target_yaw):
		return
	rotation.y = lerp_angle(cur_yaw, target_yaw, minf(1.0, TURN_RATE * get_physics_process_delta_time()))

func _apply_gravity(delta: float) -> void:
	if is_dead():
		return
	if not is_on_floor():
		# Fly 階段由 FlyState 自行管理重力（可自定義下墜）
		if state_machine.current_state_name == "Fly":
			return
		# 被擊飛期間用更大重力，讓上升/下降都更快
		var g := GRAVITY
		if state_machine.current_state_name == "Stunned":
			g = TuneConfig.stun_gravity
		velocity.y -= g * delta

func _setup_state_machine() -> void:
	state_machine = PlayerStateMachine.new()
	add_child(state_machine)

	var idle := IdleState.new()
	var move := MoveState.new()
	var jump := JumpState.new()
	var dive := DiveState.new()
	var fly := FlyState.new()
	var stunned := StunnedState.new()
	var banana_slide := BananaSlideState.new()
	var death := DeathState.new()
	var respawn_waiting := RespawnWaitingState.new()
	var respawn_fall := RespawnFallState.new()

	idle.init(self)
	move.init(self)
	jump.init(self)
	dive.init(self)
	fly.init(self)
	stunned.init(self)
	banana_slide.init(self)
	death.init(self)
	respawn_waiting.init(self)
	respawn_fall.init(self)

	state_machine.register_state("Idle", idle)
	state_machine.register_state("Move", move)
	state_machine.register_state("Jump", jump)
	state_machine.register_state("Dive", dive)
	state_machine.register_state("Fly", fly)
	state_machine.register_state("Stunned", stunned)
	state_machine.register_state("BananaSlide", banana_slide)
	state_machine.register_state("Death", death)
	state_machine.register_state("RespawnWaiting", respawn_waiting)
	state_machine.register_state("RespawnFall", respawn_fall)

	state_machine.start("Idle")

## 定位模型骨架與動畫播放器
func _setup_model() -> void:
	var model := get_node_or_null("Model")
	if not model:
		return
	_animation_player = _find_animation_player(model)
	# human 模型檢測：動畫名以「骨架|」開頭（KayKit 為 Idle_A 等），縮小 10 倍 + 轉前向
	_is_human_model = _is_human_skel(model)
	if _is_human_model:
		# human 骨骼 pose 由動畫直接驅動。做正確縮放 + Y 軸朝向補償（前向對齊 +Z）。
		model.scale = Vector3.ONE * HUMAN_MODEL_SCALE
		model.rotation.y = deg_to_rad(human_model_yaw_deg)
		# 模型自帶 OmniLight 隨玩家移動造成泛白/發光，移除之
		_remove_embedded_lights(model)
		# 原模型材質為純白 unshaded（泛白主因），改為受光照的標準材質 + 玩家色
		_apply_human_material(model)
		# human 自帶動畫，不 merge KayKit Idle（骨骼名不匹配會報警）
		_set_human_animation_looping()
		# 組合主動畫（Idle/Idle_001 含待機+移動+飛撲多段）必須按帧拆出待機段，
		# 即使有獨立 Walk/jump 也要拆（待機只用組合裡的待機段）
		_split_human_idle()
	else:
		_merge_idle_animation()
		_set_animation_looping(ANIM_IDLE)
		_set_animation_looping(ANIM_MOVE)
		_set_animation_looping(ANIM_JUMP)
		_set_animation_looping(ANIM_DIVE)
	# 初始化布娃娃（綁定模型骨架）
	ragdoll_rig = get_node_or_null("RagdollRig") as RagdollRig
	if ragdoll_rig:
		var skeleton := _find_skeleton(model)
		if skeleton and _animation_player:
			ragdoll_rig.is_human = _is_human_model
			ragdoll_rig.body_root = self
			ragdoll_rig.setup(skeleton, _animation_player)
	# Spring Bone 彈簧骨骼：常態軟糯效果（掛本角色，高 priority 在動畫後寫回）
	spring_rig = SpringBoneRig.new()
	spring_rig.name = "SpringBoneRig"
	add_child(spring_rig)
	var skel2 := _find_skeleton(model)
	if skel2 and _animation_player:
		spring_rig.skeleton = skel2
		spring_rig.animation_player = _animation_player
		spring_rig.is_human = _is_human_model
		# 保留 head 進 spring（磕頭 kowtow 效果需 head spring）；帽子隨磕頭左右晃屬合理演出
		spring_rig.apply_preset("normal")
		spring_rig.setup(skel2, _animation_player)
		spring_rig.set_active(true)
	# 軟倒起身後骨骼姿態大變：重設彈簧狀態對齊站姿，避免 head 彈簧殘留舊態
	# 與服装头骨縮放(1.8)疊加，導致蘑菇帽軟倒後懸空漂走。
	if ragdoll_rig and spring_rig:
		ragdoll_rig.stood_up.connect(func(): spring_rig.reinit())
	# 身材缩放：记录 head/chest 骨骼索引（服装效果放大部位用）
	_model_skeleton = _find_skeleton(model)
	if _model_skeleton:
		_head_bone_idx = _model_skeleton.find_bone(HumanBoneMap.resolve("head", _is_human_model))
		_body_bone_idx = _model_skeleton.find_bone(HumanBoneMap.resolve("chest", _is_human_model))
	# 变宽用到：Model 节点（整体横向缩放）+ 胶囊碰撞体（半径跟随）
	_model_node = model
	_body_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	# 表情贴脸：注入骨架（支持具名 head 骨与 Blender 默认骨名）
	face = get_node_or_null("Face") as PlayerFaceController
	if face:
		face.setup(_model_skeleton)
		# 若有模型帶獨立臉片（newnewhuman），自動改貼臉到臉片材質；無則保持平面貼紙
		face.use_head_texture = true
		var face_ok := face.apply_head_texture()
		if not face_ok:
			face.use_head_texture = false

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

## 判定是否 human 模型（骨架含 Blender 默認骨名「骨骼.」）
func _is_human_skel(model: Node3D) -> bool:
	var skel := _find_skeleton(model) as Skeleton3D
	if skel:
		for i in skel.get_bone_count():
			if String(skel.get_bone_name(i)).begins_with("骨骼"):
				return true
	return false

## 移除模型自帶的光源節點（human.fbx 帶一個 OmniLight，會造成泛白/發光）
func _remove_embedded_lights(model: Node3D) -> void:
	for l in model.find_children("*", "Light3D", true, false):
		l.queue_free()

## 覆蓋 human 模型的純白 unshaded 材質：改為受光照、帶玩家色，消除整片泛白
func _apply_human_material(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			m.material_override = null
		var mat := StandardMaterial3D.new()
		mat.albedo_color = player_color
		mat.roughness = 0.9
		mat.metallic = 0.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.material_override = mat

## 從 General.glb 合併 Idle 動畫（MovementBasic 無待機動畫）
func _merge_idle_animation() -> void:
	if not _animation_player or _animation_player.has_animation(ANIM_IDLE):
		return
	var glb := load(IDLE_SOURCE) as PackedScene
	if not glb:
		return
	var inst := glb.instantiate()
	var src_ap := _find_animation_player(inst)
	if src_ap and src_ap.has_animation(ANIM_IDLE):
		var anim: Animation = src_ap.get_animation(ANIM_IDLE).duplicate()
		var lib := _animation_player.get_animation_library("")
		if lib:
			lib.add_animation(ANIM_IDLE, anim)
	inst.queue_free()

## 身材缩放（服装效果）：head_scale 放大头部，body_scale 放大身躯。
## chest 骨缩放的子骨（头/手臂）乘 1/body_scale 抵消，避免身体放大连带头和手臂；
## 头再叠乘自身 head_scale（若未放大头则保持正常大小）。
## 布娃娃/倒地时重置（物理接管骨骼姿态，不再叠加缩放避免错乱）。
func _apply_body_scale() -> void:
	if not _model_skeleton:
		return
	if _ragdoll_in_use():
		# 布娃娃/軟倒：重置身材縮放，物理接管骨骼姿態（避免殘留縮放錯亂）
		_reset_body_scale()
		return
	if _body_bone_idx != -1:
		_model_skeleton.set_bone_pose_scale(_body_bone_idx, Vector3.ONE * body_scale)
	if _head_bone_idx != -1:
		if _is_human_model:
			# human：实测「骨骼.004」放大時頭會變大（body_scale 驗證），故 head_scale 也用它放大頭。
			# 身体放大用根骨「骨骼.001」（4157頂點=身體主體）。
			var head_scale_v := head_scale / maxf(body_scale, 0.01)
			var body_scale_v := maxf(body_scale, 0.01)
			for i in _model_skeleton.get_bone_count():
				var nm := String(_model_skeleton.get_bone_name(i))
				# 不縮放「骨骼.005_end_end_end_end」（帽子掛點骨），避免掛點被 scale 拉走/帽子亂
				if nm == "骨骼.004" or nm == "骨骼.005":
					_model_skeleton.set_bone_pose_scale(i, Vector3.ONE * head_scale_v)
				elif nm == "骨骼.001":
					_model_skeleton.set_bone_pose_scale(i, Vector3.ONE * body_scale_v)
		else:
			# 抵消 chest 继承的缩放，再乘自身的头放大
			_model_skeleton.set_bone_pose_scale(_head_bone_idx, Vector3.ONE * (head_scale / maxf(body_scale, 0.01)))
	# 手臂是 chest 子骨，身体放大时抵消保持原大小
	_apply_child_compensate(_CHEST_CHILD_BONES, body_scale)
	_apply_collision_scale()

## 帽子掛在頭骨會隨頭放大而放大；設逆縮放保持帽子視覺尺寸不爆大。
## user_hat_scale_mult 供外部（garment_demo）手動微調帽子大小。
var user_hat_scale_mult: float = 1.0

func _compensate_hat_scale(head_scale_v: float) -> void:
	if not outfit_manager or head_scale_v <= 0.0:
		return
	var hat := outfit_manager.get_item("hat_slot")
	if hat:
		hat.scale = Vector3.ONE * (0.5 * user_hat_scale_mult / head_scale_v)

## chest 的子骨（身体放大时补偿还原，避免手臂跟着变大）
const _CHEST_CHILD_BONES: Array[String] = [
	"upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "handslot.l",
	"upperarm.r", "lowerarm.r", "wrist.r", "hand.r", "handslot.r",
]

func _apply_child_compensate(bone_names: Array[String], parent_scale: float) -> void:
	if parent_scale == 1.0 or not _model_skeleton:
		return
	var inv := 1.0 / parent_scale
	for bname in bone_names:
		var idx := _model_skeleton.find_bone(HumanBoneMap.resolve(bname, _is_human_model))
		if idx != -1:
			_model_skeleton.set_bone_pose_scale(idx, Vector3.ONE * inv)

## 加宽：Model 整个横向(X)缩放 + 胶囊碰撞体半径同步跟随，
## 让身材变换的同时碰撞体体积真实变大（飞扑/撞击判定一致）。
func _apply_collision_scale() -> void:
	if _model_node:
		if _is_human_model:
			# human 整體縮放基為 HUMAN_MODEL_SCALE，加寬只放大 X
			_model_node.scale.x = HUMAN_MODEL_SCALE * body_width
		else:
			_model_node.scale.x = body_width
	if _body_collision:
		var shape := _body_collision.shape as CapsuleShape3D
		if shape:
			shape.radius = 0.4 * maxf(1.0, maxf(body_width, body_scale))

## 磕头布娃娃（服装演出）：临时开启 ragdoll，对 head 骨施向前下方冲量让角色叩头，
## 一段时间后自动关闭 ragdoll 恢复站姿。不进入 Stunned/倒地状态。
func play_kowtow_ragdoll(force: float = 6.0, duration: float = 1.0) -> void:
	if not ragdoll_rig:
		return
	if ragdoll_rig.is_ragdoll_enabled():
		return
	spring_rig.set_active(false)
	ragdoll_rig.set_ragdoll_enabled(true)
	# 等物理骨就绪（下帧）再施加头部叩冲冲量
	var fwd := -global_basis.z
	var head_impulse := Vector3(fwd.x * force, -force * 0.8, fwd.z * force)
	var body_impulse := Vector3(fwd.x * force * 0.25, 0.0, fwd.z * force * 0.25)
	call_deferred("_kowtow_impulse", head_impulse, body_impulse)
	# 磕完自动恢复站姿
	await get_tree().create_timer(duration).timeout
	if ragdoll_rig and ragdoll_rig.is_ragdoll_enabled():
		ragdoll_rig.reset()
	if spring_rig:
		spring_rig.set_active(true)

func _kowtow_impulse(head_impulse: Vector3, body_impulse: Vector3) -> void:
	if not ragdoll_rig or not ragdoll_rig.is_ragdoll_enabled():
		return
	ragdoll_rig.apply_bone_impulse("head", head_impulse)
	ragdoll_rig.apply_impulse(body_impulse)

func _ragdoll_in_use() -> bool:
	if ragdoll_rig and ragdoll_rig.is_ragdoll_enabled():
		return true
	return state_machine.current_state_name == "Stunned" or state_machine.current_state_name == "BananaSlide"

func _reset_bone_scale(bone_idx: int) -> void:
	if _model_skeleton and bone_idx != -1:
		_model_skeleton.set_bone_pose_scale(bone_idx, Vector3.ONE)

## 重置身材缩放涉及的骨到 scale=1（布娃娃/軟倒時，避免殘留放大縮小錯亂）
func _reset_body_scale() -> void:
	if not _model_skeleton:
		return
	_reset_bone_scale(_body_bone_idx)
	if _is_human_model:
		# human 放大頭部涉及頭鏈骨（名字以「骨骼.005」開頭），全部復位
		for i in _model_skeleton.get_bone_count():
			var nm := String(_model_skeleton.get_bone_name(i))
			if nm.begins_with("骨骼.005"):
				_model_skeleton.set_bone_pose_scale(i, Vector3.ONE)
	else:
		_reset_bone_scale(_head_bone_idx)
	# 帽子逆補償還原（避免軟倒後帽子大小殘留）
	if outfit_manager:
		var hat := outfit_manager.get_item("hat_slot")
		if hat:
			hat.scale = Vector3.ONE

## 設定單個動畫循環
func _set_animation_looping(anim_name: String) -> void:
	if _animation_player and _animation_player.has_animation(anim_name):
		_animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

## human 動畫按後綴名稱設為循環（Idle/Walk 循環，jump 不循環）
func _set_human_animation_looping() -> void:
	if not _animation_player:
		return
	for an in _animation_player.get_animation_list():
		var anim := _animation_player.get_animation(an)
		if an.ends_with("Idle") or an.ends_with("Walk"):
			anim.loop_mode = Animation.LOOP_LINEAR
		elif an.ends_with("jump"):
			anim.loop_mode = Animation.LOOP_NONE

## 把 human 主動畫（所有動作塞在一起的那個）按帧號拆成多個獨立子動畫。
## 源主動畫內部不同帧段是不同動作，直接播整段會「站立錯亂」。
func _split_human_idle() -> void:
	if not _animation_player:
		return
	var src_name := ""
	for an in _animation_player.get_animation_list():
		if an.begins_with("Human_"):
			continue   # 略過拆分產生的子動畫，避免用它們當源遞歸拆分
		# 組合主動畫：匹配 Idle / Idle_001 / Idle_002 等（Blender 導出可能加 _數字 尾綴）
		var lower := an.to_lower()
		if _is_combo_anim(lower):
			src_name = an
			break
	if src_name == "":
		# 找不到主動畫：退而取第一個非拆分的動畫當源
		var list := _animation_player.get_animation_list()
		for an in list:
			if not an.begins_with("Human_"):
				src_name = an
				break
	if src_name == "":
		return
	var src: Animation = _animation_player.get_animation(src_name)
	for slot_name in HUMAN_ANIM_SLOTS:
		var range_arr: Array = HUMAN_ANIM_SLOTS[slot_name]
		var f0: int = range_arr[0]
		var f1: int = range_arr[1]
		var t0 := f0 / HUMAN_ANIM_FPS
		var t1 := f1 / HUMAN_ANIM_FPS
		_slice_animation(src, t0, t1, slot_name)

## 判斷是否為「組合主動畫」（含待機/移動/飛撲多段的單一動畫）。
## newnewhuman 導出為 Idle_001；舊 human 為 Idle。特徵：名含 Idle 且時長較長（>2s）。
func _is_combo_anim(lower_name: String) -> bool:
	if not lower_name.contains("idle"):
		return false
	if _animation_player.has_animation(lower_name):
		return _animation_player.get_animation(lower_name).length > 2.0
	for an in _animation_player.get_animation_list():
		if String(an).to_lower() == lower_name:
			return _animation_player.get_animation(an).length > 2.0
	return true

## 從 source 動畫切割 [t0, t1] 時間窗口生成新動畫並加入動畫庫。
## 針對每條軌收集窗口内的關鍵幀，時間平移到 0 起。
func _slice_animation(src: Animation, t0: float, t1: float, new_name: String) -> void:
	if not _animation_player or not _animation_player.has_animation_library(""):
		return
	var lib := _animation_player.get_animation_library("")
	var dst := Animation.new()
	for t in src.get_track_count():
		var tk_type := src.track_get_type(t)
		var path: NodePath = src.track_get_path(t)
		var tk := dst.add_track(tk_type)
		dst.track_set_path(tk, path)
		# 复制轨属性
		dst.track_set_interpolation_type(tk, src.track_get_interpolation_type(t))
		var kc := src.track_get_key_count(t)
		for i in kc:
			var time := src.track_get_key_time(t, i)
			if time < t0 - 0.001 or time > t1 + 0.001:
				continue
			var v = src.track_get_key_value(t, i)
			var trans := src.track_get_key_transition(t, i)
			dst.track_insert_key(tk, time - t0, v, trans)
	dst.length = t1 - t0
	dst.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(new_name, dst)

## 依當前狀態切換動畫
func _update_animation() -> void:
	if not _animation_player:
		return
	if is_dead():
		return
	if frozen:
		_animation_player.pause()
		return
	if state_machine.current_state_name == "Stunned" or state_machine.current_state_name == "BananaSlide":
		return
	if ragdoll_rig and ragdoll_rig.is_standing_up():
		return
	var anim_name := _anim_for_state(state_machine.current_state_name)
	if anim_name != _current_anim:
		_animation_player.play(anim_name)
		_current_anim = anim_name

func _anim_for_state(state_name: String) -> String:
	if _is_human_model:
		# human 動畫：Move/Dive 可優先匹配獨立動畫；Idle 固定用拆分出的待機段（組合Idle含3段不可整播）
		match state_name:
			"Move":
				return _human_anim_or_slot("Walk", "Human_Move")
			"Dive":
				return _human_anim_or_slot("Dive", "Human_Dive")
			"Jump", "Fly":
				var j := _match_human_anim(HUMAN_ANIM_JUMP)
				return j if _is_valid_anim_name(j) else _match_slot_anim("Human_Jump")
			_:
				return _match_slot_anim("Human_Idle")
	match state_name:
		"Move":
			return ANIM_MOVE
		"Jump":
			return ANIM_JUMP
		"Dive":
			return ANIM_DIVE
		"Fly":
			# 被擊飛姿態（暫用飛撲動畫，後續可加專用被擊動畫 / 翻滾）
			return ANIM_DIVE
		_:
			return ANIM_IDLE

## human 動畫名後綴匹配：找以指定後綴結尾的動畫名；找不到退回第一個
func _match_human_anim(suffix: String) -> String:
	if not _animation_player:
		return ANIM_IDLE
	for an in _animation_player.get_animation_list():
		if an.ends_with(suffix) or an.ends_with("|" + suffix):
			return an
	var list := _animation_player.get_animation_list()
	return list[0] if list.size() > 0 else ANIM_IDLE

## 精確動畫名匹配（用於拆分出的子動畫 Human_*）；找不到退回原主動畫的後綴匹配
func _match_slot_anim(name: String) -> String:
	if _animation_player and _animation_player.has_animation(name):
		return name
	# 拆不出：退回後綴匹配（如原 jump/Walk/Idle 動畫）
	var suffix := name.replace("Human_", "")
	var s := _match_human_anim(suffix)
	if s == ANIM_IDLE:
		s = _match_human_anim(HUMAN_ANIM_IDLE)
	return s

## 嘗試用後綴直接匹配獨立動畫；無效則退回帧拆分槽動畫
func _human_anim_or_slot(suffix: String, slot: String) -> String:
	var matched := _match_human_anim(suffix)
	if _is_valid_anim_name(matched):
		return matched
	return _match_slot_anim(slot)

## 檢查動畫庫是否存在以指定後綴結尾的動畫
func _has_anim_suffix(suffix: String) -> bool:
	if not _animation_player:
		return false
	for an in _animation_player.get_animation_list():
		if an.ends_with(suffix) or an.ends_with("|" + suffix):
			return true
	return false

## 檢查動畫名是否真正存在於動畫庫（避免 _match_human_anim 找不到時回退到任意首個動畫）
func _is_valid_anim_name(name: String) -> bool:
	if name.is_empty() or name == ANIM_IDLE:
		return false
	return _animation_player != null and _animation_player.has_animation(name)

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null

## 定位換裝系統與角色效果組件
func _setup_outfit() -> void:
	outfit_manager = get_node_or_null("OutfitManager") as OutfitManager
	character_effects = get_node_or_null("CharacterEffects") as CharacterEffects

## 設定玩家顏色（走 OutfitManager + CharacterEffects 統一處理）
func apply_player_color(color: Color) -> void:
	player_color = color
	if outfit_manager:
		outfit_manager.player_color = color
	if character_effects:
		character_effects.base_color = color
