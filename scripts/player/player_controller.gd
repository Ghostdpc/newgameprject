## 职责：玩家主控制器，整合输入/状态机/物理移动/动画

class_name PlayerController
extends CharacterBody3D

const GRAVITY: float = 20.0
const ACCELERATION: float = 15.0
## 转向速率（rad/s；大=转得快，小=平滑慢转）
const TURN_RATE: float = 12.0
## 拾取有效距离（米）
const PICKUP_RANGE: float = 1.5

const ANIM_IDLE: String = "Idle_A"
const ANIM_MOVE: String = "Running_A"
const ANIM_JUMP: String = "Jump_Full_Long"
const ANIM_DIVE: String = "Jump_Full_Short"

const IDLE_SOURCE: String = "res://assets/models/mannequin/animations/Rig_Medium_General.glb"
const HumanBoneMap = preload("res://scripts/player/human_bone_map.gd")

## human 动画 FPS（模型导入 30fps）
const HUMAN_ANIM_FPS: float = 30.0
## human「主动画」内部的子段（帧号）——所有动作统一塞在同一个动画里，按帧号拆：
## 美术后续加动作时，直接在这个表里加一行即可，程式自动拆出可点播的子动画。
## {子动画名: [起始帧, 结束帧]}
const HUMAN_ANIM_SLOTS: Dictionary = {
	"Human_Idle":  [0, 30],    # 待机
	"Human_Move":  [40, 60],   # 移动
	"Human_Dive":  [70, 105],  # 飞扑
	# 之后美术把更多动作塞进主动画时，在此加一行即可（如 "Human_Jump": [106,119]）
}

## 主动画的后缀识别（美术可能命名 Idle/Walk/… 各种，取「存在」的那个）
const HUMAN_MASTER_SUFFIXES: Array[String] = ["Idle", "Walk", "Main", "Master"]

## human.fbx 原始高度约 4.456（实测），缩放到 1.0m 的精确系数
const HUMAN_MODEL_SCALE: float = 1.0 / 4.456
## human 动画名带「骨架|」前缀，用后缀匹配（Idle/Walk/jump）
const HUMAN_ANIM_IDLE: String = "Idle"
const HUMAN_ANIM_MOVE: String = "Walk"
const HUMAN_ANIM_JUMP: String = "jump"

## 拾取长按时长（秒，策划要求 0.8）
const PICKUP_HOLD_TIME: float = 0.8

## 拾取到可使用之间的间隔（秒）：捡起后需等待才能用，避免同键误触立即使用
const PICKUP_USE_GAP: float = 0.3

## 抓取距离 / 抛出速度 / 被抓起物体跟随位置（探索性功能，可删）
const GRAB_RANGE: float = 2.5
const GRAB_LIFT: float = 1.6
const THROW_SPEED: float = 5.0
## 抓取吸向手的速度（大=更快抓到；小=缓慢飞来）
const GRAB_LERP: float = 8.0
## 自爆：软倒后多久爆炸（秒）
const SELF_DESTRUCT_DELAY: float = 1.2
## 自爆波及半径（米）
const SELF_DESTRUCT_RADIUS: float = 3.0
## 自爆积分惩罚
const SELF_DESTRUCT_PENALTY: int = 30
## 自爆灰头土脸时长（秒）
const SELF_DESTRUCT_GRAY: float = 6.0

@export var jump_force: float = 8.16
## 二段跳高度（相对 jump_force 的比例；0 = 关闭二段跳）
@export var double_jump_ratio: float = 0.9

## 本空中周期是否可用二段跳（JumpState 管理）
var double_jump_available: bool = false
@export var player_index: int = 0
## 远端 puppet（client 侧渲染的玩家）：不跑本地物理/状态机，只插值 host 快照
@export var is_puppet: bool = false
## 本端预测角色（client 自己的席位）：本地模拟移动 + 宿主快照校正；道具/死亡等事件仍宿主权威
@export var is_predicted: bool = false
@export var player_color: Color = Color.WHITE
## human 模型本体 Y 轴朝向补偿（deg）。若走路侧身，在 player.tscn 调整让模型正面朝移动方向。
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

## 进入对局：随机一个表情（每轮开始调用）
func enter_match_random_face() -> void:
	if face and face.count() > 0:
		face.show_expression(randi() % face.count())

## 动作触发时轮换到下一表情
func cycle_face() -> void:
	if not face or face.count() <= 0:
		return
	var next: int = int(face.get("_current_index")) + 1
	if next >= face.count():
		next = 0
	if is_puppet:
		return  # client 端表情由 host 广播同步，puppet 不本地轮换
	face.show_expression(next)
	# host（联机）：把表情变化同步给 client 对应 puppet
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_face_changed(player_index, next)

## 持有的道具 id，空字符串表示无道具（每次最多持有一个）
var held_item_id: String = ""
## 被炸等负面效果累计的积分惩罚，快门结算时从总分扣除（clamp 到 0）
var score_penalty: int = 0
## 移速乘数（1.0 = 正常；由 player_speed_effect 临时修改）
var speed_multiplier: float = 1.0
## 身材缩放（服装效果）：head_scale 放大头部 / body_scale 放大身躯 / body_width 加宽
var head_scale: float = 1.0
var body_scale: float = 1.0
var body_width: float = 1.0
## 当前装备的服装（槽位名 -> garment_id），由 GarmentSystem 维护，评分读取用
var equipped_garments: Dictionary = {}

