## 職責：炸彈道具測試 Demo
## P1（藍）朝前投擲炸彈 → 抛物線飛行 → 引信引爆 → 範圍內玩家灰頭土臉 + 積分懲罰。
## P2（橙）站在落點附近驗證被炸效果。
## P1: WASD 移動轉向瞄準；F 投炸彈  |  R 重置 P1  |  C 清除臟污並歸零懲罰
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
				_hint("清除臟污 + 歸零懲罰")

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
