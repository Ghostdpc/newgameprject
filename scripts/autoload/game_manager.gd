## 職責：遊戲整體流程控制，按 GameConfig 驅動各階段順序推進
# 注意：autoload 腳本不使用 class_name，因為 autoload 名稱本身即全局引用
# HUD / ResultsOverlay 使用 GameManager.GameStage 時，GameManager 指 autoload 單例，可正常訪問枚舉

extends Node

enum GameStage {
	MAIN_MENU,       # S0 标题
	LOBBY,           # S1+S2 玩家加入与人数确认
	THEME_ANNOUNCE,  # S3 主題公布（3 秒）
	GRAB_CLOTHES,    # （V1.3 流程已取消，duration=0 自动跳过）
	BATTLE,          # S4 倒計時混戰（搶鏡頭）
	SCORE_SHUTTER,   # S5 快门（由关卡演出，流程不驻留）
	SCORING,         # S6+S7 系統評分 → 冠军结算
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
## 倒計時速率乘數（1.0 = 正常；由 timer_scale_effect 臨時修改）
var time_scale: float = 1.0
var config: GameConfig

## 倒计时倍率（时间道具：快进 2.0 / 慢放 0.5，默认 1.0）
var time_rate: float = 1.0
## 大厅确认的玩家数（2~4，由大厅界面写入，关卡读取）
var lobby_player_count: int = 4
## 每个玩家绑定的输入设备（按出生顺序，与 player_index 对齐）：
##   -2 = 未绑定（自动：P1/P2 键盘，P3/P4 手柄）
##   -1 = 键盘（仅 P1/P2 有效）
##   >=0 = 手柄 device id
var player_devices: Array[int] = [-2, -2, -2, -2]

var _stage_index: int = -1
var _timer_active: bool = false

func _ready() -> void:
	config = GameConfig.new()
	config.load()

## 從主界面進入遊戲，重置流程
func start_game() -> void:
	_stage_index = -1
	time_rate = 1.0
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

	if stage == GameStage.LOBBY:
		_timer_active = false
		get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
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
	stage_time_remaining -= delta * time_rate
	stage_time_remaining = maxf(stage_time_remaining, 0.0)
	EventBus.stage_timer_updated.emit(stage_time_remaining)
	if stage_time_remaining <= 0.0:
		_timer_active = false
		time_rate = 1.0
		if current_stage == GameStage.BATTLE:
			EventBus.battle_ended.emit()
		_advance_stage()

## 加时/减时（交互文档：减时最低保留 1 秒）。返回实际变化量（供飞字显示）
func add_time(delta_seconds: float) -> float:
	var before := stage_time_remaining
	var after := before + delta_seconds
	if delta_seconds < 0.0:
		after = maxf(after, 1.0)
	after = maxf(after, 0.0)
	stage_time_remaining = after
	EventBus.stage_timer_updated.emit(stage_time_remaining)
	return after - before

## 进入大厅（返回房间 / 标题→进入）
func enter_lobby() -> void:
	get_tree().paused = false
	time_rate = 1.0
	_timer_active = false
	_transition_to(GameStage.LOBBY)

## 返回标题
func enter_title() -> void:
	get_tree().paused = false
	time_rate = 1.0
	_timer_active = false
	_transition_to(GameStage.MAIN_MENU)
