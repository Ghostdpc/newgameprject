## 職責：飛撲狀態——先立定預備（刹停停留），再向前衝擊，結束後短暫僵直
## 類似立定跳遠：停下來擺好姿勢（0.3s），才撲出去

class_name DiveState
extends BaseState

const PREPARE_DURATION: float = 0.3
const DIVE_DURATION: float = 0.4
const RECOVER_DURATION: float = 0.5
const HIT_FORCE: float = 8.0
const HIT_UPWARD: float = 4.0

enum Phase { PREPARE, DIVE, RECOVER }

var _phase: Phase = Phase.PREPARE
var _phase_timer: float = 0.0
var _dive_direction: Vector3 = Vector3.ZERO
var _has_hit: bool = false

func enter() -> void:
	_phase = Phase.PREPARE
	_phase_timer = PREPARE_DURATION
	_has_hit = false
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return
	# 預備階段先立定：刹停當前移動速度（立定跳遠）
	var move_dir := controller.player_input.get_move_direction()
	if move_dir.length_squared() > 0.0:
		_dive_direction = Vector3(move_dir.x, 0.0, move_dir.y).normalized()
	else:
		_dive_direction = controller.global_basis.z
	# 立即刹停水平速度，讓角色原地立定
	controller.velocity.x = 0.0
	controller.velocity.z = 0.0

## 擊中目標：使目標進入飛行（Fly）→ 落地倒地（Down）
func hit_target(target: PlayerController) -> void:
	if _has_hit:
		return
	_has_hit = true
	target.state_machine.transition_to("Fly")
	var fly := target.state_machine.get_current_state() as FlyState
	fly.launch(_dive_direction * TuneConfig.hit_force + Vector3.UP * TuneConfig.hit_upward)
	EventBus.item_used.emit(-1, null)

## 擊中場景物理物：擊飛物品（不影響自己繼續飛撲）
func knock_prop(prop: PhysicalProp) -> void:
	var force := _dive_direction * TuneConfig.hit_force + Vector3.UP * TuneConfig.hit_upward * 0.5
	if prop.is_frozen():
		prop.release(force)
	else:
		# apply_central_impulse 直接給 Δ動量（速度增量 = impulse/mass），不另乘 mass，
		# 否則重物也獲相等速度瞬間爆飛 → 玩家碰撞被頂射亂飛
		prop.apply_central_impulse(force)

func physics_update(delta: float) -> void:
	var controller: PlayerController = _player as PlayerController
	if not controller:
		return
	# 撞到人：立即結束衝刺，快速減速停下（不等滿 RECOVER）
	if _has_hit:
		var brake := controller.ACCELERATION * 2.0 * delta
		controller.velocity.x = move_toward(controller.velocity.x, 0.0, brake)
		controller.velocity.z = move_toward(controller.velocity.z, 0.0, brake)
		if Vector2(controller.velocity.x, controller.velocity.z).length() < 0.5:
			controller.state_machine.transition_to("Idle")
		return
	match _phase:
		Phase.PREPARE:
			# 立定停留：保持靜止，倒數結束後開始衝刺
			_phase_timer -= delta
			controller.velocity.x = 0.0
			controller.velocity.z = 0.0
			if _phase_timer <= 0.0:
				_phase = Phase.DIVE
				_phase_timer = DIVE_DURATION
				controller.velocity.x = _dive_direction.x * TuneConfig.dive_force
				controller.velocity.z = _dive_direction.z * TuneConfig.dive_force
		Phase.DIVE:
			# 衝刺階段：保持速度，結束後進僵直
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_phase = Phase.RECOVER
				_phase_timer = RECOVER_DURATION
		Phase.RECOVER:
			# 僵直期：衰减速度，不接受任何輸入
			_phase_timer -= delta
			controller.velocity.x = move_toward(controller.velocity.x, 0.0, controller.ACCELERATION * delta)
			controller.velocity.z = move_toward(controller.velocity.z, 0.0, controller.ACCELERATION * delta)
			if _phase_timer <= 0.0 and controller.is_on_floor():
				controller.state_machine.transition_to("Idle")