var _animation_player: AnimationPlayer
var _current_anim: String = ""
## 冻结（表情调试用）：暂停动画更新与状态机，角色定住
var frozen: bool = false
var _is_human_model: bool = false
var _suicide_was_pressed: bool = false
## 自爆进行中（软倒→爆炸之间防止重复触发）
var _self_destructing: bool = false
## puppet 快照缓冲（client 侧远端表现插值：缓冲 + 双快照插值，吸收网络抖动）
const PUPPET_INTERP_DELAY_MS: int = 100
const PUPPET_BUFFER_MAX_MS: int = 500
var _puppet_buffer: Array = []  # {t: int, pos: Vector3, vel: Vector3, yaw: float}
## 本端预测：宿主校正阈值（米），超阈值才拉回，避免连续移动橡皮筋
const PREDICTION_CORRECTION_THRESHOLD: float = 1.5
var _prediction_active: bool = true
## 待未确认输入（reconciliation：idle 阶段只快照拉回，物理帧再重放补位）
var _reconcile_queue: Array = []
var _model_skeleton: Skeleton3D
var _head_bone_idx: int = -1
var _body_bone_idx: int = -1
var _model_node: Node3D
var _body_collision: CollisionShape3D
var _body_mask_saved: int = -1

var _pickup_hold_time: float = 0.0
## 长按期间已锁定的拾取目标 spawn_id（-1=未锁定）。拾取判定帧锁定并豁免朝向门槛，
## 避免转身稍偏就丢失目标、白按 0.8s 拾不到（联机远端尤为常见）
var _pickup_target_spawn_id: int = -1
## 捡起后剩余的使用冷却（秒），>0 时 O 键不触发使用
var _use_gap_time: float = 0.0
var _grabbed_prop: PhysicalProp = null
var _head_icon: PlayerHeadIcon

## 是否处于死亡/复活流程（非正常对战状态）
func is_dead() -> bool:
	if state_machine == null:
		return false
	var st := state_machine.current_state_name
	return st == "Death" or st == "RespawnWaiting" or st == "RespawnFall"

## 香蕉皮踩中：进入倒地滑行状态（沿途撞人，类似飞扑）
func start_banana_slide() -> void:
	if is_dead():
		return
	state_machine.transition_to("BananaSlide")

func _ready() -> void:
	player_input = _create_input_provider()
	# 身材缩放要排在动画(priority 0)与弹簧骨骼(100)之后，避免骨骼 scale 被动画覆盖
	process_priority = 100
	if is_puppet:
		_setup_outfit()  # 先就绪 character_effects，供 _setup_model 的表情贴头材质使用
		_setup_model()
	else:
		_setup_state_machine()
		_setup_outfit()
		_setup_model()
	_head_icon = get_node_or_null("PlayerHeadIcon") as PlayerHeadIcon
	apply_player_color(player_color)
	add_to_group("players")
	NetManager.register_player(self)
	EventBus.battle_started.connect(func(): score_penalty = 0)

func _exit_tree() -> void:
	NetManager.unregister_player(self)

## 依据席位所有权选择输入源：host 上远端席位用 RemoteInputProvider，其余本地直读
func _create_input_provider() -> PlayerInput:
	if is_puppet:
		return PlayerInput.new(player_index)  # puppet 不读输入，仅占位
	if NetManager.is_online and NetManager.is_host:
		var owner := NetManager.get_seat_owner(player_index)
		if owner["kind"] == NetManager.SeatKind.REMOTE:
			var remote := RemoteInputProvider.new(player_index)
			NetManager.register_remote_input(player_index, remote)
			return remote
	return PlayerInput.new(player_index)

## 开关布娃娃（被击倒时进入物理倒地）
func set_ragdoll(enabled: bool) -> void:
	if ragdoll_rig:
		ragdoll_rig.set_ragdoll_enabled(enabled)
	# 布娃娃时关闭弹簧骨骼，避免与物理姿态抢写骨架
	if spring_rig:
		spring_rig.set_active(not enabled)
	# 物理骨 layer=4 启用碰撞后会挡住/推开玩家碰撞体（玩家 mask 含 4）。
	# ragdoll 期间把玩家 mask 移除物理骨层，让碰撞体不被瘫软的骨骼挤开/挡路。
	if enabled:
		_body_mask_saved = collision_mask
		collision_mask = _body_mask_saved & ~4
	else:
		if _body_mask_saved != -1:
			collision_mask = _body_mask_saved
			_body_mask_saved = -1

## 击飞：body 位移（模型跟 body，姿态由 ragdoll 提供）
func knockback(direction: Vector3) -> void:
	velocity = direction

## 瘫软时 body 跟随物理骨落点（贴地），站起前也用它对齐避免漂移
func sync_body_to_ragdoll() -> void:
	if not ragdoll_rig:
		return
	var hips_pos := ragdoll_rig.get_hips_position()
	if hips_pos == Vector3.ZERO:
		return
	# 对齐 hips 水平位置；Y 限制在地面之上（≥0），避免碰撞体穿到地面下
	var body_y := maxf(hips_pos.y, 0.0)
	global_position = Vector3(hips_pos.x, body_y, hips_pos.z)
	velocity.y = 0.0

