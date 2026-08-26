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
## 挂点偏移（米，相对骨槽局部）：服装专属的位置微调，覆盖 OutfitManager 槽位预设偏移
var mount_offset: Vector3 = Vector3.ZERO
## 占位 tint 色（模型为纯白 unshaded 时套用，便于查看；空 = 不套）
var tint: Color = Color(1, 1, 1, 1)
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
	if d.has("mount_offset"):
		var mo: Array = d.get("mount_offset", [])
		if mo.size() >= 3:
			def.mount_offset = Vector3(float(mo[0]), float(mo[1]), float(mo[2]))
	if d.has("tint"):
		def.tint = _try_color(d.get("tint"), Color.WHITE)

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

## 解析 tint 色：接受 "#rrggbb"、"Color(1,0.8,0)" 或名字
static func _try_color(v: Variant, fallback: Color) -> Color:
	var s := str(v)
	if s.begins_with("#"):
		return Color.html(s)
	if s.begins_with("Color(") or s.begins_with("("):
		var inner := s.replace("Color(", "").replace("(", "").replace(")", "")
		var parts := inner.split(",")
		if parts.size() >= 3:
			return Color(float(parts[0].strip_edges()), float(parts[1].strip_edges()), float(parts[2].strip_edges()))
	match s.to_lower():
		"gold": return Color(1.0, 0.84, 0.0)
		"red": return Color(1, 0, 0)
		"blue": return Color(0, 0.4, 1)
		"green": return Color(0, 1, 0)
		"white": return Color(1, 1, 1)
		"black": return Color(0, 0, 0)
	return fallback
