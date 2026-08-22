## 職責：player_gray 效果 —— 灰頭土臉，在目標玩家身上疊臟污貼花，隨時間褪去
## params.duration（可選，默認 6.0）：貼花持續秒數

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