## 出界死亡：进入死亡状态（清道具、藏体、停物理）
func die() -> void:
	SoundMgr.play("die")
	if state_machine.current_state_name == "Death":
		return
	death_started.emit(self)
	state_machine.transition_to("Death")

## 配置重生（由 LevelBase 设定复活点与读秒时长）
func configure_respawn(spawn_pos: Vector3, wait_duration: float) -> void:
	var waiting := state_machine.get_state("RespawnWaiting") as RespawnWaitingState
	if waiting:
		waiting.configure(spawn_pos, wait_duration)

## 倒地后站起，由调用方确保已关闭 ragdoll
func stand_up() -> void:
	if ragdoll_rig:
		ragdoll_rig.reset()

## 拾取道具（覆盖式：新道具直接替换当前持有；ON_PICKUP 触发器立即使用）
func pickup_item(item_id: String) -> void:
	held_item_id = item_id
	_use_gap_time = PICKUP_USE_GAP
	item_picked_up.emit(item_id)
	EventBus.item_picked_up.emit(player_index, item_id)
	# 联机：host 广播拾取，client 同步 HUD/图标
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_item_picked_up(player_index, item_id)
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
	if is_puppet:
		return
	if is_dead():
		return
	if frozen:
		return
	# 本端预测：死亡/复活期间本地模拟暂停，按宿主快照插值表现
	if is_predicted and not _prediction_active:
		return
	if spring_rig:
		spring_rig.velocity_hints = Vector2(velocity.x, velocity.z)
		spring_rig.root_velocity = velocity
	if GameManager.current_stage == GameManager.GameStage.SCORING:
		return
	# 玩法慢放：只影响玩家状态机/动画，不动 UI（Engine.time_scale 全局慢放已被替换）
	var scale := NetManager.gameplay_time_scale
	if _animation_player:
		_animation_player.speed_scale = scale
	state_machine.update(delta * scale)
	_update_animation()
	_apply_body_scale()
	if _use_gap_time > 0.0:
		_use_gap_time -= delta * scale
	# 本端预测：道具拾取/使用由宿主权威广播，不本地执行
	if is_predicted:
		return
	if player_input.is_use_item_just_pressed():
		if not held_item_id.is_empty():
			# 身上有道具：捡起后需过间隔才能使用
			if _use_gap_time <= 0.0:
				use_held_item()
		else:
			# 身上无道具：尝试拾取附近道具
			_try_pickup()
	# 长按拾取兜底：联机按下沿（edge）依赖上行推导，双开/卡顿下行上行频率低，
	# 快速按键覆盖帧少、edge 易丢；held(level) 对丢帧免疫，按住 0.8s 兜底拾取
	_update_pickup_hold(delta * scale)

## 长按拾取逻辑：按住 0.8s 触发；移动/受控 打断
func _update_pickup_hold(delta: float) -> void:
	# 已有道具时不再拾取（避免即时拾取成功后长按再覆盖一次）
	if not held_item_id.is_empty():
		_pickup_hold_time = 0.0
		_pickup_target_spawn_id = -1
		return
	# 拾取可被打断：移动 / 非 Idle/Move 状态
	var st := state_machine.current_state_name
	var can_pickup := (st == "Idle" or st == "Move") and _pickup_movement_blocked() == false
	if not can_pickup:
		_pickup_hold_time = 0.0
		_pickup_target_spawn_id = -1
		return
	if player_input.is_pickup_held():
		# 长按期间在范围内锁定一个目标（只在未锁定时选，避免每帧跳目标）
		if _pickup_target_spawn_id == -1:
			var target := _find_candidate()
			if target != null:
				_pickup_target_spawn_id = int(target.get("spawn_id"))
		_pickup_hold_time += delta
		if _pickup_hold_time >= PICKUP_HOLD_TIME:
			_pickup_hold_time = 0.0
			_try_pickup()
	else:
		_pickup_hold_time = 0.0
		_pickup_target_spawn_id = -1

## 拾取长按时如果正在移动则中断（策划：移动会打断拾取）
func _pickup_movement_blocked() -> bool:
	# 阈值 0.04（约 0.2 速）：联机 _move 为网络值可能有残留/噪声，
	# 键盘 WASD(1.0) 正常打断，微小残留不误打断
	return player_input.get_move_direction().length_squared() > 0.04

func _try_pickup() -> void:
	var result := _pickup_nearest()
	if result.is_empty():
		# 已锁定目标但瞬时判定失败（目标刚离场/触发后落地中）：清锁，等下次长按重试
		if _pickup_target_spawn_id != -1:
			_pickup_target_spawn_id = -1
		return
	var id: String = result["id"]
	var is_garment: bool = result.get("is_garment", false)
	_pickup_target_spawn_id = -1
	if is_garment:
		GarmentSystem.equip_garment(self, id)
	else:
		pickup_item(id)

