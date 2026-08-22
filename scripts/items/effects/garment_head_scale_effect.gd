## 职责：garment_head_scale 效果 —— 穿上时放大头部，脱下还原

class_name GarmentHeadScaleEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	var scale: float = float(params.get("scale", 1.8))
	ctx.source_player.head_scale = scale

func revert(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	ctx.source_player.head_scale = 1.0
