## 職責：遊戲整體流程控制，按 GameConfig 驅動各階段順序推進
# 注意：autoload 腳本不使用 class_name，避免與 autoload 單例名衝突

extends Node

enum GameStage {
	MAIN_MENU,       # 主界面
	THEME_ANNOUNCE,  # 主題公布
	GRAB_CLOTHES,    # 搶衣服
	BATTLE,          # 倒計時混戰（搶鏡頭）
	SCORING,         # 系統評分
}

## 階段推進順序（不含 MAIN_MENU，由 start_game 觸發）
const STAGE_ORDER: Array = [
	GameStage.THEME_ANNOUNCE,
	GameStage.GRAB_CLOTHES,
	GameStage.BATTLE,
	GameStage.SCORING,
]

var current_stage: GameStage = GameStage.MAIN_MENU
var stage_time_remaining: float = 0.0
var config: GameConfig

var _stage_index: int = -1
var _timer_active: bool = false

func _ready() -> void:
	config = GameConfig.new()
	config.load_from_json()

## 從主界面進入遊戲，重置流程
func start_game() -> void:
	_stage_index = -1
	_advance_stage()

## 結算階段由玩家手動確認結束（用於 scoring_duration = 0 的情況）
func finish_scoring() -> void:
	_timer_active = false
	_advance_stage()

func _advance_stage() -> void:
	_stage_index += 1
	if _stage_index >= STAGE_ORDER.size():
		_transition_to(GameStage.MAIN_MENU)
		return
	_transition_to(STAGE_ORDER[_stage_index])

func _transition_to(stage: GameStage) -> void:
	current_stage = stage
	EventBus.stage_changed.emit(stage)

	if stage == GameStage.MAIN_MENU:
		_timer_active = false
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return

	if stage == GameStage.BATTLE:
		EventBus.battle_started.emit()

	var duration := _get_stage_duration(stage)

	# SCORING 且 duration = 0：停留直到 finish_scoring() 被呼叫
	if stage == GameStage.SCORING and duration <= 0.0:
		_timer_active = false
		return

	# 其他階段 duration = 0：跳過
	if duration <= 0.0:
		call_deferred("_advance_stage")
		return

	stage_time_remaining = duration
	_timer_active = true

func _get_stage_duration(stage: GameStage) -> float:
	match stage:
		GameStage.THEME_ANNOUNCE: return config.theme_announce_duration
		GameStage.GRAB_CLOTHES:   return config.grab_clothes_duration
		GameStage.BATTLE:         return config.battle_duration
		GameStage.SCORING:        return config.scoring_duration
	return 0.0

func _process(delta: float) -> void:
	if not _timer_active:
		return
	stage_time_remaining -= delta
	stage_time_remaining = maxf(stage_time_remaining, 0.0)
	EventBus.stage_timer_updated.emit(stage_time_remaining)
	if stage_time_remaining <= 0.0:
		_timer_active = false
		if current_stage == GameStage.BATTLE:
			EventBus.battle_ended.emit()
		_advance_stage()