## 拾取：找最近的 pickup_items 成员，返回 { id, is_garment, spawn_id } 或 {}
func _pickup_nearest() -> Dictionary:
	var nearest := _find_candidate()
	if nearest == null:
		return {}
	var id: String = nearest.pickup_for(self)
	if id.is_empty():
		return {}
	# 联机：host 广播实体消失，client 释放对应道具箱/服装
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_entity_despawn(int(nearest.get("spawn_id")))
	var is_garment := nearest.is_in_group("garment_pickups")
	return { "id": id, "is_garment": is_garment, "spawn_id": int(nearest.get("spawn_id")) }

## 找当前可拾取的候选节点（不销毁、不调用 pickup_for），长按锁定与最终拾取共用
func _find_candidate() -> Node3D:
	var items := get_tree().get_nodes_in_group("pickup_items")
	if items.is_empty():
		return null
	var fwd := global_basis.z
	var range_sq := PICKUP_RANGE * PICKUP_RANGE
	# 已锁定目标：优先直接找它（豁免朝向门槛，长按中转身不丢目标）
	if _pickup_target_spawn_id != -1:
		for item in items:
			var locked := item as Node3D
			if locked and int(locked.get("spawn_id")) == _pickup_target_spawn_id:
				var lto := locked.global_position - global_position
				lto.y = 0.0
				if lto.length_squared() <= range_sq and locked.has_method("pickup_for"):
					return locked
				break
		# 锁定目标失效：清锁，走常规评分
		_pickup_target_spawn_id = -1
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
		# 直立于道具正上方（水平距离极小）时，水平朝向无意义 → 直接允许拾取
		if dist > PICKUP_RANGE:
			continue
		var score: float
		if dist <= 0.3:
			# 贴身/正上方：不受朝向限制
			score = 1.0 - dist / PICKUP_RANGE * 0.25
		else:
			var facing := to.normalized().dot(fwd)
			if facing < 0.15:
				continue
			score = facing - dist / PICKUP_RANGE * 0.5
		if score > best_score:
			best_score = score
			nearest = n
	return nearest

func _physics_process(delta: float) -> void:
	if is_puppet:
		_puppet_physics(delta)
		return
	var scale := NetManager.gameplay_time_scale
	# 本端预测：只本地模拟移动（重力和状态机），自杀/飞扑撞击/推物/抓取/拾取等由宿主权威
	if is_predicted:
		if not _prediction_active:
			_puppet_physics(delta)
			return
		if not _reconcile_queue.is_empty():
			# 校正重放补位：本帧重放未确认输入，跳过常规模拟（下帧继续）
			_replay_pending()
			return
		_apply_gravity(delta * scale)
		state_machine.physics_update(delta * scale)
		move_and_slide()
		return
	# 死亡/复活状态也需物理帧推进（Death→Waiting→Fall），故不整体跳过
	_apply_gravity(delta * scale)
	if is_dead():
		state_machine.physics_update(delta * scale)
		move_and_slide()
		return
	_handle_suicide()
	if GameManager.current_stage == GameManager.GameStage.SCORING:
		velocity.x = move_toward(velocity.x, 0.0, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCELERATION * delta)
		move_and_slide()
		return
	state_machine.physics_update(delta * scale)
	move_and_slide()
	_check_dive_hit()
	_push_contacted_props()
	_update_grab(delta)

# ---------------------------------------------------------------- 远端 puppet

## 写入远端快照（client 侧，由 NetManager 广播驱动；缓冲后延迟插值 + 速度外推）。
## t_msec 为宿主时间戳换算到本端时间线，非本端到达时刻（网络抖动不进插值轴）。
func apply_remote_state(pos: Vector3, vel: Vector3, state_name: String, yaw: float, t_msec: int) -> void:
	_puppet_buffer.append({"t": t_msec, "pos": pos, "vel": vel, "yaw": yaw})
	while not _puppet_buffer.is_empty() and t_msec - int(_puppet_buffer[0]["t"]) > PUPPET_BUFFER_MAX_MS:
		_puppet_buffer.pop_front()
	_puppet_update_animation(state_name)

## 本端预测可本地模拟的基础移动状态（其余战斗/死亡状态由宿主权威，暂停本地模拟并插值表现）。
## Dive 不在列：飞扑命中是宿主权威，本地预测位移会在命中瞬间被拉回，改为宿主权威插值 + 命中事件。
const PREDICTED_LOCAL_STATES: Array = ["Idle", "Move", "Jump"]

## 本端预测校正：宿主快照拉回（非基础移动状态暂停本地模拟，其余超阈值才拉回 + 输入重放）
func apply_prediction_correction(pos: Vector3, vel: Vector3, state_name: String, yaw: float, t_msec: int, ack_seq: int = -1) -> void:
	if not PREDICTED_LOCAL_STATES.has(state_name):
		_prediction_active = false
		_puppet_buffer.append({"t": t_msec, "pos": pos, "vel": vel, "yaw": yaw})
		while not _puppet_buffer.is_empty() and t_msec - int(_puppet_buffer[0]["t"]) > PUPPET_BUFFER_MAX_MS:
			_puppet_buffer.pop_front()
		_puppet_update_animation(state_name)
		return
	_prediction_active = true
	_puppet_buffer.clear()
	if global_position.distance_to(pos) > PREDICTION_CORRECTION_THRESHOLD:
		global_position = pos
		velocity = vel
		rotation.y = yaw
		NetManager.drop_acked_inputs(player_index, ack_seq)
		_reconcile_queue = NetManager.take_pending_inputs(player_index)

