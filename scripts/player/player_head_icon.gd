## 职责：玩家头顶道具图标（拾取后出现，约 2 秒出现→保持→消失）
## - Sprite3D billboard 面向相机，layer 4 = UI 标识，不进拍照 RT
## - 动画：淡入+弹跳 → 保持 → 淡出+上浮

class_name PlayerHeadIcon
extends Sprite3D

## 出现、消失全过程总时长（秒）
const DURATION: float = 2.0
const FADE_IN: float = 0.15
const FADE_OUT: float = 0.3
const RISE: float = 0.4

var _tween: Tween
var _base_y: float = 0.0

func _ready() -> void:
	_base_y = position.y
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	layers = 4
	modulate.a = 0.0
	visible = false

## 显示道具图标，重复拾取时中断上一段动画重新播放
func show_item(icon: Texture2D) -> void:
	if _tween:
		_tween.kill()
	texture = icon
	visible = true
	modulate.a = 0.0
	scale = Vector3(0.6, 0.6, 0.6)
	position.y = _base_y

	_tween = create_tween()
	# 淡入 + 弹跳
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(self, "scale", Vector3.ONE, FADE_IN)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 保持
	_tween.tween_interval(DURATION - FADE_IN - FADE_OUT)
	# 淡出 + 上浮
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_property(self, "position:y", _base_y + RISE, FADE_OUT)
	_tween.tween_callback(func(): visible = false)
