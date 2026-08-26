## 职责：香蕉皮滑倒测试 Demo
## P1（蓝）踩到地上的香蕉皮 → 倒地滑行；P2（橙）站在滑行路径上验证撞人倒地。
## P1: WASD + 空格跳 + F扑   P2: 方向键 + 1跳 + 2扑
## 遇障碍：撞到下个角色（HIT_RADIUS 内）则将其击飞，自己停止瘫软；滑满距离起身。
class_name BananaDemoController
extends Node3D

@onready var player: PlayerController = $Player
@onready var player2: PlayerController = $Player2

func _ready() -> void:
	# 在 P1 前方摆放一个香蕉皮陷阱，玩家踩上即触发滑倒
	call_deferred("_place_trap")

func _place_trap() -> void:
	if ItemSystem == null:
		push_warning("item_system autoload 未就绪，无法放置香蕉皮")
		return
	var trap_def: TrapDef = ItemSystem._item_config.get_trap("banana_peel")
	if trap_def == null:
		push_warning("找不到 banana_peel trap")
		return
	var inst := TrapInstance.new()
	inst.setup(trap_def, player)
	add_child(inst)
	# 放在 P1 与 P2 连线中点，P1 前进会踩到
	inst.global_position = Vector3(0.0, 0.3, 0.5)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				player.global_position = Vector3(-3, 1, 5)
				player.velocity = Vector3.ZERO
				_hint("重置 P1 位置")
			KEY_T:
				_place_trap()
				_hint("重新放置香蕉皮")

func _process(_delta: float) -> void:
	# 常驻诊断：显示 P1 按键方向 与 当前位置（真机排查 WASD 无效用）
	var l := get_node_or_null("UILayer/Feedback") as Label
	if l and player and player.player_input:
		var d := player.player_input.get_move_direction()
		l.text = "dir=%s pos=(%.1f,%.1f,%.1f) state=%s speed=%.1f" % [
			d, player.global_position.x, player.global_position.y, player.global_position.z,
			player.state_machine.current_state_name if player.state_machine else "None",
			player.speed_multiplier * TuneConfig.move_speed
		]

func _hint(text: String) -> void:
	var l := get_node_or_null("UILayer/Feedback") as Label
	if l:
		l.text = text
