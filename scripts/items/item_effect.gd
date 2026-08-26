## 职责：道具效果基类，子类覆写 apply / revert 实现具体行为

class_name ItemEffect
extends RefCounted

var kind: ItemTypes.EffectKind = ItemTypes.EffectKind.NONE
var target: ItemTypes.Target = ItemTypes.Target.WORLD
var duration: float = 0.0
var params: Dictionary = {}

## 效果生效，由 ItemSystem 调用
func apply(ctx: ItemContext) -> void:
	pass

## 效果回退（有时长时由 ItemSystem 计时后调用）
func revert(ctx: ItemContext) -> void:
	pass

## 从数据字典填充基本字段（load 时由 ItemDef 建构）
func from_data(data: Dictionary) -> void:
	duration = float(data.get("duration", 0.0))
	params   = data.get("params", {}) as Dictionary
