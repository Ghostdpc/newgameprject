## 職責：player_ragdoll 效果 —— 觸發目標玩家進入布娃娃狀態

class_name PlayerRagdollEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	# duration > 0 時由 ItemSystem 計時後調用 revert；
	# 這裡僅激活布娃娃，動畫控制權交給 RagdollRig
	ctx.source_player.set_ragdoll(true)
	if duration > 0.0:
		# 讓玩家狀態機進入 Stunned（保證站起後恢復控制）
		ctx.source_player.state_machine.transition_to("Stunned")

func revert(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	ctx.source_player.set_ragdoll(false)
