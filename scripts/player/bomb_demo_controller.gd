## 职责：炸弹道具测试 Demo
## P1（蓝）朝前投掷炸弹 → 抛物线飞行 → 引信引爆 → 范围内玩家灰头土脸 + 积分惩罚。
## P2（橙）站在落点附近验证被炸效果。
## P1: WASD 移动转向瞄准；F 投炸弹  |  R 重置 P1  |  C 清除脏污并归零惩罚
class_name BombDemoController
extends Node3D

@onready var player: PlayerController = $Player
@onready var player2: PlayerController = $Player2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_throw_bomb()
			KEY_R:
				player.global_position = Vector3(-4, 1, 0)
				player.velocity = Vector3.ZERO
				_hint("重置 P1 位置")
			KEY_C:
				player.score_penalty = 0
				player2.score_penalty = 0
				if player.character_effects:
					player.character_effects.clear_all()
				if player2.character_effects:
					player2.character_effects.clear_all()
				_hint("清除脏污 + 归零惩罚")

func _throw_bomb() -> void:
	if ItemSystem == null:
		push_warning("item_system autoload 未就绪，无法投炸弹")
		return
	ItemSystem.use_item(player, "bomb")
	_hint("P1 投出炸弹！")

func _process(_delta: float) -> void:
	var l := get_node_or_null("UILayer/Feedback") as Label
	if l:
		l.text = "P1 penalty=%d  |  P2 penalty=%d" % [
			player.score_penalty if player else 0,
			player2.score_penalty if player2 else 0,
		]

func _hint(text: String) -> void:
	var l := get_node_or_null("UILayer/Feedback") as Label
	if l:
		l.text = text