## reconciliation 重放：宿主权威快照已拉回，本物理帧把未确认输入重放补位（catch-up）。
## 必须在 _physics_process 内跑（move_and_slide 仅物理帧合法），故由 idle 阶段的校正只入队。
## 用固定物理 tick 逐条重演（非当前帧 delta，避免帧率漂移），单帧步数设上限防尖峰。
const REPLAY_MAX_STEPS: int = 12  # 单帧最多重放步数，超出的旧输入丢弃（下轮校正再收敛）

func _replay_pending() -> void:
	var pending := _reconcile_queue
	_reconcile_queue = []
	if pending.is_empty():
		return
	var start := 0
	if pending.size() > REPLAY_MAX_STEPS:
		start = pending.size() - REPLAY_MAX_STEPS
	var tick := get_physics_process_delta_time() * NetManager.gameplay_time_scale
	var real_input := player_input
	var replay := ReplayInputProvider.new(player_index)
	replay.set_entries(pending)
	player_input = replay
	for i in range(start, pending.size()):
		replay.step(i)
		_apply_gravity(tick)
		state_machine.physics_update(tick)
		move_and_slide()
	player_input = real_input

## 远端 puppet：宿主广播的飞扑命中反馈（true=被击飞切 Fly，false=撞物自己倒地切 Stunned）
func apply_dive_hit_feedback(target_was_player: bool) -> void:
	if target_was_player:
		_puppet_update_animation("Fly")
	else:
		_puppet_update_animation("Stunned")

## puppet 插值：按延迟缓冲在相邻快照间插值（抖动吸收）；单快照时用速度外推
func _puppet_physics(_delta: float) -> void:
	if _animation_player:
		_animation_player.speed_scale = NetManager.gameplay_time_scale
	var now := Time.get_ticks_msec()
	var target_t := now - PUPPET_INTERP_DELAY_MS
	if _puppet_buffer.is_empty():
		return
	if _puppet_buffer.size() == 1 or target_t >= int(_puppet_buffer[-1]["t"]):
		var latest: Dictionary = _puppet_buffer[-1]
		var ahead := maxf(0.0, float(target_t - int(latest["t"])) / 1000.0)
		global_position = (latest["pos"] as Vector3) + (latest["vel"] as Vector3) * ahead
		rotation.y = latest["yaw"]
		return
	if target_t <= int(_puppet_buffer[0]["t"]):
		global_position = _puppet_buffer[0]["pos"]
		rotation.y = _puppet_buffer[0]["yaw"]
		return
	for i in range(_puppet_buffer.size() - 1):
		var a: Dictionary = _puppet_buffer[i]
		var b: Dictionary = _puppet_buffer[i + 1]
		var ta: int = a["t"]
		var tb: int = b["t"]
		if ta <= target_t and target_t <= tb:
			var span := tb - ta
			var alpha := 0.5 if span <= 0 else clampf(float(target_t - ta) / float(span), 0.0, 1.0)
			global_position = (a["pos"] as Vector3).lerp(b["pos"] as Vector3, alpha)
			rotation.y = lerp_angle(a["yaw"], b["yaw"], alpha)
			return

## puppet 动画：按 host 状态名切动画（远端不做 ragdoll，用 canned 动画）
func _puppet_update_animation(state_name: String) -> void:
	if not _animation_player:
		return
	var anim := _anim_for_state(state_name)
	if anim != _current_anim:
		_animation_player.play(anim)
		_current_anim = anim

## 自爆（原自杀，测试用）：按下后先软倒，然后爆炸，再走死亡+复活流程
func _handle_suicide() -> void:
	var pressed := player_input.is_suicide_just_pressed()
	if pressed and not _suicide_was_pressed and not _self_destructing and not is_dead():
		_start_self_destruct()
	_suicide_was_pressed = pressed

## 自爆：进入软倒(Stunned)，延迟后爆炸并触发死亡复活
func _start_self_destruct() -> void:
	_self_destructing = true
	state_machine.transition_to("Stunned")
	if not is_dead():
		# 软倒片刻后爆炸
		var timer := get_tree().create_timer(SELF_DESTRUCT_DELAY)
		timer.timeout.connect(_explode_self)

## 自爆爆炸：复用炸弹爆炸特效 + 波及周边玩家，随后走死亡复活
func _explode_self() -> void:
	_self_destructing = false
	SoundMgr.play("explode")
	var scene := get_tree().current_scene
	if scene:
		BombInstance.spawn_explosion_fx(global_position, scene, SELF_DESTRUCT_RADIUS)
	# 波及范围内其他玩家（复用炸弹的灰头土脸+积分惩罚+击飞）
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as PlayerController
		if other == null or other == self:
			continue
		var d := global_position.distance_to(other.global_position)
		if d > SELF_DESTRUCT_RADIUS:
			continue
		if other.character_effects:
			other.character_effects.apply_dirt_decal(SELF_DESTRUCT_GRAY)
		other.score_penalty += SELF_DESTRUCT_PENALTY
		_blast_knockback(other, d)
	# 自爆者自己：出界下方交 LevelBase 走死亡+复活流程
	global_position.y = -100.0

