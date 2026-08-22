## 職責：道具效果基類，子類覆寫 apply / revert 實現具體行為

class_name ItemEffect
extends RefCounted

var kind: ItemTypes.EffectKind = ItemTypes.EffectKind.NONE
var target: ItemTypes.Target = ItemTypes.Target.WORLD
var duration: float = 0.0
var params: Dictionary = {}

## 效果生效，由 ItemSystem 調用
func apply(ctx: ItemContext) -> void:
	pass

## 效果回退（有時長時由 ItemSystem 計時後調用）
func revert(ctx: ItemContext) -> void:
	pass

## 從數據字典填充基本字段（load 時由 ItemDef 建構）
func from_data(data: Dictionary) -> void:
	duration = float(data.get("duration", 0.0))
	params   = data.get("params", {}) as Dictionary
