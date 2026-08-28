## 职责：主世界快门前 3 秒逐步减速慢放（正式版）
## 在 BATTLE 阶段倒数至 trigger_seconds 时，启动逐步减速流程，将 NetManager.gameplay_time_scale 降到 min_scale。
## 若期间道具加时使剩余时间回升（> trigger_seconds + hysteresis），恢复 time_scale=1，
## 直到再次进入 trigger 区间才重新减速。
##
## process_mode = ALWAYS：time_scale 缩小时仍能用墙钟正常推进计时与监控。
## 慢放不是暂停：保留一个极小流速 min_scale（可选 stop_at_zero 完全停格）。
## 不引用任何 autoload（规避编译期依赖），剩余秒由 Level 每帧注入。

class_name ShutterSlowmoController
extends Node

@export var trigger_seconds: float = 2.0   ## 剩余秒 ≤ 此值启动减速
@export var decel_time: float = 3.0        ## 减速时长（秒，1→min_scale）
@export var decel_curve: float = 0.3       ## <1 先快后慢
@export var min_scale: float = 0.3         ## 最低时间流速：倒计时随此速率收尾（过低会卡死流程）
@export var stop_at_zero: bool = false     ## true=frozen 完全停格（会卡倒计时，仅调试用）
@export var hysteresis: float = 1.0        ## 加时回升超过此值才取消减速（防抖）
@export var cancellable_by_timer: bool = true  ## 加时时是否允许取消减速恢复

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
	# 道具加时把剩余时间顶回触发线：恢复 time_scale，退出流程
	if cancellable_by_timer and _last_remaining > trigger_seconds + hysteresis:
		cancel()
		return
	_phase_elapsed = (Time.get_ticks_msec() - _start_msec) / 1000.0
	var t := clampf(_phase_elapsed / decel_time, 0.0, 1.0)
	var cur := lerpf(1.0, min_scale, ease(t, decel_curve))
	NetManager.set_time_scale(cur)
	if t >= 1.0 and stop_at_zero:
		NetManager.set_time_scale(0.0)

func _enable() -> void:
	if _active:
		return
	_active = true
	_phase_elapsed = 0.0
	_start_msec = Time.get_ticks_msec()
	NetManager.set_time_scale(1.0)
	set_process(true)

## 取消减速，恢复正常时间流（加时回升 / 战争结束 / 关卡离开时）
func cancel() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	NetManager.set_time_scale(1.0)

func _exit_tree() -> void:
	NetManager.set_time_scale(1.0)

## 供 Level 在 BATTLE 内每帧注入剩余秒；倒数至阈值即启动减速
func update_trigger(seconds_remaining: float) -> void:
	_last_remaining = seconds_remaining
	if not _active and seconds_remaining <= trigger_seconds:
		_enable()
