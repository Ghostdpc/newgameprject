## 职责：运行时道具使用上下文，传入 apply / revert

class_name ItemContext
extends RefCounted

## 使用道具的玩家（trigger = ON_PICKUP/ON_USE）
var source_player: PlayerController

## 道具 id（方便 Handler 取定义）
var item_id: String = ""

## 额外信息（ON_HIT 时传入命中对象等）
var extra: Dictionary = {}
