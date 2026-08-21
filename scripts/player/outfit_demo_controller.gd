## 職責：換裝 + 角色效果 Demo
## 1 戴帽 / 2 卸帽 / 3 全身繪畫(紅) / 4 全身灰化 / 5 頭部灰化 / 6 右臂灰化 / 7 身體著色 / 0 清除全部

class_name OutfitDemoController
extends Node3D

const HAT_SCENE := preload("res://scenes/tech_demos/outfit_items/hat.tscn")

@onready var _outfit: OutfitManager = $RigModel/OutfitManager
@onready var _effects: CharacterEffects = $RigModel/CharacterEffects
@onready var _hint: Label = $UILayer/Feedback

func _ready() -> void:
	_outfit.player_color = Color(0.2, 0.6, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_outfit.equip("hat_slot", HAT_SCENE)
				_update_hint("戴帽")
			KEY_2:
				_outfit.unequip("hat_slot")
				_update_hint("卸帽")
			KEY_3:
				_effects.paint(Color(1.0, 0.2, 0.2))
				_update_hint("全身繪畫！")
			KEY_4:
				_effects.apply_gray()
				_update_hint("全身灰化！")
			KEY_5:
				_effects.apply_gray(3.0, ["head"])
				_update_hint("頭部灰化！")
			KEY_6:
				_effects.apply_gray(3.0, ["arm_r"])
				_update_hint("右臂灰化！")
			KEY_7:
				_effects.paint(Color(0.4, 1.0, 0.3), 5.0, ["body"])
				_update_hint("身體著色！")
			KEY_0:
				_outfit.clear_all()
				_effects.clear_all()
				_update_hint("清除全部")

func _update_hint(text: String) -> void:
	if _hint:
		_hint.text = text