## 自爆击飞周边玩家（复用炸弹的 _knockback_player 逻辑）
func _blast_knockback(player: PlayerController, dist: float) -> void:
	if player == null or player.state_machine == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dir := to_player.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.1, 0.0, 0.1).normalized()
	var falloff := clampf(1.0 - dist / maxf(SELF_DESTRUCT_RADIUS, 0.01), 0.4, 1.0)
	var blast := TuneConfig.hit_force * 1.4 * falloff
	var up := TuneConfig.hit_upward * 1.3 * falloff
	player.state_machine.transition_to("Fly")
	var fly := player.state_machine.get_current_state() as FlyState
	if fly:
		fly.launch(dir * blast + Vector3.UP * up)

## 玩家移动时推动接触到的场景物理物（解决 move_and_slide 卡住不推）
func _push_contacted_props() -> void:
	# 用输入方向而非 velocity（顶住箱子时 velocity 会被归零，输入方向仍有效）
	var input_dir := player_input.get_move_direction()
	if input_dir.length_squared() < 0.01:
		return
	var push_dir := to_world_dir(input_dir)
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PhysicalProp:
			(collider as PhysicalProp).push(push_dir)

## 抓取更新：R 键按住 → 抓起/跟随面前物理物；松开 → 抛出
func _update_grab(delta: float) -> void:
	if _grabbed_prop != null:
		# 抓取点随物品尺寸：前置距离=深度一半+间隙，抬升=高度/2（避免大件卡身位）
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
			# 松开：跑动中 = 带著玩家速度抛出；静止 = 原地放下（只留很小前向）
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

## 物品碰撞半尺寸（xyz），用于调整抓取点位置避免大件卡身位。无碰撞/未知时返回原固定档位。
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

## 找最近的可抓取场景物件（group "physical_prop"，距离内）
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

## 飞扑状态碰撞检测：撞到玩家→击飞对方倒地；撞到场景物理物→击飞物品 + 自己倒地
## 命中纯宿主物理：host 侧广播命中事件，client 靠事件同步 VFX/反馈时序（不靠 state 名+位置推断）
func _check_dive_hit() -> void:
	if state_machine.current_state_name != "Dive":
		return
	var dive := state_machine.get_current_state() as DiveState
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PlayerController:
			var was_hit := dive.is_hit()
			dive.hit_target(collider as PlayerController)
			if not was_hit and NetManager.is_online and NetManager.is_host:
				NetManager.broadcast_dive_hit(player_index, (collider as PlayerController).player_index, false, global_position)
		elif collider is PhysicalProp:
			dive.knock_prop(collider as PhysicalProp)
			# 撞到物品自己也立刻停下并进入倒地（与被撞同等）
			SoundMgr.play("hit")
			_knocked_down_by_prop(dive)
			if NetManager.is_online and NetManager.is_host:
				NetManager.broadcast_dive_hit(player_index, -1, true, global_position)
			return

## 撞到物品后自己倒地：立即停下 + 进入 Stunned（布娃娃瘫软）
func _knocked_down_by_prop(dive: DiveState) -> void:
	velocity = Vector3.ZERO
	state_machine.transition_to("Stunned")

func apply_move(direction: Vector2) -> void:
	var world_dir := to_world_dir(direction)
	var target_velocity := world_dir * TuneConfig.move_speed * speed_multiplier
	var dt := get_physics_process_delta_time() * NetManager.gameplay_time_scale
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * dt)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * dt)
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

## 平滑转身：模型正面朝 +Z，用 yaw 角度插值（避免 slerp 在 180° 退化导致瞬移）
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
	rotation.y = lerp_angle(cur_yaw, target_yaw, minf(1.0, TURN_RATE * get_physics_process_delta_time() * NetManager.gameplay_time_scale))

func _apply_gravity(delta: float) -> void:
	if is_dead():
		return
	if not is_on_floor():
		# Fly 阶段由 FlyState 自行管理重力（可自定义下坠）
		if state_machine.current_state_name == "Fly":
			return
		# 被击飞期间用更大重力，让上升/下降都更快
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

