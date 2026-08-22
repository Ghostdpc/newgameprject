## 職責：timer_scale 效果 —— 將倒計時速率乘以 scale，持續 seconds 秒後還原

class_name TimerScaleEffect
extends ItemEffect

## 覆寫 from_data：用 params.seconds 作為持續時長
func from_data(data: Dictionary) -> void:
	super.from_data(data)
	var p: Dictionary = data.get("params", {}) as Dictionary
	var seconds: float = float(p.get("seconds", 0.0))
	if seconds > 0.0:
		duration = seconds

func apply(ctx: ItemContext) -> void:
	var scale: float = float(params.get("scale", 1.0))
	GameManager.time_scale = scale

func revert(ctx: ItemContext) -> void:
	GameManager.time_scale = 1.0
