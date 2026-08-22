## 職責：運行時道具使用上下文，傳入 apply / revert

class_name ItemContext
extends RefCounted

## 使用道具的玩家（trigger = ON_PICKUP/ON_USE）
var source_player: PlayerController

## 道具 id（方便 Handler 取定義）
var item_id: String = ""

## 額外信息（ON_HIT 時傳入命中對象等）
var extra: Dictionary = {}
