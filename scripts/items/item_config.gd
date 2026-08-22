## 職責：道具配置表，從 items.json 讀取，提供 get_item(id) 查詢

class_name ItemConfig
extends ConfigTable

func _table_name() -> String:
	return "items"

func _defaults() -> Dictionary:
	return {
		"spawn_config": {"max_active": 5, "respawn_interval": 8.0},
		"items": [],
		"traps": [],
	}

## 按 id 返回道具定義，不存在回傳 null
func get_item(id: String) -> ItemDef:
	var records: Array = get_records("items")
	for r in records:
		if r is Dictionary and r.get("id", "") == id:
			return ItemDef.from_dict(r)
	return null

## 按 id 返回道具图标 key（用于 UI 显示，空字符串 = 无图标）
func get_item_icon(id: String) -> String:
	for r in get_records("items"):
		if r is Dictionary and r.get("id", "") == id:
			return str(r.get("icon", ""))
	return ""

## 返回所有道具 id 列表
func all_ids() -> Array[String]:
	var result: Array[String] = []
	for r in get_records("items"):
		if r is Dictionary:
			result.append(str(r.get("id", "")))
	return result

## 返回 spawn_config 字典
func get_spawn_config() -> Dictionary:
	return get_dict("spawn_config")

## 返回所有放置物定義
func all_trap_defs() -> Array[TrapDef]:
	var result: Array[TrapDef] = []
	for r in get_records("traps"):
		if r is Dictionary:
			result.append(TrapDef.from_dict(r))
	return result

## 按 id 返回放置物定義，不存在回傳 null
func get_trap(id: String) -> TrapDef:
	for r in get_records("traps"):
		if r is Dictionary and r.get("id", "") == id:
			return TrapDef.from_dict(r)
	return null
