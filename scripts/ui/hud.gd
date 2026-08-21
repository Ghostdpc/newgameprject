## 職責：HUD，顯示當前階段名稱與倒計時

class_name HUD
extends CanvasLayer

@onready var _stage_label: Label  = $VBox/StageLabel
@onready var _timer_label: Label  = $VBox/TimerLabel
@onready var _photo_panel: TextureRect = $PhotoPanel

func _ready() -> void:
	EventBus.stage_changed.connect(_on_stage_changed)
	EventBus.stage_timer_updated.connect(_on_timer_updated)
	_bind_photo_panel()

func _bind_photo_panel() -> void:
	var viewport := get_parent().get_node_or_null("PhotoViewport") as SubViewport
	if viewport and _photo_panel:
		_photo_panel.texture = viewport.get_texture()

func _on_timer_updated(seconds: float) -> void:
	_timer_label.text = "%.0f" % ceilf(seconds)

func _on_stage_changed(stage: int) -> void:
	match stage:
		GameManager.GameStage.MAIN_MENU:
			_stage_label.text = ""
			_timer_label.text = ""
		GameManager.GameStage.THEME_ANNOUNCE:
			_stage_label.text = "主題公布"
		GameManager.GameStage.GRAB_CLOTHES:
			_stage_label.text = "搶衣服！"
		GameManager.GameStage.BATTLE:
			_stage_label.text = "搶鏡頭！"
		GameManager.GameStage.SCORING:
			_stage_label.text = ""
			_timer_label.text = ""