## 定位模型骨架与动画播放器
func _setup_model() -> void:
	var model := get_node_or_null("Model")
	if not model:
		return
	_animation_player = _find_animation_player(model)
	# human 模型检测：动画名以「骨架|」开头（KayKit 为 Idle_A 等），缩小 10 倍 + 转前向
	_is_human_model = _is_human_skel(model)
	if _is_human_model:
		# human 骨骼 pose 由动画直接驱动。做正确缩放 + Y 轴朝向补偿（前向对齐 +Z）。
		model.scale = Vector3.ONE * HUMAN_MODEL_SCALE
		model.rotation.y = deg_to_rad(human_model_yaw_deg)
		# 模型自带 OmniLight 随玩家移动造成泛白/发光，移除之
		_remove_embedded_lights(model)
		# 原模型材质为纯白 unshaded（泛白主因），改为受光照的标准材质 + 玩家色
		_apply_human_material(model)
		# human 自带动画，不 merge KayKit Idle（骨骼名不匹配会报警）
		_set_human_animation_looping()
		# 组合主动画（Idle/Idle_001 含待机+移动+飞扑多段）必须按帧拆出待机段，
		# 即使有独立 Walk/jump 也要拆（待机只用组合里的待机段）
		_split_human_idle()
	else:
		_merge_idle_animation()
		_set_animation_looping(ANIM_IDLE)
		_set_animation_looping(ANIM_MOVE)
		_set_animation_looping(ANIM_JUMP)
		_set_animation_looping(ANIM_DIVE)
	# 远端 puppet：仅渲染模型与动画，不建布娃娃/弹簧骨骼/身材缩放（物理由 host 权威模拟）
	if is_puppet:
		_model_skeleton = _find_skeleton(model)
		face = get_node_or_null("Face") as PlayerFaceController
		if face and _model_skeleton:
			face.setup(_model_skeleton)
			# 与 host 同渲染路径：表情贴头部材质（Sprite3D 贴骨在部分模型上不可见/穿帮）
			face.use_head_texture = true
			if not face.apply_head_texture():
				face.use_head_texture = false
		return
	# 初始化布娃娃（绑定模型骨架）
	ragdoll_rig = get_node_or_null("RagdollRig") as RagdollRig
	if ragdoll_rig:
		var skeleton := _find_skeleton(model)
		if skeleton and _animation_player:
			ragdoll_rig.is_human = _is_human_model
			ragdoll_rig.body_root = self
			ragdoll_rig.setup(skeleton, _animation_player)
	# Spring Bone 弹簧骨骼：常态软糯效果（挂本角色，高 priority 在动画后写回）
	spring_rig = SpringBoneRig.new()
	spring_rig.name = "SpringBoneRig"
	add_child(spring_rig)
	var skel2 := _find_skeleton(model)
	if skel2 and _animation_player:
		spring_rig.skeleton = skel2
		spring_rig.animation_player = _animation_player
		spring_rig.is_human = _is_human_model
		# 保留 head 进 spring（磕头 kowtow 效果需 head spring）；帽子随磕头左右晃属合理演出
		spring_rig.apply_preset("normal")
		spring_rig.setup(skel2, _animation_player)
		spring_rig.set_active(true)
	# 软倒起身后骨骼姿态大变：重设弹簧状态对齐站姿，避免 head 弹簧残留旧态
	# 与服装头骨缩放(1.8)叠加，导致蘑菇帽软倒后悬空漂走。
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
		# 若有模型带独立脸片（newnewhuman），自动改贴脸到脸片材质；无则保持平面贴纸
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

## 判定是否 human 模型（骨架含 Blender 默认骨名「骨骼.」）
func _is_human_skel(model: Node3D) -> bool:
	var skel := _find_skeleton(model) as Skeleton3D
	if skel:
		for i in skel.get_bone_count():
			if String(skel.get_bone_name(i)).begins_with("骨骼"):
				return true
	return false

## 移除模型自带的光源节点（human.fbx 带一个 OmniLight，会造成泛白/发光）
func _remove_embedded_lights(model: Node3D) -> void:
	for l in model.find_children("*", "Light3D", true, false):
		l.queue_free()

## 覆盖 human 模型的纯白 unshaded 材质：改为受光照、带玩家色，消除整片泛白
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

## 从 General.glb 合并 Idle 动画（MovementBasic 无待机动画）
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
		# 布娃娃/软倒：重置身材缩放，物理接管骨骼姿态（避免残留缩放错乱）
		_reset_body_scale()
		return
	if _body_bone_idx != -1:
		_model_skeleton.set_bone_pose_scale(_body_bone_idx, Vector3.ONE * body_scale)
	if _head_bone_idx != -1:
		if _is_human_model:
			# human：实测「骨骼.004」放大时头会变大（body_scale 验证），故 head_scale 也用它放大头。
			# 身体放大用根骨「骨骼.001」（4157顶点=身体主体）。
			var head_scale_v := head_scale / maxf(body_scale, 0.01)
			var body_scale_v := maxf(body_scale, 0.01)
			for i in _model_skeleton.get_bone_count():
				var nm := String(_model_skeleton.get_bone_name(i))
				# 不缩放「骨骼.005_end_end_end_end」（帽子挂点骨），避免挂点被 scale 拉走/帽子乱
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

## 帽子挂在头骨会随头放大而放大；设逆缩放保持帽子视觉尺寸不爆大。
## user_hat_scale_mult 供外部（garment_demo）手动微调帽子大小。
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
			# human 整体缩放基为 HUMAN_MODEL_SCALE，加宽只放大 X
			_model_node.scale.x = HUMAN_MODEL_SCALE * body_width
		else:
			_model_node.scale.x = body_width
	if _body_collision:
		var shape := _body_collision.shape as CapsuleShape3D
		if shape:
			shape.radius = 0.4 * maxf(1.0, maxf(body_width, body_scale))

## 外部（联机 client 换装同步等）变更身材缩放后，显式刷新骨架缩放。
## puppet 的 _process 会跳过 _apply_body_scale，需手动触发一次。
func refresh_body_scale() -> void:
	_apply_body_scale()

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

