## 職責：放置物定義（只讀值對象），由 ItemConfig 構建

class_name TrapDef
extends RefCounted

var id: String = ""
var display_name: String = ""
var lifetime: float = 0.0
var trigger: ItemTypes.Trigger = ItemTypes.Trigger.ON_STEP
var effects: Array[ItemEffect] = []

static func from_dict(d: Dictionary) -> TrapDef:
	var def := TrapDef.new()
	def.id           = str(d.get("id", ""))
	def.display_name = str(d.get("display_name", def.id))
	def.lifetime     = float(d.get("lifetime", 0.0))
	def.trigger      = ItemTypes.Trigger.ON_STEP

	var raw_effects: Array = d.get("effects", []) as Array
	for e in raw_effects:
		var kind_str: String = str(e.get("kind", ""))
		var kind := _parse_kind(kind_str)
		var effect := ItemEffectRegistry.create(kind, e)
		if effect:
			def.effects.append(effect)
	return def

static func _parse_kind(s: String) -> ItemTypes.EffectKind:
	match s.to_lower():
		"player_ragdoll": return ItemTypes.EffectKind.PLAYER_RAGDOLL
		"player_stun":    return ItemTypes.EffectKind.PLAYER_STUN
		"player_speed":   return ItemTypes.EffectKind.PLAYER_SPEED
		"timer_add":      return ItemTypes.EffectKind.TIMER_ADD
		"banana_slide":   return ItemTypes.EffectKind.BANANA_SLIDE
		_:                return ItemTypes.EffectKind.NONE
