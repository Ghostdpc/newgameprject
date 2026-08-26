## 职责：飞扑状态——先立定预备（刹停停留），再向前冲击，结束后短暂僵直
## 类似立定跳远：停下来摆好姿势（0.3s），才扑出去

class_name DiveState
extends BaseState

const PREPARE_DURATION: float = 0.3
const DIVE_DURATION: float = 0.4
const RECOVER_DURATION: float = 0.5
const HIT_FORCE: float = 8.0
const HIT_UPWARD: float = 4.0
## 飞扑自身轻微腾空初速（y），让动作有高度变化而非纯贴地滑行
const DIVE_UP: float = 2.5

enum Phase { PREPARE, DIVE, RECOVER }

var _phase: Phase = Phase.PREPARE
var _phase_timer: float = 0.0
var _dive_direction: Vector3 = Vector3.ZERO
var _has_hit: bool = false

func enter() -> void:
	SoundMgr.play("dive", true)
	_phase = Phase.PREPARE
	_phase_timer = PREPARE_DURATION
	_has_hit = false
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return
	# 预备阶段先立定：刹停当前移动速度（立定跳远）
	var move_dir := controller.player_input.get_move_direction()
	if move_dir.length_squared() > 0.0:
		_dive_direction = controller.to_world_dir(move_dir)
	else:
		_dive_direction = controller.global_basis.z
	# 立即刹停水平速度，让角色原地立定
	controller.velocity.x = 0.0
	controller.velocity.z = 0.0

## 击中目标：使目标进入飞行（Fly）→ 落地倒地（Down）
func hit_target(target: PlayerController) -> void:
	if _has_hit:
		return
	_has_hit = true
	# 撞击特效固定在发起者位置中心偏前（稳定，不随目标漂移）
	if target and PropVfx:
		var hit_pos := (_player as PlayerController).global_position + _dive_direction * 0.7 + Vector3.UP * 0.5
		PropVfx.spawn_hit_shockwave(hit_pos, Color(1.0, 0.85, 0.30, 1.0))
	target.state_machine.transition_to("Fly")
	var fly := target.state_machine.get_current_state() as FlyState
	fly.launch(_dive_direction * TuneConfig.hit_force + Vector3.UP * TuneConfig.hit_upward)
	EventBus.item_used.emit(-1, null)

## 击中场景物理物：击飞物品（不影响自己继续飞扑）
func knock_prop(prop: PhysicalProp) -> void:
	var force := _dive_direction * TuneConfig.hit_force + Vector3.UP * TuneConfig.hit_upward * 0.5
	if prop.is_frozen():
		prop.release(force)
	else:
		# 速度增量 = impulse/mass。乘 mass 让撞飞速度与质量无关（重物也飞得动）；
		# 乱飞已由物品侧的击飞冷却解决，此处保持够大的撞飞力道
		prop.apply_central_impulse(force * prop.mass)
	# 撞到道具也触发爆闪（在玩家前方碰撞点）
	if PropVfx and not _has_hit:
		var prop_hit := (_player as Node3D).global_position + _dive_direction * 0.7 + Vector3.UP * 0.5
		PropVfx.spawn_hit_shockwave(prop_hit, Color(1.0, 0.9, 0.5, 1.0))

func physics_update(delta: float) -> void:
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return
	# 撞到人：立即结束冲刺，快速减速停下（不等满 RECOVER）
	if _has_hit:
		var brake := controller.ACCELERATION * 2.0 * delta
		controller.velocity.x = move_toward(controller.velocity.x, 0.0, brake)
		controller.velocity.z = move_toward(controller.velocity.z, 0.0, brake)
		if Vector2(controller.velocity.x, controller.velocity.z).length() < 0.5:
			controller.state_machine.transition_to("Idle")
		return
	match _phase:
		Phase.PREPARE:
			# 立定停留：保持静止，倒数结束后开始冲刺
			_phase_timer -= delta
			controller.velocity.x = 0.0
			controller.velocity.z = 0.0
			if _phase_timer <= 0.0:
				_phase = Phase.DIVE
				_phase_timer = DIVE_DURATION
				controller.velocity.x = _dive_direction.x * TuneConfig.dive_force
				controller.velocity.z = _dive_direction.z * TuneConfig.dive_force
				# 轻微腾空：飞扑自带高度变化（不高，落地靠重力拉回）
				if controller.is_on_floor():
					controller.velocity.y = DIVE_UP
		Phase.DIVE:
			# 冲刺阶段：保持速度，结束后进僵直
			_phase_timer -= delta
			# 撞到墙/场景（速度被挡但非撞人）→ 触发爆闪一次 + 快速停止
			if not _has_hit and controller.is_on_wall():
				_has_hit = true
				if PropVfx:
					var wall_hit := controller.global_position + _dive_direction * 0.9 + Vector3.UP * 0.55
					PropVfx.spawn_hit_shockwave(wall_hit, Color(1.0, 0.9, 0.6, 1.0))
				_phase = Phase.RECOVER
				_phase_timer = maxf(_phase_timer, 0.1)
			if _phase_timer <= 0.0:
				_phase = Phase.RECOVER
				_phase_timer = RECOVER_DURATION
		Phase.RECOVER:
			# 僵直期：衰减速度，不接受任何输入
			_phase_timer -= delta
			controller.velocity.x = move_toward(controller.velocity.x, 0.0, controller.ACCELERATION * delta)
			controller.velocity.z = move_toward(controller.velocity.z, 0.0, controller.ACCELERATION * delta)
			if _phase_timer <= 0.0 and controller.is_on_floor():
				controller.state_machine.transition_to("Idle")
