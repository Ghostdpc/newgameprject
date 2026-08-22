## 職責：timer_add 效果 —— 增減當前階段剩餘倒計時

class_name TimerAddEffect
extends ItemEffect

## apply：直接修改 GameManager.stage_time_remaining，支持 min_clamp 下限
func apply(ctx: ItemContext) -> void:
	var delta: float = float(params.get("delta", 0.0))
	var min_clamp: float = float(params.get("min_clamp", 0.0))
	GameManager.stage_time_remaining = maxf(
		GameManager.stage_time_remaining + delta, min_clamp
	)

## timer_add 為瞬發效果，無需 revert
