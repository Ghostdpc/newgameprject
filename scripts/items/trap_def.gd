## 职责：放置物定义（只读值对象），由 ItemConfig 构建

class_name TrapDef
extends RefCounted

var id: String = ""
var display_name: String = ""
## 3D 模型资源路径（res://，空 = 无模型用占位方块）
var model: String = ""
## 贴图资源路径（res://，空 = 用模型自带材质）
var texture: String = ""
## 模型统一缩放
var model_scale: float = 1.0
var lifetime: float = 0.0
var trigger: ItemTypes.Trigger = ItemTypes.Trigger.ON_STEP
## 放置物被触发时播放的特效场景路径（res://，空 = 不播放）
var use_vfx: String = ""
## 特效播放位置模式（放置物固定为 world，在触发点播放）
var use_vfx_mode: ItemDef.VfxMode = ItemDef.VfxMode.WORLD
var effects: Array[ItemEffect] = []

static func from_dict(d: Dictionary) -> TrapDef:
	var def := TrapDef.new()
	def.id           = str(d.get("id", ""))
	def.display_name = str(d.get("display_name", def.id))
	def.model        = str(d.get("model", ""))
	def.texture      = str(d.get("texture", ""))
	def.model_scale  = float(d.get("model_scale", 1.0))
	def.lifetime     = float(d.get("lifetime", 0.0))
	def.use_vfx      = str(d.get("use_vfx", ""))
	def.use_vfx_mode = ItemDef._parse_vfx_mode(str(d.get("use_vfx_mode", "world")))
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
