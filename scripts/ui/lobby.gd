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
## client：申请加入时暂存的待绑定设备（host 分配到席位后写入对应槽位）
var _pending_join_device: int = -2
## client：已在途的加入申请设备（防止同设备在 host 确认前重复申请）
var _pending_join_devices: Array[int] = []
## client：本端各键盘席位的设备（-1 统一键盘），供编号与战斗输入
var _client_devices: Dictionary = {}

var _rows: Array[TextureRect] = []
var _row_dirs: Array[float] = []
var _starting := false

@onready var _scroll_layer: Control = $ScrollLayer
@onready var _card_row: HBoxContainer = $Center/CardRow
@onready var _room_code_row: HBoxContainer = $Header/RoomCodeRow
@onready var _room_code_value: Label = $Header/RoomCodeRow/Value

func _ready() -> void:
	GameManager.current_stage = GameManager.GameStage.LOBBY
	$Header/RoomCodeRow/CopyButton.pressed.connect(_on_copy_code)
	for i in 4:
		var card := _card_row.get_child(i) as LobbyCard
		card.setup(i, PlayerConfig.get_color(i))
		card.gui_input.connect(_on_card_gui_input.bind(i))
		_cards.append(card)
	_build_scroll_rows()
	if NetManager.is_online:
		NetManager.seat_owners_changed.connect(_on_net_seats_changed)
		NetManager.join_rejected.connect(_on_join_rejected)
	_update_mode_label()
	_refresh()

## 顶部副标题显示当前模式（本地 / 联机房主 / 联机客户端）
func _update_mode_label() -> void:
	var sub := get_node_or_null("Header/SubLabel") as Label
	if sub == null:
		return
	if not NetManager.is_online:
		sub.text = "本地 4 人同屏 · 按下按钮加入"
		_room_code_row.visible = false
	elif NetManager.is_host:
		sub.text = "联机 · 房主 · 房间「%s」" % NetManager.room_name
		_show_room_code()
	else:
		sub.text = "联机 · 客户端 · 房间「%s」 · 按 空格/△ 就绪" % NetManager.room_name
		_room_code_row.visible = false

## host：显示主房间码（优先 IPv4 局域网码，无则 IPv6）+ 复制按钮
func _show_room_code() -> void:
	var code := NetManager.ipv4_code if not NetManager.ipv4_code.is_empty() else NetManager.ipv6_code
	_room_code_row.visible = not code.is_empty()
	_room_code_value.text = code

func _on_copy_code() -> void:
	var code := NetManager.ipv4_code if not NetManager.ipv4_code.is_empty() else NetManager.ipv6_code
	if not code.is_empty():
		DisplayServer.clipboard_set(code)

## 联机：席位表变化时刷新大厅卡片（远端席位显示已加入）
func _on_net_seats_changed() -> void:
	_refresh()

## 联机：加入被拒（房间满），清除本端在途申请
func _on_join_rejected() -> void:
	_pending_join_devices.clear()
	_pending_join_device = -2

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
	# 联机：host 判定全员就绪（client 不自启）
	if NetManager.is_online:
		if not NetManager.is_host:
			return false
		if NetManager.get_occupied_seat_count() < 2:
			return false
		for o: Dictionary in NetManager.seat_owners:
			if o["kind"] != NetManager.SeatKind.EMPTY and not o["ready"]:
				return false
		return true
	# 本地
	if _joined_count() < 2:
		return false
	for i in 4:
		if _joined[i] and not _ready_flags[i]:
			return false
	return true

## 联机：远端席位数量
func _remote_count() -> int:
	var n := 0
	for o: Dictionary in NetManager.seat_owners:
		if o["kind"] == NetManager.SeatKind.REMOTE:
			n += 1
	return n

## 联机 client
func _is_net_client() -> bool:
	return NetManager.is_online and not NetManager.is_host