## 重置身材缩放涉及的骨到 scale=1（布娃娃/软倒时，避免残留放大缩小错乱）
func _reset_body_scale() -> void:
	if not _model_skeleton:
		return
	_reset_bone_scale(_body_bone_idx)
	if _is_human_model:
		# human 放大头部涉及头链骨（名字以「骨骼.005」开头），全部复位
		for i in _model_skeleton.get_bone_count():
			var nm := String(_model_skeleton.get_bone_name(i))
			if nm.begins_with("骨骼.005"):
				_model_skeleton.set_bone_pose_scale(i, Vector3.ONE)
	else:
		_reset_bone_scale(_head_bone_idx)
	# 帽子逆补偿还原（避免软倒后帽子大小残留）
	if outfit_manager:
		var hat := outfit_manager.get_item("hat_slot")
		if hat:
			hat.scale = Vector3.ONE

## 设定单个动画循环
func _set_animation_looping(anim_name: String) -> void:
	if _animation_player and _animation_player.has_animation(anim_name):
		_animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

## human 动画按后缀名称设为循环（Idle/Walk 循环，jump 不循环）
func _set_human_animation_looping() -> void:
	if not _animation_player:
		return
	for an in _animation_player.get_animation_list():
		var anim := _animation_player.get_animation(an)
		if an.ends_with("Idle") or an.ends_with("Walk"):
			anim.loop_mode = Animation.LOOP_LINEAR
		elif an.ends_with("jump"):
			anim.loop_mode = Animation.LOOP_NONE

## 把 human 主动画（所有动作塞在一起的那个）按帧号拆成多个独立子动画。
## 源主动画内部不同帧段是不同动作，直接播整段会「站立错乱」。
func _split_human_idle() -> void:
	if not _animation_player:
		return
	var src_name := ""
	for an in _animation_player.get_animation_list():
		if an.begins_with("Human_"):
			continue   # 略过拆分产生的子动画，避免用它们当源递归拆分
		# 组合主动画：匹配 Idle / Idle_001 / Idle_002 等（Blender 导出可能加 _数字 尾缀）
		var lower := an.to_lower()
		if _is_combo_anim(lower):
			src_name = an
			break
	if src_name == "":
		# 找不到主动画：退而取第一个非拆分的动画当源
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

## 判断是否为「组合主动画」（含待机/移动/飞扑多段的单一动画）。
## newnewhuman 导出为 Idle_001；旧 human 为 Idle。特征：名含 Idle 且时长较长（>2s）。
func _is_combo_anim(lower_name: String) -> bool:
	if not lower_name.contains("idle"):
		return false
	if _animation_player.has_animation(lower_name):
		return _animation_player.get_animation(lower_name).length > 2.0
	for an in _animation_player.get_animation_list():
		if String(an).to_lower() == lower_name:
			return _animation_player.get_animation(an).length > 2.0
	return true

## 从 source 动画切割 [t0, t1] 时间窗口生成新动画并加入动画库。
## 针对每条轨收集窗口内的关键帧，时间平移到 0 起。
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

## 依当前状态切换动画
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
		# human 动画：Move/Dive 可优先匹配独立动画；Idle 固定用拆分出的待机段（组合Idle含3段不可整播）
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
			# 被击飞姿态（暂用飞扑动画，后续可加专用被击动画 / 翻滚）
			return ANIM_DIVE
		_:
			return ANIM_IDLE

## human 动画名后缀匹配：找以指定后缀结尾的动画名；找不到退回第一个
func _match_human_anim(suffix: String) -> String:
	if not _animation_player:
		return ANIM_IDLE
	for an in _animation_player.get_animation_list():
		if an.ends_with(suffix) or an.ends_with("|" + suffix):
			return an
	var list := _animation_player.get_animation_list()
	return list[0] if list.size() > 0 else ANIM_IDLE

## 精确动画名匹配（用于拆分出的子动画 Human_*）；找不到退回原主动画的后缀匹配
func _match_slot_anim(name: String) -> String:
	if _animation_player and _animation_player.has_animation(name):
		return name
	# 拆不出：退回后缀匹配（如原 jump/Walk/Idle 动画）
	var suffix := name.replace("Human_", "")
	var s := _match_human_anim(suffix)
	if s == ANIM_IDLE:
		s = _match_human_anim(HUMAN_ANIM_IDLE)
	return s

## 尝试用后缀直接匹配独立动画；无效则退回帧拆分槽动画
func _human_anim_or_slot(suffix: String, slot: String) -> String:
	var matched := _match_human_anim(suffix)
	if _is_valid_anim_name(matched):
		return matched
	return _match_slot_anim(slot)

## 检查动画库是否存在以指定后缀结尾的动画
func _has_anim_suffix(suffix: String) -> bool:
	if not _animation_player:
		return false
	for an in _animation_player.get_animation_list():
		if an.ends_with(suffix) or an.ends_with("|" + suffix):
			return true
	return false

## 检查动画名是否真正存在于动画库（避免 _match_human_anim 找不到时回退到任意首个动画）
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

## 定位换装系统与角色效果组件
func _setup_outfit() -> void:
	outfit_manager = get_node_or_null("OutfitManager") as OutfitManager
	character_effects = get_node_or_null("CharacterEffects") as CharacterEffects

## 设定玩家颜色（走 OutfitManager + CharacterEffects 统一处理）
func apply_player_color(color: Color) -> void:
	player_color = color
	if outfit_manager:
		outfit_manager.player_color = color
	if character_effects:
		character_effects.base_color = color
