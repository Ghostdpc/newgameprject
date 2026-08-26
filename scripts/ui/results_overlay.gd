## 职责：结算覆盖层，展示系统评分并提供返回主界面与退出选项

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
	# TODO: 接入实际 ScoreSystem 结果
	_scores_label.text = "系统评分中...\n（详细结果待实现）"
	_panel.show()

func _on_menu_pressed() -> void:
	GameManager.finish_scoring()

func _on_quit_pressed() -> void:
	get_tree().quit()
