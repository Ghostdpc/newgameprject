## 職責：timer_add 效果 —— 增減當前階段剩餘倒計時

class_name TimerAddEffect
extends ItemEffect

## apply：直接修改 GameManager.stage_time_remaining
func apply(ctx: ItemContext) -> void:
	var delta: float = float(params.get("delta", 0.0))
	GameManager.stage_time_remaining = maxf(
		GameManager.stage_time_remaining + delta, 0.0
	)

## timer_add 為瞬發效果，無需 revert
