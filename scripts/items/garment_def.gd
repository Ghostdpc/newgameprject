## 职责：服装定义（只读值对象），由 GarmentConfig 构建

class_name GarmentDef
extends RefCounted

var id: String = ""
var display_name: String = ""
var icon: String = ""
var slot: String = ""
var model: String = ""
var texture: String = ""
var model_scale: float = 1.0
## 快门帧该件对 outfit 分的贡献上限（0~1）
var score_bonus: float = 0.0
var effects: Array[ItemEffect] = []

static func from_dict(d: Dictionary) -> GarmentDef:
	var def := GarmentDef.new()
	def.id           = str(d.get("id", ""))
	def.display_name = str(d.get("display_name", def.id))
	def.icon         = str(d.get("icon", ""))
	def.slot         = str(d.get("slot", "hat_slot"))
	def.model        = str(d.get("model", ""))
	def.texture      = str(d.get("texture", ""))
	def.model_scale  = float(d.get("model_scale", 1.0))
	def.score_bonus  = float(d.get("score_bonus", 0.0))

	var raw_effects: Array = d.get("effects", []) as Array
	for e in raw_effects:
		var kind := _parse_kind(str(e.get("kind", "")))
		var effect := ItemEffectRegistry.create(kind, e)
		if effect:
			def.effects.append(effect)
	return def

static func _parse_kind(s: String) -> ItemTypes.EffectKind:
	match s.to_lower():
		"player_speed":           return ItemTypes.EffectKind.PLAYER_SPEED
		"garment_head_scale":     return ItemTypes.EffectKind.GARMENT_HEAD_SCALE
		"garment_body_scale":     return ItemTypes.EffectKind.GARMENT_BODY_SCALE
		"garment_spring_wobble":  return ItemTypes.EffectKind.GARMENT_SPRING_WOBBLE
		"garment_emission_glow":  return ItemTypes.EffectKind.GARMENT_EMISSION_GLOW
		_:                        return ItemTypes.EffectKind.NONE