func _refresh() -> void:
	if _is_net_client():
		_reconcile_client_seats()
	for i in 4:
		var state := LobbyCard.State.EMPTY
		if NetManager.is_online:
			var o: Dictionary = NetManager.seat_owners[i]
			if o["kind"] != NetManager.SeatKind.EMPTY:
				state = LobbyCard.State.READY if o["ready"] else LobbyCard.State.JOINED
		elif _joined[i]:
			state = LobbyCard.State.READY if _ready_flags[i] else LobbyCard.State.JOINED
		_cards[i].set_state(state)
		_cards[i].set_device(_device_label(i))
	_maybe_autostart()

# ---------------------------------------------------------------- 设备标签

## 计算槽位的操作方式文本（卡片下方显示）。联机只标本端角色，远端留空。
func _device_label(i: int) -> String:
	if not _is_local_slot(i):
		return ""
	var dev := _local_device(i)
	if dev < 0:
		var n := _keyboard_number(i)
		return "键盘%d" % (n if n > 0 else 1)
	return "手柄%d" % dev

## 联机取本端角色的本地设备：client 用本端上报的设备；host 走本端 _slot_devices
func _local_device(i: int) -> int:
	if NetManager.is_online:
		if _is_net_client():
			if _client_devices.has(i):
				return int(_client_devices[i])
			return -2
		# host：本端本地席位用 _slot_devices（远端不显示，不会走到这）
		if i < _slot_devices.size():
			return _slot_devices[i]
		return -2
	if i < _slot_devices.size():
		return _slot_devices[i]
	return -2

## 键盘角色序号：所有本端键盘角色按席位升序编号 1..N（例：P1,P3 键盘 → P1=键盘1、P3=键盘2）
func _keyboard_number(i: int) -> int:
	var kb: Array[int] = []
	for s in 4:
		if _is_local_slot(s) and _local_device(s) < 0:
			kb.append(s)
	var n := kb.find(i)
	return n + 1 if n >= 0 else 0

## 该槽位是否本端可操作的角色（联机仅本端席位；本地仅已加入）
func _is_local_slot(i: int) -> bool:
	if NetManager.is_online:
		return i in NetManager.get_my_seats()
	return _joined[i]

# ---------------------------------------------------------------- 加入 / 就绪
## host 本地：占席位；client：向 host 申请
func _set_joined(index: int, device: int) -> void:
	_joined[index] = true
	_ready_flags[index] = false
	_slot_devices[index] = device
	if NetManager.is_online and NetManager.is_host:
		# host：本地席位写入席位表（source of truth）
		NetManager.claim_local_seat(index, device)
	else:
		# 本地同屏：无网络动作
		pass
	if NetManager.is_online and not NetManager.is_host:
		# client：先不落槽位（席位编号由 host 分配/确认），暂存设备并申请期望槽位
		_joined[index] = false
		_slot_devices[index] = -2
		_pending_join_device = device
		NetManager.join_seat(device, index)
		return
	SoundMgr.play("join", true)

## host 本地：释放席位；client：申请退出
func _leave_slot(index: int) -> void:
	_joined[index] = false
	_ready_flags[index] = false
	var dev := _slot_devices[index]
	_slot_devices[index] = -2
	if NetManager.is_online and NetManager.is_host:
		NetManager.free_seat(index)
	elif NetManager.is_online and not NetManager.is_host:
		NetManager.leave_my_seat(index)
	_client_devices.erase(index)
	SoundMgr.play("ui_click")

func _set_ready(index: int, value: bool) -> void:
	_ready_flags[index] = value
	if NetManager.is_online:
		NetManager.set_seat_ready(index, value)
	SoundMgr.play("confirm" if value else "ui_click")

## client：根据 host 广播的最新席位表，同步「我实际拥有的席位 + 设备」
func _reconcile_client_seats() -> void:
	if not _is_net_client():
		return
	for i in 4:
		var is_mine := i in NetManager.get_my_seats()
		if is_mine and not _joined[i]:
			_joined[i] = true
			_ready_flags[i] = false
			var dev := int(_pending_join_device) if _pending_join_device != -2 else _slot_devices[i]
			_slot_devices[i] = dev
			_client_devices[i] = dev
			GameManager.player_devices[i] = dev
			if dev >= 0:
				_pending_join_devices.erase(dev)
			_pending_join_device = -2
			SoundMgr.play("join", true)
		elif not is_mine and _joined[i]:
			_joined[i] = false
			_ready_flags[i] = false
			_slot_devices[i] = -2
			_client_devices.erase(i)

