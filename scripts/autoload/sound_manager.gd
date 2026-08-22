## 职责：全局音频 —— BGM 随流程阶段切换 + 各类音效（EventBus 信号驱动）
## BGM：DreamMaker 生成（title/battle 两首）；SFX：程序合成卡通风（assets/audio/sfx/）

class_name SoundManager
extends Node

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_TITLE := preload("res://assets/audio/bgm/title.mp3")
const BGM_BATTLE := preload("res://assets/audio/bgm/battle.mp3")
const BGM_VOLUME := -6.0

const SFX_NAMES := [
	"ui_click", "join", "confirm", "tick", "battle_start",
	"pickup", "interrupt", "item_use", "time_fast", "time_slow",
	"time_add", "time_sub", "hit", "shutter", "score_tick", "champion",
]

var _streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _bgm_current: String = ""
var _last_tick_sec: int = -1

func _ready() -> void:
	for n in SFX_NAMES:
		_streams[n] = load(SFX_DIR + n + ".wav")
	for i in 8:   # 简单复音池
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = BGM_VOLUME
	add_child(_bgm)

	EventBus.item_picked_up.connect(func(_i: int, _id: String): play("pickup", true))
	EventBus.item_used.connect(func(_i: int, _id: String): play("item_use"))
	EventBus.trap_triggered.connect(func(_t: String, _i: int): play("hit"))
	EventBus.time_effect_applied.connect(_on_time_effect)
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.photo_taken.connect(func(tex: ViewportTexture):
		if tex != null:
			play("shutter"))
	EventBus.stage_changed.connect(_on_stage_changed)
	EventBus.stage_timer_updated.connect(_on_timer)
	# 首启时 MAIN_MENU 不会发 stage_changed，直接起标题 BGM
	_switch_bgm("title" if GameManager.current_stage != GameManager.GameStage.BATTLE else "battle")

# ---------------------------------------------------------------- SFX
func play(sfx_name: String, pitch_rand: bool = false) -> void:
	var s = _streams.get(sfx_name)
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.pitch_scale = randf_range(0.94, 1.06) if pitch_rand else 1.0
	p.play()

func _free_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[randi() % _sfx_players.size()]

func _on_time_effect(type: int, value: float) -> void:
	if value <= 0.0:
		return
	match type:
		0: play("time_fast")
		1: play("time_slow")
		2: play("time_add")
		3: play("time_sub")

## 最后 3 秒倒数滴答
func _on_timer(seconds: float) -> void:
	if GameManager.current_stage != GameManager.GameStage.BATTLE:
		_last_tick_sec = -1
		return
	var n := ceili(seconds)
	if n == _last_tick_sec:
		return
	_last_tick_sec = n
	if n <= 3 and n > 0:
		play("tick")

# ---------------------------------------------------------------- BGM
func _on_battle_started() -> void:
	play("battle_start")
	_switch_bgm("battle")

func _on_stage_changed(stage: int) -> void:
	match stage:
		GameManager.GameStage.MAIN_MENU, GameManager.GameStage.LOBBY, \
		GameManager.GameStage.THEME_ANNOUNCE:
			_switch_bgm("title")
		GameManager.GameStage.SCORING:
			_fade_bgm_out()

func _switch_bgm(key: String) -> void:
	if _bgm_current == key and _bgm.playing:
		return
	_bgm_current = key
	_bgm.volume_db = BGM_VOLUME
	_bgm.stream = BGM_TITLE if key == "title" else BGM_BATTLE
	_bgm.play()

func _fade_bgm_out() -> void:
	_bgm_current = ""
	if not _bgm.playing:
		return
	var tw := create_tween()
	tw.tween_property(_bgm, "volume_db", -40.0, 0.8)
	tw.tween_callback(_bgm.stop)
