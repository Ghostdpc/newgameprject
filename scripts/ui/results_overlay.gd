## 職責：結算覆蓋層，展示系統評分並提供返回主界面與退出選項

class_name ResultsOverlay
extends CanvasLayer

@onready var _panel: Control        = $Panel
@onready var _scores_label: Label   = $Panel/Center/VBox/ScoresLabel
@onready var _menu_button: Button   = $Panel/Center/VBox/MenuButton
@onready var _quit_button: Button   = $Panel/Center/VBox/QuitButton

func _ready() -> void:
	_panel.hide()
	EventBus.stage_changed.connect(_on_stage_changed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

func _on_stage_changed(stage: int) -> void:
	if stage == GameManager.GameStage.SCORING:
		_show_results()
	else:
		_panel.hide()

func _show_results() -> void:
	# TODO: 接入實際 ScoreSystem 結果
	_scores_label.text = "系統評分中...\n（詳細結果待實現）"
	_panel.show()

func _on_menu_pressed() -> void:
	GameManager.finish_scoring()

func _on_quit_pressed() -> void:
	get_tree().quit()
