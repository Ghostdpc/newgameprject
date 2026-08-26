## 职责：单张配置表的统一访问基类，子类只声明表名与默认值，不手写映射

class_name ConfigTable
extends RefCounted

var _data: Dictionary = {}

## 子类覆写此方法，回传对应的配置文件名（不含 .json）
func _table_name() -> String:
	return ""

## 子类覆写此方法，回传各字段的默认值字典
func _defaults() -> Dictionary:
	return {}

## 键是否存在于已加载的配置中
func has(key: String) -> bool:
	return _data.has(key)

## 加载配置，从 ConfigLoader 读取并缓存到 _data
func load() -> void:
	_data = ConfigLoader.load_config(_table_name())

## 类型化取值，优先用 _data，缺失时回退 _defaults()，都无则用零值
func get_float(key: String) -> float:
	if _data.has(key):
		return float(_data[key])
	var d := _defaults()
	if d.has(key):
		return float(d[key])
	return 0.0

func get_int(key: String) -> int:
	if _data.has(key):
		return int(_data[key])
	var d := _defaults()
	if d.has(key):
		return int(d[key])
	return 0

func get_string(key: String) -> String:
	if _data.has(key):
		return String(_data[key])
	var d := _defaults()
	if d.has(key):
		return String(d[key])
	return ""

func get_bool(key: String) -> bool:
	if _data.has(key):
		return bool(_data[key])
	var d := _defaults()
	if d.has(key):
		return bool(d[key])
	return false

func get_array(key: String) -> Array:
	if _data.has(key):
		return _data[key] as Array
	var d := _defaults()
	if d.has(key):
		return d[key] as Array
	return []

func get_dict(key: String) -> Dictionary:
	if _data.has(key):
		return _data[key] as Dictionary
	var d := _defaults()
	if d.has(key):
		return d[key] as Dictionary
	return {}

## 取得 key 下的记录列表（集合表用）
func get_records(key: String) -> Array:
	return get_array(key)

## 按 id 字段在记录列表中查找（每个记录须含 id 键）
func get_record_by_id(key: String, id: String) -> Dictionary:
	for r in get_records(key):
		if r is Dictionary and r.get("id", "") == id:
			return r
	return {}
