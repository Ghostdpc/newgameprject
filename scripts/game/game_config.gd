## 職責：各遊戲階段時長配置，從 JSON 讀取，缺失時使用代碼默認值

class_name GameConfig
extends RefCounted

const CONFIG_NAME: String = "game_flow"

var theme_announce_duration: float = 0.0
var grab_clothes_duration: float   = 0.0
var battle_duration: float         = 15.0
var scoring_duration: float        = 0.0

## 從 JSON 加載配置，缺失的鍵保留默認值
func load_from_json() -> void:
	var cfg: Dictionary = ConfigLoader.load_config(CONFIG_NAME)
	if cfg.is_empty():
		return
	theme_announce_duration = float(cfg.get("theme_announce_duration", theme_announce_duration))
	grab_clothes_duration   = float(cfg.get("grab_clothes_duration",   grab_clothes_duration))
	battle_duration         = float(cfg.get("battle_duration",         battle_duration))
	scoring_duration        = float(cfg.get("scoring_duration",        scoring_duration))
