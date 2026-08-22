## 職責：主世界快門前 3 秒逐步减速慢放（正式版）
## 在 BATTLE 階段倒數至 trigger_seconds 时，啟動逐步减速流程，將 Engine.time_scale 降到 min_scale。
## 若期間道具加時使剩餘時間回升（> trigger_seconds + hysteresis），恢復 time_scale=1，
## 直到再次進入 trigger 區間才重新减速。
##
## process_mode = ALWAYS：time_scale 縮小時仍能用牆鐘正常推進計時與監控。
## 慢放不是暫停：保留一個極小流速 min_scale（可選 stop_at_zero 完全停格）。
## 不引用任何 autoload（規避編譯期依賴），剩餘秒由 Level 每幀注入。

class_name ShutterSlowmoController
extends Node

@export var trigger_seconds: float = 3.0   ## 剩餘秒 ≤ 此值啟動减速
@export var decel_time: float = 3.0        ## 减速時長（秒，1→min_scale）
@export var decel_curve: float = 0.3       ## <1 先快後慢
@export var min_scale: float = 0.06        ## 最低時間流速（>0 持續緩慢，0=完全停格）
@export var stop_at_zero: bool = false     ## true=frozen 完全停格；false=停在 min_scale
@export var hysteresis: float = 1.0        ## 加時回升超過此值才取消减速（防抖）
@export var cancellable_by_timer: bool = true  ## 加時時是否允許取消减速恢復

var _active: bool = false
var _phase_elapsed: float = 0.0
var _start_msec: int = 0
var _last_remaining: float = 0.0

var active: bool:
	get:
		return _active

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _process(_delta: float) -> void:
	if not _active:
		return
	# 道具加時把剩餘時間頂回觸發線：恢復 time_scale，退出流程
	if cancellable_by_timer and _last_remaining > trigger_seconds + hysteresis:
		cancel()
		return
	_phase_elapsed = (Time.get_ticks_msec() - _start_msec) / 1000.0
	var t := clampf(_phase_elapsed / decel_time, 0.0, 1.0)
	var cur := lerpf(1.0, min_scale, ease(t, decel_curve))
	Engine.time_scale = cur
	if t >= 1.0 and stop_at_zero:
		Engine.time_scale = 0.0

func _enable() -> void:
	if _active:
		return
	_active = true
	_phase_elapsed = 0.0
	_start_msec = Time.get_ticks_msec()
	Engine.time_scale = 1.0
	set_process(true)

## 取消减速，恢復正常時間流（加時回升 / 戰爭結束 / 關卡離開時）
func cancel() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	Engine.time_scale = 1.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

## 供 Level 在 BATTLE 內每幀注入剩餘秒；倒數至閾值即啟動减速
func update_trigger(seconds_remaining: float) -> void:
	_last_remaining = seconds_remaining
	if not _active and seconds_remaining <= trigger_seconds:
		_enable()
