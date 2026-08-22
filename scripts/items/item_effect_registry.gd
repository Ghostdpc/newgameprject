## 職責：道具效果類型注冊表，EffectKind → ItemEffect 子類腳本

class_name ItemEffectRegistry

static var _map: Dictionary = {}

## 注冊效果類型（啟動時由 ItemSystem 完成）
static func register(kind: ItemTypes.EffectKind, script: Script) -> void:
	_map[kind] = script

## 按 kind 實例化效果對象，返回 null 表示未注冊
static func create(kind: ItemTypes.EffectKind, data: Dictionary) -> ItemEffect:
	if not _map.has(kind):
		push_warning("ItemEffectRegistry: unregistered kind %d" % kind)
		return null
	var effect: ItemEffect = _map[kind].new() as ItemEffect
	effect.kind   = kind
	effect.target = _parse_target(data.get("target", "world"))
	effect.from_data(data)
	return effect

static func _parse_target(s: Variant) -> ItemTypes.Target:
	match str(s).to_lower():
		"self":   return ItemTypes.Target.SELF
		"others": return ItemTypes.Target.OTHERS
		"all":    return ItemTypes.Target.ALL
		_:        return ItemTypes.Target.WORLD
