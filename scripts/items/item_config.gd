## 職責：道具配置表，從 items.json 讀取，提供 get_item(id) 查詢

class_name ItemConfig
extends ConfigTable

func _table_name() -> String:
	return "items"

func _defaults() -> Dictionary:
	return {"items": []}

## 按 id 返回道具定義，不存在回傳 null
func get_item(id: String) -> ItemDef:
	var records: Array = get_records("items")
	for r in records:
		if r is Dictionary and r.get("id", "") == id:
			return ItemDef.from_dict(r)
	return null

## 返回所有道具 id 列表
func all_ids() -> Array[String]:
	var result: Array[String] = []
	for r in get_records("items"):
		if r is Dictionary:
			result.append(str(r.get("id", "")))
	return result