## 数字键 / 鼠标：循环 空位 → 已加入 → 已就绪 → 空位（键盘类操作）
func _cycle_slot(index: int) -> void:
	if NetManager.is_online:
		# 联机：只操作空槽位与本端自己的席位（防键盘 1~4 抢占对端席位卡死）
		var o: Dictionary = NetManager.seat_owners[index]
		if o["kind"] != NetManager.SeatKind.EMPTY and not (index in NetManager.get_my_seats()):
			_refresh()
			return
		if o["kind"] == NetManager.SeatKind.EMPTY:
			_set_joined(index, -1)
		elif _is_net_client():
			NetManager.set_seat_ready(index, not o["ready"])
		else:
			if not _ready_flags[index]:
				_set_ready(index, true)
			else:
				_leave_slot(index)
		_refresh()
		return
	if not _joined[index]:
		_set_joined(index, -1)
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
			# 联机 host：跳过已被远端占用的席位
			if NetManager.is_online and NetManager.is_host \
					and NetManager.seat_owners[i]["kind"] != NetManager.SeatKind.EMPTY:
				continue
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
	if _is_net_client():
		# client 加入是异步的（host 分配），防在途重复：同手柄设备、或键盘已有一个在途申请
		if device < 0 and not _pending_join_devices.is_empty():
			return
		if device < 0 and _pending_join_device != -2:
			return
		if device >= 0 and device in _pending_join_devices:
			return
		if device >= 0:
			_pending_join_devices.append(device)
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
		if not NetManager.is_online:
			_cycle_slot(index)
			return
		# 联机：只能操作空槽位与本端自己的席位，禁止点击/抢占对端席位（否则席位冲突卡死）
		var o: Dictionary = NetManager.seat_owners[index]
		if o["kind"] == NetManager.SeatKind.EMPTY:
			_set_joined(index, -1)  # 点空位：host 本地加入 / client 键盘申请加入
			return
		if not (index in NetManager.get_my_seats()):
			return  # 点对端席位：无操作
		if _is_net_client():
			NetManager.set_seat_ready(index, not o["ready"])
		else:
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
	if NetManager.is_online and not NetManager.is_host:
		return  # 联机 client 由 host 启动
	SoundMgr.play("confirm")
	GameManager.player_devices = _slot_devices.duplicate()
	if NetManager.is_online and NetManager.is_host:
		# 远端席位 player_devices 保持 -2（由 RemoteInputProvider 接管）
		GameManager.lobby_player_count = NetManager.get_occupied_seat_count()
	else:
		GameManager.lobby_player_count = _joined_count()
	GameManager.goto_level("res://scenes/levels/room_stage_battle.tscn")

func _on_back() -> void:
	if NetManager.is_online:
		NetManager.leave_game()
	GameManager.enter_title()

# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		return
	# 联机 client：也用本机设备加入/退出/就绪（由 host 分配席位）
	if _is_net_client():
		if event is InputEventJoypadButton:
			var jb := event as InputEventJoypadButton
			match jb.button_index:
				JOY_BUTTON_X: _on_join(jb.device)          # □ 加入
				JOY_BUTTON_Y: _on_ready(jb.device)         # △ 准备
				JOY_BUTTON_A: _on_cancel_ready(jb.device)  # ✕ 取消准备
				JOY_BUTTON_B: _on_cancel_join(jb.device)   # ○ 退出 / 返回
			return
		if event is InputEventKey:
			match (event as InputEventKey).keycode:
				KEY_1: _cycle_slot(0)
				KEY_2: _cycle_slot(1)
				KEY_3: _cycle_slot(2)
				KEY_4: _cycle_slot(3)
				KEY_BACKSPACE, KEY_X: _remove_last()
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
