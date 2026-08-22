## 職責：單張配置表的統一訪問基類，子類只聲明表名與默認值，不手寫映射

class_name ConfigTable
extends RefCounted

var _data: Dictionary = {}

## 子類覆寫此方法，回傳對應的配置文件名（不含 .json）
func _table_name() -> String:
	return ""

## 子類覆寫此方法，回傳各字段的默認值字典
func _defaults() -> Dictionary:
	return {}

## 鍵是否存在於已加載的配置中
func has(key: String) -> bool:
	return _data.has(key)

## 加載配置，從 ConfigLoader 讀取並緩存到 _data
func load() -> void:
	_data = ConfigLoader.load_config(_table_name())

## 類型化取值，優先用 _data，缺失時回退 _defaults()，都無則用零值
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

## 取得 key 下的記錄列表（集合表用）
func get_records(key: String) -> Array:
	return get_array(key)

## 按 id 字段在記錄列表中查找（每個記錄須含 id 鍵）
func get_record_by_id(key: String, id: String) -> Dictionary:
	for r in get_records(key):
		if r is Dictionary and r.get("id", "") == id:
			return r
	return {}
