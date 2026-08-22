## 职责：garment_body_scale 效果 —— 穿上时放大身躯 + 加宽，脱下还原

class_name GarmentBodyScaleEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	ctx.source_player.body_scale = float(params.get("scale", 1.5))
	ctx.source_player.body_width = float(params.get("width", 1.5))

func revert(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	ctx.source_player.body_scale = 1.0
	ctx.source_player.body_width = 1.0
