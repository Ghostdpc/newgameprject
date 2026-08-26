## 职责：联机房间面板 —— 中文房间码开房 / 进房
## host：创建房间 → 显示 IPv4（局域网）/ IPv6（跨网）房间码，可一键复制 → 进入大厅
## client：直接打字输入房间码 → 加入房间（无需手柄选字表）

class_name NetTestPanel
extends Control

@onready var _password: LineEdit = $Panel/Margin/VBox/Password
@onready var _room_name: LineEdit = $Panel/Margin/VBox/HostSection/RoomName
@onready var _mode: OptionButton = $Panel/Margin/VBox/HostSection/Mode
@onready var _code_box: VBoxContainer = $Panel/Margin/VBox/HostSection/CodeBox
@onready var _code4_row: HBoxContainer = $Panel/Margin/VBox/HostSection/CodeBox/Code4Row
@onready var _code4_value: Label = $Panel/Margin/VBox/HostSection/CodeBox/Code4Row/Value
@onready var _code6_row: HBoxContainer = $Panel/Margin/VBox/HostSection/CodeBox/Code6Row
@onready var _code6_value: Label = $Panel/Margin/VBox/HostSection/CodeBox/Code6Row/Value
@onready var _enter_lobby: Button = $Panel/Margin/VBox/HostSection/EnterLobby
@onready var _code_input: LineEdit = $Panel/Margin/VBox/JoinSection/CodeInput
@onready var _status: Label = $Panel/Margin/VBox/Status

func _ready() -> void:
	$Panel/Margin/VBox/HostSection/HostButton.pressed.connect(_on_host)
	$Panel/Margin/VBox/HostSection/CodeBox/Code4Row/Copy.pressed.connect(_on_copy4)
	$Panel/Margin/VBox/HostSection/CodeBox/Code6Row/Copy.pressed.connect(_on_copy6)
	$Panel/Margin/VBox/HostSection/EnterLobby.pressed.connect(_on_enter_lobby)
	$Panel/Margin/VBox/JoinSection/JoinButton.pressed.connect(_on_join)
	$Panel/Margin/VBox/BackButton.pressed.connect(_on_back)
	NetManager.connected_to_server.connect(_on_connected)
	NetManager.connection_failed.connect(_on_conn_failed)
	_code_input.grab_focus()

func _on_host() -> void:
	var room := _room_name.text.strip_edges()
	if room.is_empty():
		room = "测试房"
	var err := NetManager.host_game(room, _password.text, NetManager.DEFAULT_PORT, _mode.selected == 1)
	if err != OK:
		_status.text = "创建失败: %s" % error_string(err)
		return
	_code4_row.visible = not NetManager.ipv4_code.is_empty()
	_code6_row.visible = not NetManager.ipv6_code.is_empty()
	_code4_value.text = NetManager.ipv4_code
	_code6_value.text = NetManager.ipv6_code
	_code_box.visible = true
	_enter_lobby.visible = true
	if NetManager.ipv4_code.is_empty():
		_status.text = "已创建（跨网 IPv6），把房间码发给好友即可加入"
	else:
		_status.text = "已创建（局域网 IPv4），把房间码发给好友即可加入"

func _on_copy4() -> void:
	DisplayServer.clipboard_set(NetManager.ipv4_code)
	_status.text = "已复制局域网房间码"

func _on_copy6() -> void:
	DisplayServer.clipboard_set(NetManager.ipv6_code)
	_status.text = "已复制跨网房间码"

func _on_enter_lobby() -> void:
	GameManager.enter_lobby()

func _on_join() -> void:
	var code := _code_input.text.strip_edges()
	if code.is_empty():
		_status.text = "请输入房间码"
		return
	var err := NetManager.join_by_code(code, _password.text)
	if err != OK:
		_status.text = "连接失败: %s" % error_string(err)
		return
	_status.text = "正在连接..."

func _on_connected() -> void:
	_status.text = "连接成功，进入大厅"
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _on_conn_failed(reason: String) -> void:
	_status.text = "连接失败: %s" % reason

func _on_back() -> void:
	if NetManager.is_online:
		NetManager.leave_game()
	GameManager.enter_title()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
