## 職責：香蕉皮滑倒效果 —— 踩中后立即倒地（ragdoll），沿行进方向持续滑行。
## 滑行规则：
##   - 撞到玩家 → 对方倒地（Fly），自己停止但仍倒地瘫（Stunned）
##   - 撞到场景物 → 不击飞物品，自己停止但仍倒地瘫
##   - 否则滑到终点后起身
## 由 BananaSlideEffect 经 player.start_banana_slide() 触发。

class_name BananaSlideState
extends BaseState

## 滑行水平速度（m/s）
const SLIDE_SPEED := 8.0
## 最大滑行距离（米）
const MAX_SLIDE_DIST := 12.0

var _slide_dir := Vector3.FORWARD
var _slid_dist := 0.0
var _last_pos := Vector3.ZERO
var _hit := false
var _halted := false

func enter() -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	_hit = false
	_halted = false
	_slid_dist = 0.0
	_last_pos = controller.global_position
	# 滑行方向：取水平速度方向，静止则用角色朝向
	var horizontal := Vector3(controller.velocity.x, 0.0, controller.velocity.z)
	if horizontal.length_squared() < 0.01:
		horizontal = -controller.global_basis.z
	_slide_dir = horizontal.normalized()
	# 倒地布娃娃
	controller.set_ragdoll(true)
	if controller.spring_rig:
		controller.spring_rig.set_active(false)
	# 起始骨速 = 倒地后向前滑
	controller.ragdoll_rig.drive_bones_horizontal(_slide_dir, SLIDE_SPEED)

func exit() -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	controller.set_ragdoll(false)
	if controller.spring_rig:
		controller.spring_rig.set_active(true)

func physics_update(delta: float) -> void:
	var controller := _player as PlayerController
	if not controller or controller.ragdoll_rig == null:
		return
	if _halted:
		return
	# 持续滑行（每帧重置骨速，克服地面摩擦维持速度），直到撞到障碍
	if not _hit:
		controller.ragdoll_rig.drive_bones_horizontal(_slide_dir, SLIDE_SPEED)
	# body 跟随 ragdoll hips 的水平位置（保持 mesh/body 对齐），但 y 由 body 自身地面碰撞控制，
	# 避免 hips 骨高度抖动把 body 带离地面（穿模/掉坑）
	var hips := controller.ragdoll_rig.get_hips_position()
	if hips != Vector3.ZERO:
		controller.global_position = Vector3(hips.x, controller.global_position.y, hips.z)
	controller.move_and_slide()
	# 滑行距离累计
	var now := controller.global_position
	_slid_dist += now.distance_to(_last_pos)
	_last_pos = now
	# 撞人/撞物检测（用 body 的滑行碰撞）
	if not _hit:
		for i in controller.get_slide_collision_count():
			var col := controller.get_slide_collision(i)
			var collider := col.get_collider()
			if collider is PlayerController and collider != controller:
				_hit_player(collider as PlayerController)
				return
			elif collider is PhysicalProp:
				_halt("撞到物品")
				return
			elif collider is StaticBody3D:
				# 撞到静态障碍（墙/家具）：法线近水平才算墙面/侧面，地面(近竖直)忽略
				var normal := col.get_normal()
				if absf(normal.y) < 0.6:
					_halt("撞到静态障碍")
					return
	# 没撞到，滑满距离后起身
	if _slid_dist >= MAX_SLIDE_DIST:
		_stand_up()
		return

## 撞到玩家：对方直接倒地（Stunned 瘫软，不击飞），自己停止但仍倒地瘫
func _hit_player(target: PlayerController) -> void:
	if _hit or _halted:
		return
	_hit = true
	# 击倒而非击飞：直接进 Stunned，对方原地瘫软倒地
	if target.state_machine:
		target.state_machine.transition_to("Stunned")
	_halt("撞到玩家")

## 停下但保持倒地瘫（进入 Stunned，由 Stunned 计时后自动站起）
func _halt(reason: String) -> void:
	if _halted:
		return
	_halted = true
	var controller := _player as PlayerController
	if not controller:
		return
	if controller.ragdoll_rig:
		controller.ragdoll_rig.drive_bones_horizontal(_slide_dir, 0.0)
	# 转移到 Stunned：继续保持 ragdoll 瘫软，计时结束站起
	controller.state_machine.transition_to("Stunned")

## 滑到终点：停止骨速后直接起身（不瘫）
func _stand_up() -> void:
	if _halted:
		return
	_halted = true
	var controller := _player as PlayerController
	if not controller:
		return
	# 起身由 exit() 关闭 ragdoll + ragdoll_rig 站起插值处理
	controller.state_machine.transition_to("Idle")
