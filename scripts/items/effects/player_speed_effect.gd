## 职责：player_speed 效果 —— 移速乘数 buff，持续 effect.duration 秒后还原

class_name PlayerSpeedEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	SoundMgr.play("boost")
	if ctx.source_player == null:
		return
	var multiplier: float = float(params.get("multiplier", 1.0))
	ctx.source_player.speed_multiplier = multiplier

func revert(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	ctx.source_player.speed_multiplier = 1.0
