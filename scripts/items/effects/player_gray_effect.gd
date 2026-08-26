## 职责：player_gray 效果 —— 灰头土脸，在目标玩家身上叠脏污贴花，随时间褪去
## params.duration（可选，默认 6.0）：贴花持续秒数

class_name PlayerGrayEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	var player: PlayerController = ctx.source_player
	if player == null:
		return
	if player.character_effects == null:
		return
	var secs: float = float(params.get("duration", duration if duration > 0.0 else 6.0))
	player.character_effects.apply_dirt_decal(secs)
