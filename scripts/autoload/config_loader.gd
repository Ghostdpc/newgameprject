## 职责：JSON 配置文件加载器，统一入口 + 快取

extends Node

const CONFIG_ROOT: String = "res://data/configs/"
const RESERVED_KEYS: Array[String] = ["_comment"]

var _cache: Dictionary = {}

## 读取配置，返回 Dictionary。文件不存在或解析失败回传 {}
func load_config(config_name: String) -> Dictionary:
	if _cache.has(config_name):
		return _cache[config_name]

	var path := CONFIG_ROOT + config_name + ".json"
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ConfigLoader: cannot open: %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_error("ConfigLoader: invalid JSON: %s" % path)
		return {}

	var cfg: Dictionary = parsed
	for k in RESERVED_KEYS:
		cfg.erase(k)

	_cache[config_name] = cfg
	return cfg

## 清快取重读（开发热重载用）
func reload(config_name: String) -> Dictionary:
	_cache.erase(config_name)
	return load_config(config_name)

## 便捷查询，缺失时回传 default_value
func get_value(config_name: String, key: String, default_value: Variant = null) -> Variant:
	var cfg := load_config(config_name)
	return cfg.get(key, default_value)

## 检查某配置文件是否存在（未加载时只做文件存在判断，不解析）
func has_config(config_name: String) -> bool:
	if _cache.has(config_name):
		return true
	var path := CONFIG_ROOT + config_name + ".json"
	return FileAccess.file_exists(path)
