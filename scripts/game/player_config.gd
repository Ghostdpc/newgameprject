## 职责：玩家配色配置（P1-P4），从 JSON 读取，策划可直接修改
## 颜色用 #RRGGBB 十六进制，与交互文档三重辨识一致：P1蓝 / P2橙 / P3绿 / P4紫

class_name PlayerConfig
extends ConfigTable

static var _instance: PlayerConfig = null

func _table_name() -> String:
	return "player_colors"

func _defaults() -> Dictionary:
	return {
		"player_colors": ["#3B7AE6", "#E68C1F", "#40D159", "#9959F2"],
	}

## 全局唯一入口：返回 P1-P4 的颜色数组（懒加载 + 缓存）
static func get_player_colors() -> Array[Color]:
	if _instance == null:
		_instance = PlayerConfig.new()
		_instance.load()
	return _instance._parse_colors()

static func get_color(player_index: int) -> Color:
	var colors := get_player_colors()
	if colors.is_empty():
		return Color.WHITE
	return colors[player_index % colors.size()]

func _parse_colors() -> Array[Color]:
	var result: Array[Color] = []
	for v in get_array("player_colors"):
		if v is String:
			result.append(_parse_hex_color(String(v)))
		elif v is Dictionary:
			result.append(Color(
				float(v.get("r", 0.0)),
				float(v.get("g", 0.0)),
				float(v.get("b", 0.0)),
			))
	return result

## 解析 #RRGGBB / #RRGGBBAA 十六进制颜色
static func _parse_hex_color(s: String) -> Color:
	var hex := s.strip_edges()
	if hex.begins_with("#"):
		hex = hex.substr(1)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var a := 1.0
	if hex.length() >= 6:
		r = hex.substr(0, 2).hex_to_int() / 255.0
		g = hex.substr(2, 2).hex_to_int() / 255.0
		b = hex.substr(4, 2).hex_to_int() / 255.0
	if hex.length() >= 8:
		a = hex.substr(6, 2).hex_to_int() / 255.0
	return Color(r, g, b, a)
