## 职责：banana_slide 效果 —— 踩到香蕉皮时进入倒地滑行（玩家侧 BananaSlideState 处理）
## 倒地后沿行进方向滑行，沿途撞到玩家则将其击飞并停下（类似飞扑），否则滑到终点起身。

class_name BananaSlideEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	var player := ctx.source_player as PlayerController
	player.start_banana_slide()

func revert(_ctx: ItemContext) -> void:
	pass
