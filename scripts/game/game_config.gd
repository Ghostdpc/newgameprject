## 職責：各遊戲階段時長配置，從 JSON 讀取，缺失時使用 _defaults() 默認值

class_name GameConfig
extends ConfigTable

func _table_name() -> String:
	return "game_flow"

func _defaults() -> Dictionary:
	return {
		"theme_announce_duration": 0.0,
		"grab_clothes_duration": 0.0,
		"battle_duration": 15.0,
		"scoring_duration": 0.0,
	}

var theme_announce_duration: float:
	get: return get_float("theme_announce_duration")

var grab_clothes_duration: float:
	get: return get_float("grab_clothes_duration")

var battle_duration: float:
	get: return get_float("battle_duration")

var scoring_duration: float:
	get: return get_float("scoring_duration")
