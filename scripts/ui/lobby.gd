## 职责：大厅加入 / 就绪界面（S1 加入 + S2 人数/就绪确认）
## 视觉：背景 + 差分滚动条（相邻行左右反向滚动），四张玩家卡片（空位 / 已加入 / 已就绪）
## 开始规则：全员就绪（>=2 人且所有已加入者均就绪）后短暂延时自动进入对战
## 手柄输入（PlayStation 键位）：
##   - □ 方块：加入（占用下一空位，显示已加入）
##   - △ 三角：加入后准备（显示已准备）
##   - ✕ 叉：准备后取消准备
##   - ○ 圈：加入后取消加入；未加入时返回标题
## 键盘/鼠标（调试）：数字键 1~4 / 点卡片循环 空位→已加入→已就绪→空位；Esc 返回；Backspace 退出最后一位

class_name Lobby
extends Control

const SCROLL_TEX: Texture2D = preload("res://assets/textures/ui/lobby/scroll_band.png")
const SCROLL_SPEED := 42.0
const AUTOSTART_DELAY := 1.1

var _joined: Array[bool] = [false, false, false, false]
var _ready_flags: Array[bool] = [false, false, false, false]
## 槽位綁定設備：-2 空位 / -1 鍵盤 / >=0 手柄 device id
var _slot_devices: Array[int] = [-2, -2, -2, -2]
var _cards: Array[LobbyCard] = []

var _rows: Array[TextureRect] = []
var _row_dirs: Array[float] = []
var _starting := false

@onready var _scroll_layer: Control = $ScrollLayer
@onready var _card_row: HBoxContainer = $Center/CardRow

func _ready() -> void:
	GameManager.current_stage = GameManager.GameStage.LOBBY
	for i in 4:
		var card := _card_row.get_child(i) as LobbyCard
		card.setup(i, PlayerConfig.get_color(i))
		card.gui_input.connect(_on_card_gui_input.bind(i))
		_cards.append(card)
	_build_scroll_rows()
	_refresh()

# ---------------------------------------------------------------- 差分滚动背景
func _build_scroll_rows() -> void:
	var view := get_viewport_rect().size
	var band_w := float(SCROLL_TEX.get_width())
	var band_h := float(SCROLL_TEX.get_height())
	var count := int(ceil(view.y / band_h)) + 1
	for i in count:
		var row := TextureRect.new()
		row.texture = SCROLL_TEX
		row.stretch_mode = TextureRect.STRETCH_TILE
		row.size = Vector2(view.x + band_w, band_h)
		row.position = Vector2(-band_w * randf(), i * band_h)
		row.modulate = Color(1, 1, 1, 0.5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scroll_layer.add_child(row)
		_rows.append(row)
		_row_dirs.append(1.0 if i % 2 == 0 else -1.0)

func _process(delta: float) -> void:
	var band_w := float(SCROLL_TEX.get_width())
	for i in _rows.size():
		var row := _rows[i]
		var x := row.position.x - _row_dirs[i] * SCROLL_SPEED * delta
		if x <= -band_w:
			x += band_w
		elif x > 0.0:
			x -= band_w
		row.position.x = x

# ---------------------------------------------------------------- 状态刷新
func _joined_count() -> int:
	var n := 0
	for j in _joined:
		if j:
			n += 1
	return n

func _slot_for_device(device: int) -> int:
	for i in 4:
		if _joined[i] and _slot_devices[i] == device:
			return i
	return -1

func _all_ready() -> bool:
	if _joined_count() < 2:
		return false
	for i in 4:
		if _joined[i] and not _ready_flags[i]:
			return false
	return true

func _refresh() -> void:
	for i in 4:
		var state := LobbyCard.State.EMPTY
		if _joined[i]:
			state = LobbyCard.State.READY if _ready_flags[i] else LobbyCard.State.JOINED
		_cards[i].set_state(state)
	_maybe_autostart()

# ---------------------------------------------------------------- 加入 / 就绪
func _set_joined(index: int, device: int) -> void:
	_joined[index] = true
	_ready_flags[index] = false
	_slot_devices[index] = device
	SoundMgr.play("join", true)

func _leave_slot(index: int) -> void:
	_joined[index] = false
	_ready_flags[index] = false
	_slot_devices[index] = -2
	SoundMgr.play("ui_click")

func _set_ready(index: int, value: bool) -> void:
	_ready_flags[index] = value
	SoundMgr.play("confirm" if value else "ui_click")

## 数字键 / 鼠标：循环 空位 → 已加入 → 已就绪 → 空位
func _cycle_slot(index: int) -> void:
	if not _joined[index]:
		_set_joined(index, -1 if index <= 1 else index)
	elif not _ready_flags[index]:
		_set_ready(index, true)
	else:
		_leave_slot(index)
	_refresh()

## 手柄 A：加入下一空位并绑定设备
func _join_next(device: int) -> void:
	var range_slots := [0, 1] if device == -1 else [0, 1, 2, 3]
	for i in range_slots:
		if not _joined[i]:
			_set_joined(i, device)
			_refresh()
			return

func _remove_last() -> void:
	for i in range(3, -1, -1):
		if _joined[i]:
			_leave_slot(i)
			_refresh()
			return

## □ 方块：加入下一空位
func _on_join(device: int) -> void:
	if _slot_for_device(device) >= 0:
		return
	_join_next(device)

## △ 三角：加入后准备
func _on_ready(device: int) -> void:
	var slot := _slot_for_device(device)
	if slot >= 0 and not _ready_flags[slot]:
		_set_ready(slot, true)
		_refresh()

## ✕ 叉：准备后取消准备
func _on_cancel_ready(device: int) -> void:
	var slot := _slot_for_device(device)
	if slot >= 0 and _ready_flags[slot]:
		_set_ready(slot, false)
		_refresh()

## ○ 圈：加入后取消加入；未加入时返回标题
func _on_cancel_join(device: int) -> void:
	var slot := _slot_for_device(device)
	if slot < 0:
		_on_back()
		return
	if _ready_flags[slot]:
		return
	_leave_slot(slot)
	_refresh()

func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_cycle_slot(index)

# ---------------------------------------------------------------- 自动开始
func _maybe_autostart() -> void:
	if _starting or not _all_ready():
		return
	_starting = true
	await get_tree().create_timer(AUTOSTART_DELAY).timeout
	if _all_ready():
		_do_start()
	else:
		_starting = false

func _do_start() -> void:
	SoundMgr.play("confirm")
	GameManager.lobby_player_count = _joined_count()
	GameManager.player_devices = _slot_devices.duplicate()
	GameManager.goto_level("res://scenes/levels/room_stage_battle.tscn")

func _on_back() -> void:
	GameManager.enter_title()

# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		match jb.button_index:
			JOY_BUTTON_X: _on_join(jb.device)          # □ 方块 加入
			JOY_BUTTON_Y: _on_ready(jb.device)         # △ 三角 准备
			JOY_BUTTON_A: _on_cancel_ready(jb.device)  # ✕ 叉 取消准备
			JOY_BUTTON_B: _on_cancel_join(jb.device)   # ○ 圈 取消加入 / 返回
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		return
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_1: _cycle_slot(0)
			KEY_2: _cycle_slot(1)
			KEY_3: _cycle_slot(2)
			KEY_4: _cycle_slot(3)
			KEY_BACKSPACE, KEY_X: _remove_last()
