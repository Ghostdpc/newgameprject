## 職責：飛撲狀態，向前衝擊，結束後短暫僵直不可操作

class_name DiveState
extends BaseState

const DIVE_FORCE: float = 9.0
const DIVE_DURATION: float = 0.4
const RECOVER_DURATION: float = 0.5
const HIT_FORCE: float = 8.0
const HIT_UPWARD: float = 4.0

var _timer: float = 0.0
var _recover_timer: float = 0.0
var _dive_direction: Vector3 = Vector3.ZERO
var _has_hit: bool = false

func enter() -> void:
	_timer = DIVE_DURATION
	_recover_timer = 0.0
	_has_hit = false
	var controller: PlayerController = _player as PlayerController
	if controller:
		var move_dir := controller.player_input.get_move_direction()
		if move_dir.length_squared() > 0.0:
			_dive_direction = Vector3(move_dir.x, 0.0, move_dir.y).normalized()
		else:
			_dive_direction = controller.global_basis.z
		controller.velocity.x = _dive_direction.x * TuneConfig.dive_force
		controller.velocity.z = _dive_direction.z * TuneConfig.dive_force

## 擊中目標：使目標進入飛行（Fly）→ 落地倒地（Down）
func hit_target(target: PlayerController) -> void:
	if _has_hit:
		return
	_has_hit = true
	target.state_machine.transition_to("Fly")
	var fly := target.state_machine.get_current_state() as FlyState
	fly.launch(_dive_direction * TuneConfig.hit_force + Vector3.UP * TuneConfig.hit_upward)
	EventBus.item_used.emit(-1, null)

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
	if _timer > 0.0:
		_timer -= delta
		return
	# 僵直期：衰减速度，不接受任何輸入
	_recover_timer += delta
	controller.velocity.x = move_toward(controller.velocity.x, 0.0, controller.ACCELERATION * delta)
	controller.velocity.z = move_toward(controller.velocity.z, 0.0, controller.ACCELERATION * delta)
	if _recover_timer >= RECOVER_DURATION and controller.is_on_floor():
		controller.state_machine.transition_to("Idle")
