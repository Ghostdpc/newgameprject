## 职责：player_ragdoll 效果 —— 触发目标玩家进入布娃娃状态

class_name PlayerRagdollEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	# duration > 0 时由 ItemSystem 计时后调用 revert；
	# 这里仅激活布娃娃，动画控制权交给 RagdollRig
	ctx.source_player.set_ragdoll(true)
	if duration > 0.0:
		# 让玩家状态机进入 Stunned（保证站起后恢复控制）
		ctx.source_player.state_machine.transition_to("Stunned")

func revert(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	ctx.source_player.set_ragdoll(false)
