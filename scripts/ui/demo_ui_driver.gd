## 职责：Demo 专用 —— 混战开始后按固定时序播放 EventBus 事件，
## 展示服装/道具/时间道具的 HUD 反馈（正式版接入真实拾取系统后移除）。
## 条目：[时间秒, 类型, 参数1, 参数2, 参数3]

class_name DemoUiDriver
extends Node

const EVENTS: Array = [
	[2.0,  "outfit",   0, 0, "outfit_cap"],       # P1 头部：棒球帽
	[3.5,  "outfit",   1, 1, "outfit_jacket"],    # P2 身体：外套
	[5.0,  "outfit",   2, 2, "outfit_wand"],      # P3 手持：魔杖
	[6.5,  "item",     3, 0, "item_energy"],      # P4 捡到能量饮料
	[8.0,  "item_use", 3, 0, "item_energy"],      # P4 使用（灰闪清空）
	[10.0, "time",     0, 0, ""],                 # 快进 2.0x（3 秒）
	[14.0, "outfit",   0, 1, "outfit_dress"],     # P1 同槽替换：身体→裙子
	[17.0, "time",     1, 0, ""],                 # 慢放 0.5x（3 秒）
	[22.0, "item",     0, 0, "item_battery"],     # P1 捡到加时电池
	[23.5, "item_use", 0, 0, "item_battery"],
	[26.0, "time",     2, 0, ""],                 # 加时 +3s
	[31.0, "outfit",   3, 0, "outfit_tophat"],    # P4 头部：礼帽
	[33.0, "time",     3, 0, ""],                 # 减时 -3s（最低 1s）
	[38.0, "outfit",   1, 2, "outfit_balloon"],   # P2 手持：气球
]

const RATE_DURATION := 3.0

var _elapsed: float = 0.0
var _next_index: int = 0
var _active: bool = false

func _ready() -> void:
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)

func _on_battle_started() -> void:
	_elapsed = 0.0
	_next_index = 0
	_active = true

func _on_battle_ended() -> void:
	_active = false
	GameManager.time_rate = 1.0

func _process(delta: float) -> void:
	if not _active:
		return
	if GameManager.current_stage != GameManager.GameStage.BATTLE:
		return
	_elapsed += delta
	while _next_index < EVENTS.size() and _elapsed >= float(EVENTS[_next_index][0]):
		_fire(EVENTS[_next_index])
		_next_index += 1

func _fire(ev: Array) -> void:
	match String(ev[1]):
		"outfit":
			EventBus.outfit_changed.emit(int(ev[2]), int(ev[3]), String(ev[4]))
		"item":
			EventBus.item_picked_up.emit(int(ev[2]), String(ev[4]))
		"item_use":
			EventBus.item_used.emit(int(ev[2]), String(ev[4]))
		"time":
			_apply_time_effect(int(ev[2]))

func _apply_time_effect(kind: int) -> void:
	if GameManager.current_stage != GameManager.GameStage.BATTLE:
		return
	match kind:
		0:
			_apply_rate(HUD.TimeEffect.FAST, 2.0)
		1:
			_apply_rate(HUD.TimeEffect.SLOW, 0.5)
		2:
			var d := GameManager.add_time(3.0)
			EventBus.time_effect_applied.emit(HUD.TimeEffect.ADD, d)
		3:
			var d := GameManager.add_time(-3.0)
			EventBus.time_effect_applied.emit(HUD.TimeEffect.SUB, d)

func _apply_rate(type: int, rate: float) -> void:
	GameManager.time_rate = rate
	EventBus.time_effect_applied.emit(type, rate)
	await get_tree().create_timer(RATE_DURATION).timeout
	# 同类刷新/互斥：只在自己的倍率仍生效时恢复（交互文档 §6）
	if GameManager.time_rate == rate:
		GameManager.time_rate = 1.0
		EventBus.time_effect_applied.emit(type, 0.0)
