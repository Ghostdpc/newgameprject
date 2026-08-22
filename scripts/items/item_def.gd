## 職責：道具定義（只讀值對象），由 ItemConfig 構建

class_name ItemDef
extends RefCounted

var id: String = ""
var display_name: String = ""
var icon: String = ""
var trigger: ItemTypes.Trigger = ItemTypes.Trigger.ON_USE
var effects: Array[ItemEffect] = []

## 從 JSON 記錄構建，effect 字段由 ItemEffectRegistry 實例化
static func from_dict(d: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id           = str(d.get("id", ""))
	def.display_name = str(d.get("display_name", def.id))
	def.icon         = str(d.get("icon", ""))
	def.trigger      = _parse_trigger(str(d.get("trigger", "on_use")))

	var raw_effects: Array = d.get("effects", []) as Array
	for e in raw_effects:
		var kind := _parse_kind(str(e.get("kind", "")))
		var effect := ItemEffectRegistry.create(kind, e)
		if effect:
			def.effects.append(effect)
	return def

static func _parse_trigger(s: String) -> ItemTypes.Trigger:
	match s.to_lower():
		"on_pickup": return ItemTypes.Trigger.ON_PICKUP
		"on_hit":    return ItemTypes.Trigger.ON_HIT
		"on_step":   return ItemTypes.Trigger.ON_STEP
		_:           return ItemTypes.Trigger.ON_USE

static func _parse_kind(s: String) -> ItemTypes.EffectKind:
	match s.to_lower():
		"timer_add":      return ItemTypes.EffectKind.TIMER_ADD
		"timer_scale":    return ItemTypes.EffectKind.TIMER_SCALE
		"camera_push":    return ItemTypes.EffectKind.CAMERA_PUSH
		"camera_offset":  return ItemTypes.EffectKind.CAMERA_OFFSET
		"player_stun":    return ItemTypes.EffectKind.PLAYER_STUN
		"player_ragdoll": return ItemTypes.EffectKind.PLAYER_RAGDOLL
		"player_speed":   return ItemTypes.EffectKind.PLAYER_SPEED
		"spawn_trap":     return ItemTypes.EffectKind.SPAWN_TRAP
		_:                return ItemTypes.EffectKind.NONE
