## 職責：道具定義（只讀值對象），由 ItemConfig 構建

class_name ItemDef
extends RefCounted

enum VfxMode {
	WORLD,          # 在世界坐標播放（使用者當前位置）
	ATTACH_PLAYER,  # 作為使用者子節點跟隨移動
	ATTACH_CAMERA,  # 掛載到相機前方（類全屏效果）
}

var id: String = ""
var display_name: String = ""
var icon: String = ""
## 3D 模型資源路徑（res://，空 = 無模型用占位方塊）
var model: String = ""
## 貼圖資源路徑（res://，空 = 用模型自帶材質）
var texture: String = ""
## 模型統一縮放（貼合道具箱體積）
var model_scale: float = 1.0
## 使用/觸發道具時播放的特效場景路徑（res://，空 = 不播放）
var use_vfx: String = ""
## 特效播放位置模式
var use_vfx_mode: VfxMode = VfxMode.WORLD
var trigger: ItemTypes.Trigger = ItemTypes.Trigger.ON_USE
var effects: Array[ItemEffect] = []

## 從 JSON 記錄構建，effect 字段由 ItemEffectRegistry 實例化
static func from_dict(d: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id           = str(d.get("id", ""))
	def.display_name = str(d.get("display_name", def.id))
	def.icon         = str(d.get("icon", ""))
	def.model        = str(d.get("model", ""))
	def.texture      = str(d.get("texture", ""))
	def.model_scale  = float(d.get("model_scale", 1.0))
	def.use_vfx      = str(d.get("use_vfx", ""))
	def.use_vfx_mode = _parse_vfx_mode(str(d.get("use_vfx_mode", "world")))
	def.trigger      = _parse_trigger(str(d.get("trigger", "on_use")))

	var raw_effects: Array = d.get("effects", []) as Array
	for e in raw_effects:
		var kind := _parse_kind(str(e.get("kind", "")))
		var effect := ItemEffectRegistry.create(kind, e)
		if effect:
			def.effects.append(effect)
	return def

static func _parse_vfx_mode(s: String) -> VfxMode:
	match s.to_lower():
		"attach_player": return VfxMode.ATTACH_PLAYER
		"attach_camera": return VfxMode.ATTACH_CAMERA
		_:               return VfxMode.WORLD

static func _parse_trigger(s: String) -> ItemTypes.Trigger:
	match s.to_lower():
		"on_pickup": return ItemTypes.Trigger.ON_PICKUP
		"on_hit":    return ItemTypes.Trigger.ON_HIT
		"on_step":   return ItemTypes.Trigger.ON_STEP
		_:           return ItemTypes.Trigger.ON_USE

static func _parse_kind(s: String) -> ItemTypes.EffectKind:
	match s.to_lower():
		"timer_add":               return ItemTypes.EffectKind.TIMER_ADD
		"timer_scale":             return ItemTypes.EffectKind.TIMER_SCALE
		"camera_push":             return ItemTypes.EffectKind.CAMERA_PUSH
		"camera_offset":           return ItemTypes.EffectKind.CAMERA_OFFSET
		"player_stun":             return ItemTypes.EffectKind.PLAYER_STUN
		"player_ragdoll":          return ItemTypes.EffectKind.PLAYER_RAGDOLL
		"player_speed":            return ItemTypes.EffectKind.PLAYER_SPEED
		"spawn_trap":              return ItemTypes.EffectKind.SPAWN_TRAP
		"throw_bomb":              return ItemTypes.EffectKind.THROW_BOMB
		"player_gray":             return ItemTypes.EffectKind.PLAYER_GRAY
		"garment_head_scale":      return ItemTypes.EffectKind.GARMENT_HEAD_SCALE
		"garment_body_scale":      return ItemTypes.EffectKind.GARMENT_BODY_SCALE
		"garment_spring_wobble":   return ItemTypes.EffectKind.GARMENT_SPRING_WOBBLE
		"garment_emission_glow":   return ItemTypes.EffectKind.GARMENT_EMISSION_GLOW
		_:                         return ItemTypes.EffectKind.NONE
