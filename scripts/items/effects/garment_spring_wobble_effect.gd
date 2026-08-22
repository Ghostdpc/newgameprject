## 职责：garment_spring_wobble 效果 —— 穿上时切换 spring_rig 到 kowtow 预设，脱下还原 normal

class_name GarmentSpringWobbleEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	var rig: SpringBoneRig = ctx.source_player.spring_rig
	if rig == null:
		return
	var preset: String = str(params.get("preset", "kowtow"))
	rig.apply_preset(preset)
	rig.set_active(true)

func revert(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	var rig: SpringBoneRig = ctx.source_player.spring_rig
	if rig == null:
		return
	rig.apply_preset("normal")
	rig.set_active(true)
