## 職責：換裝 Demo（多槽位穿戴驗證）
## 1/2 帽、3/4 上衣、5/6 背包、9/0 清除全部 —— 穿戴物綁骨槽隨動畫擺動
## 效果：Q全身紅 / W灰 / E頭灰 / R臂灰 / T身綠

class_name OutfitDemoController
extends Node3D

const HAT_SCENE := preload("res://scenes/tech_demos/outfit_items/hat.tscn")
const SHIRT_SCENE := preload("res://scenes/tech_demos/outfit_items/shirt.tscn")
const BACKPACK_SCENE := preload("res://scenes/tech_demos/outfit_items/backpack.tscn")
const ANIM_WALK: String = "Walking_A"

@onready var _outfit: OutfitManager = $RigModel/OutfitManager
@onready var _effects: CharacterEffects = $RigModel/CharacterEffects
@onready var _hint: Label = $UILayer/Feedback
@onready var _anim: AnimationPlayer = _find_anim($RigModel)

func _ready() -> void:
	_outfit.player_color = Color(0.2, 0.6, 1.0)
	if _anim and _anim.has_animation(ANIM_WALK):
		_anim.get_animation(ANIM_WALK).loop_mode = Animation.LOOP_LINEAR
		_anim.play(ANIM_WALK)
	_update_hint("頭/胸口/右肩槽就緒，走路動畫播放中")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_KP_1:
				_outfit.equip("hat_slot", HAT_SCENE)
				_update_hint("戴帽 → head 骨")
			KEY_2, KEY_KP_2:
				_outfit.unequip("hat_slot")
				_update_hint("卸帽")
			KEY_3, KEY_KP_3:
				_outfit.equip("shirt_slot", SHIRT_SCENE)
				_update_hint("穿上衣 → chest 骨")
			KEY_4, KEY_KP_4:
				_outfit.unequip("shirt_slot")
				_update_hint("脫上衣")
			KEY_5, KEY_KP_5:
				_outfit.equip("accessory_slot", BACKPACK_SCENE)
				_update_hint("帶背包 → upperarm.r 骨")
			KEY_6, KEY_KP_6:
				_outfit.unequip("accessory_slot")
				_update_hint("卸背包")
			KEY_Q:
				_effects.paint(Color(1.0, 0.2, 0.2))
				_update_hint("全身繪畫紅")
			KEY_W:
				_effects.apply_gray()
				_update_hint("全身灰化")
			KEY_E:
				_effects.apply_gray(3.0, ["head"])
				_update_hint("頭部灰化")
			KEY_R:
				_effects.apply_gray(3.0, ["arm_r"])
				_update_hint("右臂灰化")
			KEY_T:
				_effects.paint(Color(0.4, 1.0, 0.3), 5.0, ["body"])
				_update_hint("身體著色綠")
			KEY_9, KEY_KP_9, KEY_0, KEY_KP_0:
				_outfit.clear_all(); _effects.clear_all()
				_update_hint("清除全部")

func _update_hint(text: String) -> void:
	if _hint:
		_hint.text = "穿戴：[1]帽 [3]上衣 [5]背包  [2/4/6]卸下  [9/0]清除\n效果：[Q]紅 [W]灰 [E]頭灰 [R]臂灰 [T]身綠\n> " + text

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null
