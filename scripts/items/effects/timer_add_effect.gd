## 职责：timer_add 效果 —— 增减当前阶段剩余倒计时

class_name TimerAddEffect
extends ItemEffect

## apply：直接修改 GameManager.stage_time_remaining，支持 min_clamp 下限
func apply(ctx: ItemContext) -> void:
	var delta: float = float(params.get("delta", 0.0))
	var actual_delta := GameManager.add_time(delta)
	EventBus.time_effect_applied.emit(2 if actual_delta >= 0.0 else 3, actual_delta)

## timer_add 为瞬发效果，无需 revert
