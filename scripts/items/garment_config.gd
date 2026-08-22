## 职责：服装配置表，从 garments.json 读取，提供 get_garment(id) 查询

class_name GarmentConfig
extends ConfigTable

func _table_name() -> String:
	return "garments"

func _defaults() -> Dictionary:
	return { "garments": [] }

## 按 id 返回服装定义，不存在返回 null
func get_garment(id: String) -> GarmentDef:
	for r in get_records("garments"):
		if r is Dictionary and r.get("id", "") == id:
			return GarmentDef.from_dict(r)
	return null

## 返回所有服装 id 列表
func all_ids() -> Array[String]:
	var result: Array[String] = []
	for r in get_records("garments"):
		if r is Dictionary:
			result.append(str(r.get("id", "")))
	return result

## 返回所有服装定义
func all_garments() -> Array[GarmentDef]:
	var result: Array[GarmentDef] = []
	for r in get_records("garments"):
		if r is Dictionary:
			result.append(GarmentDef.from_dict(r))
	return result
