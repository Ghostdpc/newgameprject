## 職責：時間流速控制測試（暫停 / 子弹時間 / 快門慢放流程）
## 用 Engine.time_scale 全局慢放：物理、動畫、彈簧軟糯、計時器全受影響，無需改各對象。
## process_mode=ALWAYS → time_scale=0 暫停時仍能響應按鍵並按牆鐘恢復。
##
## 按鍵：
##   P = 暫停/恢復（掛起 → 凍結整個世界；再按恢復原流速）
##   B(按住) = 子弹時間（瞬間降到目標慢速，松手漸變恢復 1.0）
##   O = 快門慢放流程(toggle)：按一次 → decel_time(1.5s) 逐步减速到完全停格(0)，停住；
##       再按一次立即恢復正常
##   M = 調整子彈時間慢速目標（0.05~0.5，顯示於 Hint）

class_name TimeScaleController
extends Node

const RECOVER_SPEED: float = 2.5   ## 子弹時間松手後恢復速率（每秒 time_scale 增量）

@export var bullet_target: float = 0.08   ## B子彈時間慢速目標（0.05~0.5）
@export var decel_time: float = 3.0       ## 减速時長（秒，1→0），即整個快門流程時長
@export var decel_curve: float = 0.3      ## 减速曲線：<1 先快後慢，>1 先慢後快
var debug_label: Label

enum ShutterPhase { NONE, DECEL, FROZEN }

var _paused: bool = false
var _suspend_scale: float = 1.0   ## 暫停前一個 time_scale（恢復時還原）
var _bullet_active: bool = false
var _recovering: bool = false
var _recover_target: float = 1.0
var _phase: ShutterPhase = ShutterPhase.NONE
var _phase_elapsed: float = 0.0
var _start_msec: int = 0       ## 快門流程開始的牆鐘毫秒（time_scale 縮小不影響計時）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	debug_label = get_node_or_null("../UILayer/Hint") as Label
	if debug_label:
		debug_label.process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	_refresh_hint()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P:
				_toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_B:
				_enter_bullet()
				get_viewport().set_input_as_handled()
			KEY_O:
				_toggle_shutter()
				get_viewport().set_input_as_handled()
			KEY_M:
				bullet_target = clampf(bullet_target - 0.02, 0.05, 0.5)
				if _bullet_active and not _paused:
					Engine.time_scale = bullet_target
				_refresh_hint()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _paused:
		return
	if _phase != ShutterPhase.NONE:
		_tick_shutter(delta)
		return
	if _bullet_active:
		# 按住 B 期間維持慢速
		if not Input.is_key_pressed(KEY_B) and not Input.is_physical_key_pressed(KEY_B):
			_exit_bullet()
	elif _recovering:
		Engine.time_scale = move_toward(Engine.time_scale, _recover_target, RECOVER_SPEED * delta)
		if is_equal_approx(Engine.time_scale, _recover_target):
			Engine.time_scale = _recover_target
			_recovering = false
			_refresh_hint()

## O：toggle 快門慢放流程 —— 按一次進入(1.5s减速→停格)，再按一次立即恢復正常
func _toggle_shutter() -> void:
	if _paused:
		return
	if _phase != ShutterPhase.NONE:
		# 流程中：立即退出並恢復正常
		_phase = ShutterPhase.NONE
		_phase_elapsed = 0.0
		Engine.time_scale = 1.0
		_refresh_hint()
	else:
		_start_shutter()

## 進入快門慢放流程：decel_time 內逐步减速到停格(0)。恢復需再按 O
func _start_shutter() -> void:
	_bullet_active = false
	_recovering = false
	_phase = ShutterPhase.DECEL
	_phase_elapsed = 0.0
	_start_msec = Time.get_ticks_msec()
	_refresh_hint()

func _tick_shutter(delta: float) -> void:
	# 用牆鐘算進度：Engine.time_scale 縮小時 _process 的 delta 也變小，
	# 若累加 delta 會導致永遠到不了停止。牆鐘不受影響。
	_phase_elapsed = (Time.get_ticks_msec() - _start_msec) / 1000.0
	match _phase:
		ShutterPhase.DECEL:
			var t := clampf(_phase_elapsed / decel_time, 0.0, 1.0)
			Engine.time_scale = lerpf(1.0, 0.0, ease(t, decel_curve))
			if t >= 1.0:
				Engine.time_scale = 0.0
				_phase = ShutterPhase.FROZEN
				_refresh_hint()
		ShutterPhase.FROZEN:
			Engine.time_scale = 0.0

func _toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		_suspend_scale = Engine.time_scale
		Engine.time_scale = 0.0
		_phase = ShutterPhase.NONE
		_refresh_hint()
	else:
		Engine.time_scale = _suspend_scale
		_bullet_active = false
		_recovering = false
		_refresh_hint()

func _enter_bullet() -> void:
	if _paused:
		return
	_bullet_active = true
	_recovering = false
	_phase = ShutterPhase.NONE
	Engine.time_scale = bullet_target
	_refresh_hint()

func _exit_bullet() -> void:
	if _paused:
		return
	_bullet_active = false
	_recovering = true
	_recover_target = 1.0
	_refresh_hint()

func _refresh_hint() -> void:
	if not debug_label:
		return
	var st := "暫停" if _paused else "%.2f" % Engine.time_scale
	var phase_txt := {
		ShutterPhase.NONE: "—",
		ShutterPhase.DECEL: "快門·減速中",
		ShutterPhase.FROZEN: "快門·停格",
	}
	var bt: String = "子彈時間" if _bullet_active else phase_txt[_phase]
	debug_label.text = "[P]暫停 [B按住]子彈時間 [O]快門慢放 [M]目標%.2f   time_scale=%s (%s)" % [
		bullet_target, st, bt
	]
