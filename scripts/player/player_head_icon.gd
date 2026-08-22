## 職責：玩家頭頂道具圖標（拾取後出現，約 2 秒出現→保持→消失）
## - Sprite3D billboard 面向相機，layer 4 = UI 標識，不進拍照 RT
## - 動畫：淡入+彈跳 → 保持 → 淡出+上浮

class_name PlayerHeadIcon
extends Sprite3D

## 出現、消失全過程總時長（秒）
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

## 顯示道具圖標，重複拾取時中斷上一段動畫重新播放
func show_item(icon: Texture2D) -> void:
	if _tween:
		_tween.kill()
	texture = icon
	visible = true
	modulate.a = 0.0
	scale = Vector3(0.6, 0.6, 0.6)
	position.y = _base_y

	_tween = create_tween()
	# 淡入 + 彈跳
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(self, "scale", Vector3.ONE, FADE_IN)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 保持
	_tween.tween_interval(DURATION - FADE_IN - FADE_OUT)
	# 淡出 + 上浮
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_property(self, "position:y", _base_y + RISE, FADE_OUT)
	_tween.tween_callback(func(): visible = false)
