## 职责：联机网络管理（ENet listen-server / client），零服务器方案传输层
## 拓扑：host 权威（host 模拟全部席位，client 采集输入 + 播放表现）
## 入房：中文房间码（RoomCode 编解码 IP:端口）。host 开房生成 IPv4 码（局域网）
## 与 IPv6 码（跨网直连），client 输入任一码进房。IPv4 码 5 字、IPv6 码 13 字。
## 注意：autoload 脚本不使用 class_name，autoload 名称本身即全局引用

extends Node

enum SeatKind { EMPTY, LOCAL, REMOTE }

signal server_started()
signal connected_to_server()
signal connection_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal server_stopped()
signal seat_owners_changed()
signal join_rejected()

const DEFAULT_PORT: int = 7001
const MAX_SEATS: int = 4

## 握手/席位关键日志写文件（双开无控制台也能排查）
func _log_net(side: String, msg: String) -> void:
	var line := "[%s] [%s] %s" % [side, Time.get_time_string_from_system(), msg]
	print(line)
	var f := FileAccess.open("user://net_debug.log", FileAccess.WRITE)
	if f:
		f.store_string(FileAccess.get_file_as_string("user://net_debug.log") + line + "\n")
		f.close()

var is_host: bool = false
var is_online: bool = false
var room_name: String = ""
var password: String = ""
var my_peer_id: int = 0
var server_port: int = DEFAULT_PORT
## 开房生成的中文房间码（IPv4 局域网 / IPv6 跨网，无对应地址时为空串）
var ipv4_code: String = ""
var ipv6_code: String = ""

## 席位所有权 0-3：{"kind": SeatKind, "device": int, "peer_id": int}
var seat_owners: Array = []

var _enet: ENetMultiplayerPeer
## seat -> RemoteInputProvider（host 侧远端席位输入源）
var _remote_inputs: Dictionary = {}
## 快照广播计数器（30Hz）
var _snapshot_frame_counter: int = 0
## 关卡相机分区索引（host 选择后广播，client 读取；-1 = 未定）
var zone_index: int = -1
## client：是否已通知 UI 进入大厅（防重复切场景）
var _lobby_entered: bool = false

func _ready() -> void:
	# 暂停状态下仍需收发 RPC（暂停是 get_tree().paused，对端恢复指令需送达）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_seats()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _physics_process(_delta: float) -> void:
	# 注意：RemoteInputProvider 的边缘推进在 apply_input（RPC 到达）时完成。
	# 不能在 physics 每帧无条件 prev=cur —— RPC 在 idle 阶段更新 cur，physics 阶段的
	# 无条件推进会在状态机查询前把新 level 移入 prev，导致 cur==prev、边缘恒 false。
	# client：上行本端席位输入（仅已绑定设备的席位，60Hz）
	if is_online and not is_host:
		for seat in get_my_seats():
			if GameManager.player_devices[seat] != -2:
				send_local_input(seat)
	# host：状态快照广播（30Hz，每2物理帧）
	if is_host:
		_snapshot_frame_counter += 1
		if _snapshot_frame_counter >= 2:
			_snapshot_frame_counter = 0
			_broadcast_state_snapshot()

func _init_seats() -> void:
	seat_owners.clear()
	for i in MAX_SEATS:
		seat_owners.append({"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false})

# ---------------------------------------------------------------- 创建 / 加入 / 离开

## host 开房（listen server）。生成中文房间码。返回 Error
## ENet 只能绑单一协议栈（Windows 下 "::" 默认仅 IPv6），由 prefer_ipv6 选栈：
##   false=局域网（优先 IPv4），true=跨网（优先 IPv6）。所选栈无地址时自动回退另一栈。
func host_game(p_room_name: String, p_password: String = "", port: int = DEFAULT_PORT, prefer_ipv6: bool = false) -> Error:
	ipv4_code = ""
	ipv6_code = ""
	var addrs := _collect_addresses()
	var bind_ip := ""
	if prefer_ipv6:
		if addrs.has("ipv6"):
			bind_ip = "::"
		elif addrs.has("ipv4"):
			bind_ip = "*"
	else:
		if addrs.has("ipv4"):
			bind_ip = "*"
		elif addrs.has("ipv6"):
			bind_ip = "::"
	if bind_ip.is_empty():
		return ERR_CANT_CREATE
	_enet = ENetMultiplayerPeer.new()
	var err := _create_server_socket(bind_ip, port)
	if err != OK:
		# 首选协议栈绑定失败时回退另一栈
		var alt := ""
		if bind_ip == "*" and addrs.has("ipv6"):
			alt = "::"
		elif bind_ip == "::" and addrs.has("ipv4"):
			alt = "*"
		if not alt.is_empty():
			bind_ip = alt
			err = _create_server_socket(bind_ip, port)
	if err != OK:
		_enet = null
		return err
	multiplayer.multiplayer_peer = _enet
	is_host = true
	is_online = true
	room_name = p_room_name
	password = p_password
	server_port = port
	my_peer_id = multiplayer.get_unique_id()
	if bind_ip == "::":
		ipv6_code = RoomCode.encode_ipv6(addrs["ipv6"], port)
	else:
		ipv4_code = RoomCode.encode_ipv4(addrs["ipv4"], port)
	_log_net("host", "开房 bind=%s ipv4码=%s ipv6码=%s" % [bind_ip, ipv4_code, ipv6_code])
	server_started.emit()
	return OK

## 按指定 bind_ip 创建 ENet 服务器
func _create_server_socket(bind_ip: String, port: int) -> Error:
	_enet.set_bind_ip(bind_ip)
	return _enet.create_server(port, MAX_SEATS - 1)

## 收集本机可用的 IPv4（局域网）与全局 IPv6（跨网）地址
## IPv4 跳过链路本地（169.254.x.x APIPA）与回环，优先私网段
func _collect_addresses() -> Dictionary:
	var out := {}
	var best4 := ""
	var best4_score := -1
	var ipv6_first := ""
	for raw in IP.get_local_addresses():
		var ip := str(raw).to_lower()
		if ip == "127.0.0.1" or ip == "::1" or ip.begins_with("fe80:"):
			continue
		if ip.contains(":"):
			if ipv6_first.is_empty() and _is_global_ipv6(ip):
				ipv6_first = ip
		else:
			var s := _ipv4_score(ip)
			if s > best4_score:
				best4_score = s
				best4 = ip
	if best4_score >= 0:
		out["ipv4"] = best4
	if not ipv6_first.is_empty():
		out["ipv6"] = ipv6_first
	return out

## IPv4 可用性评分：链路本地/回环 -1（丢弃），私网段 3（优先），其他 1
func _ipv4_score(ip: String) -> int:
	var parts := ip.split(".")
	if parts.size() != 4:
		return -1
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	if a == 127 or a == 0:
		return -1
	if a == 169 and b == 254:
		return -1  # APIPA 链路本地，不可达
	if a == 10:
		return 3
	if a == 192 and b == 168:
		return 3
	if a == 172 and b >= 16 and b <= 31:
		return 3
	return 1

## 全局单播（2000::/3）或 ULA（fc00::/7）
func _is_global_ipv6(ip: String) -> bool:
	return ip.begins_with("2") or ip.begins_with("3") \
		or ip.begins_with("fd") or ip.begins_with("fc")

## client 通过房间码加入（自动解码 IP:端口）。返回 Error
func join_by_code(code: String, p_password: String = "") -> Error:
	var info := RoomCode.decode(code)
	if info.is_empty():
		return ERR_INVALID_PARAMETER
	return join_game(str(info["ip"]), int(info["port"]), p_password)

## client 加入（IP:端口）。返回 Error
func join_game(ip: String, port: int = DEFAULT_PORT, p_password: String = "") -> Error:
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(ip, port)
	if err != OK:
		_enet = null
		return err
	multiplayer.multiplayer_peer = _enet
	is_online = true
	password = p_password
	return OK

func leave_game() -> void:
	_remote_inputs.clear()
	_lobby_entered = false
	is_host = false
	is_online = false
	my_peer_id = 0
	ipv4_code = ""
	ipv6_code = ""
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_enet = null
	_init_seats()

# ---------------------------------------------------------------- 席位所有权

func get_seat_owner(seat: int) -> Dictionary:
	if seat < 0 or seat >= MAX_SEATS:
		return {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1}
	return seat_owners[seat]

func get_occupied_seat_count() -> int:
	var n := 0
	for o in seat_owners:
		if o["kind"] != SeatKind.EMPTY:
			n += 1
	return n

## 本端控制的席位（host：本地席位；client：peer_id == 我的远端席位）
func get_my_seats() -> Array[int]:
	var seats: Array[int] = []
	for i in MAX_SEATS:
		var o: Dictionary = seat_owners[i]
		if is_host:
			if o["kind"] == SeatKind.LOCAL:
				seats.append(i)
		else:
			if o["kind"] == SeatKind.REMOTE and o["peer_id"] == my_peer_id:
				seats.append(i)
	return seats

## host 本地设备占席位
func claim_local_seat(seat: int, device: int) -> void:
	if not is_host:
		return
	seat_owners[seat] = {"kind": SeatKind.LOCAL, "device": device, "peer_id": -1, "ready": false}
	_sync_seat_owners()

func free_seat(seat: int) -> void:
	seat_owners[seat] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false}
	_sync_seat_owners()

func free_peer_seats(peer_id: int) -> void:
	for i in MAX_SEATS:
		if seat_owners[i]["peer_id"] == peer_id:
			seat_owners[i] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false}
	_sync_seat_owners()

## client → host：申请加入一个空席位（带本端设备号 + 期望槽位；preferred 空则用，否则第一个空）
@rpc("any_peer", "reliable")
func _join_request(device: int, preferred: int = -1) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	_log_net("host", "_join_request peer=%d dev=%d pref=%d" % [peer, device, preferred])
	if preferred >= 0 and preferred < MAX_SEATS \
			and seat_owners[preferred]["kind"] == SeatKind.EMPTY:
		seat_owners[preferred] = {"kind": SeatKind.REMOTE, "device": device, "peer_id": peer, "ready": false}
		_sync_seat_owners()
		_join_ok.rpc_id(peer, preferred)
		return
	for i in MAX_SEATS:
		if seat_owners[i]["kind"] == SeatKind.EMPTY:
			seat_owners[i] = {"kind": SeatKind.REMOTE, "device": device, "peer_id": peer, "ready": false}
			_sync_seat_owners()
			_join_ok.rpc_id(peer, i)
			return
	# 无空位：回拒绝，让 client 清除在途申请
	_join_full.rpc_id(peer)

## host → client：加入成功，返回分配的席位（席位表已由 _apply_seat_owners 先同步到位）
@rpc("authority", "reliable")
func _join_ok(seat: int) -> void:
	seat_owners_changed.emit()

## host → client：房间已满，加入被拒绝
@rpc("authority", "reliable")
func _join_full() -> void:
	join_rejected.emit()

## client → host：退出自己的席位
@rpc("any_peer", "reliable")
func _leave_request(seat: int) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	var o := get_seat_owner(seat)
	if o["kind"] == SeatKind.REMOTE and o["peer_id"] == peer:
		seat_owners[seat] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false}
		_sync_seat_owners()

## client 端：本地维护「我申请过的席位 + 设备」一致表（显示/战斗用）
func join_seat(device: int, preferred_seat: int = -1) -> void:
	if is_host or not is_online:
		return
	_join_request.rpc_id(1, device, preferred_seat)

func leave_my_seat(seat: int) -> void:
	if is_host or not is_online:
		return
	_leave_request.rpc_id(1, seat)

## 设置席位就绪状态（host 本地席位直接改+同步；client 请求 host）
func set_seat_ready(seat: int, ready: bool) -> void:
	if is_host:
		var o := get_seat_owner(seat)
		if o["kind"] == SeatKind.EMPTY:
			return
		o["ready"] = ready
		_sync_seat_owners()
	else:
		_set_ready_request.rpc_id(1, seat, ready)

## 返回大厅时重置所有已占用席位的就绪态（host 权威），避免联机重进秒开
func enter_lobby_reset_ready() -> void:
	if not is_host or not is_online:
		return
	var changed := false
	for i in MAX_SEATS:
		var o: Dictionary = seat_owners[i]
		if o["kind"] != SeatKind.EMPTY and o["ready"]:
			o["ready"] = false
			changed = true
	if changed:
		_sync_seat_owners()

@rpc("any_peer", "reliable")
func _set_ready_request(seat: int, ready: bool) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var o := get_seat_owner(seat)
	if o["kind"] != SeatKind.REMOTE or o["peer_id"] != sender:
		return
	o["ready"] = ready
	_sync_seat_owners()

## 席位表同步给所有端（host 权威）
func _sync_seat_owners() -> void:
	if is_host and is_online:
		rpc("_apply_seat_owners", seat_owners)
	seat_owners_changed.emit()

@rpc("authority", "reliable")
func _apply_seat_owners(owners: Array) -> void:
	seat_owners = owners
	if not is_host:
		_auto_bind_my_seats()
	seat_owners_changed.emit()

## client：本端席位默认绑定本地设备（首个席位键盘，其余手柄 0/1/...）
## 大厅 UI 接线后由玩家显式选择设备覆盖此默认
func _auto_bind_my_seats() -> void:
	var my_seats := get_my_seats()
	for i in my_seats.size():
		var seat: int = my_seats[i]
		if GameManager.player_devices[seat] == -2:
			GameManager.player_devices[seat] = -1 if i == 0 else i - 1

# ---------------------------------------------------------------- 连接 / 鉴权

func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if is_host:
		free_peer_seats(peer_id)
		peer_left.emit(peer_id)

func _on_connected_to_server() -> void:
	my_peer_id = multiplayer.get_unique_id()
	_log_net("client", "ENet 连接成功, my_peer_id=%d" % my_peer_id)
	# 连接建立后上报密码，host 校验通过后分配席位
	_submit_password.rpc_id(1, password)
	# 直接进入大厅：ENet 已建立即认为可入局（密码由 host 校验，错会被断开）。
	# 不等待 host 的 _accept_join 回包，避免握手确认丢失导致一直「连接中」。
	if not _lobby_entered:
		_lobby_entered = true
		connected_to_server.emit()

func _on_server_disconnected() -> void:
	if not is_online and _enet == null:
		return  # 主动离开触发，不重复处理
	leave_game()
	server_stopped.emit()
	GameManager.enter_title()

func _on_connection_failed() -> void:
	is_online = false
	connection_failed.emit("connection_failed")

## client → host：密码鉴权
@rpc("any_peer", "reliable")
func _submit_password(pw: String) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	_log_net("host", "收到鉴权来自 peer %d" % peer)
	if password != "" and pw != password:
		_log_net("host", "密码不符，断开 peer %d" % peer)
		multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	_accept_join.rpc_id(peer, room_name)

## host → client：鉴权通过、带回房间名（client 已在 ENet 连接成功时进大厅，此处只补房间名）
@rpc("authority", "reliable")
func _accept_join(room: String) -> void:
	room_name = room
	_log_net("client", "收到 _accept_join, room=" + room)
	if not _lobby_entered:
		_lobby_entered = true
		connected_to_server.emit()
	# 房间名晚到：触发刷新，让大厅显示正确房名
	seat_owners_changed.emit()

# ---------------------------------------------------------------- 输入上行

## client → host：输入 level 上行（60Hz，unreliable_ordered，只发 level 不发边缘）
@rpc("any_peer", "unreliable_ordered")
func submit_input(seat: int, move: Vector2, buttons: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var o := get_seat_owner(seat)
	if o["kind"] != SeatKind.REMOTE or o["peer_id"] != sender:
		return
	var provider = _remote_inputs.get(seat)
	if provider:
		provider.apply_input(move, buttons)

## client 端：采集本地席位输入并上行（每物理帧由外部调用）
func send_local_input(seat: int) -> void:
	if is_host or not is_online:
		return
	var local := PlayerInput.new(seat)
	var level: Dictionary = local.get_input_level()
	submit_input.rpc_id(1, seat, level["move"], level["buttons"])

## host 端：注册远端席位的输入源（由 PlayerController 创建时调用）
func register_remote_input(seat: int, provider) -> void:
	_remote_inputs[seat] = provider

func unregister_remote_input(seat: int) -> void:
	_remote_inputs.erase(seat)

# ---------------------------------------------------------------- 状态快照广播

## host：采集全部真实玩家的状态，广播给所有 client
func _broadcast_state_snapshot() -> void:
	var snapshots: Array = []
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as PlayerController
		if p and not p.is_puppet:
			snapshots.append({
				"i": p.player_index,
				"p": [p.global_position.x, p.global_position.y, p.global_position.z],
				"v": [p.velocity.x, p.velocity.y, p.velocity.z],
				"s": p.state_machine.current_state_name if p.state_machine else "Idle",
				"y": p.rotation.y,
			})
	if not snapshots.is_empty():
		_apply_state_snapshot.rpc(snapshots)

## host → client：状态快照写入
@rpc("authority", "unreliable")
func _apply_state_snapshot(snapshots: Array) -> void:
	for s in snapshots:
		var idx: int = s["i"]
		var pos := Vector3(s["p"][0], s["p"][1], s["p"][2])
		var vel := Vector3(s["v"][0], s["v"][1], s["v"][2])
		var state: String = s["s"]
		var yaw: float = s["y"]
		var puppet := _find_puppet(idx)
		if puppet:
			puppet.apply_remote_state(pos, vel, state, yaw)

func _find_puppet(player_index: int) -> PlayerController:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as PlayerController
		if p and p.is_puppet and p.player_index == player_index:
			return p
	return null

# ---------------------------------------------------------------- 道具事件广播

## 全局实体 id 计数器（道具箱/服装共用，保证跨类型唯一）
var _next_entity_id: int = 0

func next_entity_id() -> int:
	_next_entity_id += 1
	return _next_entity_id

## host：道具生成广播（client 在相同位置生成同款）
func broadcast_item_spawn(item_id: String, pos: Vector3, spawn_id: int) -> void:
	_rpc_item_spawn.rpc(item_id, pos, spawn_id)

@rpc("authority", "reliable")
func _rpc_item_spawn(item_id: String, pos: Vector3, spawn_id: int) -> void:
	ItemSpawner.spawn_box_at(item_id, pos, spawn_id)

## host：服装生成广播
func broadcast_garment_spawn(garment_id: String, pos: Vector3, spawn_id: int) -> void:
	_rpc_garment_spawn.rpc(garment_id, pos, spawn_id)

@rpc("authority", "reliable")
func _rpc_garment_spawn(garment_id: String, pos: Vector3, spawn_id: int) -> void:
	GarmentSpawner.spawn_pickup_at(garment_id, pos, spawn_id)

## host：实体被拾取消失广播（道具箱/服装共用）
func broadcast_entity_despawn(spawn_id: int) -> void:
	_rpc_entity_despawn.rpc(spawn_id)

@rpc("authority", "reliable")
func _rpc_entity_despawn(spawn_id: int) -> void:
	for node in get_tree().get_nodes_in_group("item_boxes"):
		if node.get("spawn_id") == spawn_id:
			node.queue_free()
			return
	for node in get_tree().get_nodes_in_group("garment_pickups"):
		if node.get("spawn_id") == spawn_id:
			node.queue_free()
			return

## host：道具拾取广播（client 同步 HUD/图标）
func broadcast_item_picked_up(player_index: int, item_id: String) -> void:
	_rpc_item_picked_up.rpc(player_index, item_id)

@rpc("authority", "reliable")
func _rpc_item_picked_up(player_index: int, item_id: String) -> void:
	EventBus.item_picked_up.emit(player_index, item_id)

## host：道具使用广播（client 只播 VFX，不应用效果）
func broadcast_item_used(player_index: int, item_id: String) -> void:
	_rpc_item_used.rpc(player_index, item_id)

@rpc("authority", "reliable")
func _rpc_item_used(player_index: int, item_id: String) -> void:
	EventBus.item_used.emit(player_index, item_id)
	ItemSystem.play_use_vfx_only(item_id, player_index)

## host：服装穿戴广播（client 只挂外观，不应用效果）
func broadcast_outfit_changed(player_index: int, slot: int, garment_id: String) -> void:
	_rpc_outfit_changed.rpc(player_index, slot, garment_id)

@rpc("authority", "reliable")
func _rpc_outfit_changed(player_index: int, slot: int, garment_id: String) -> void:
	EventBus.outfit_changed.emit(player_index, slot, garment_id)
	var player := _find_puppet(player_index)
	if player:
		GarmentSystem.equip_garment_visual(player, garment_id)

## host：陷阱生成广播
func broadcast_trap_spawn(trap_id: String, pos: Vector3, spawn_id: int) -> void:
	_rpc_trap_spawn.rpc(trap_id, pos, spawn_id)

@rpc("authority", "reliable")
func _rpc_trap_spawn(trap_id: String, pos: Vector3, spawn_id: int) -> void:
	TrapInstance.spawn_visual(trap_id, pos, spawn_id)

## host：陷阱触发广播
func broadcast_trap_triggered(spawn_id: int, trap_id: String, player_index: int, pos: Vector3) -> void:
	_rpc_trap_triggered.rpc(spawn_id, trap_id, player_index, pos)

@rpc("authority", "reliable")
func _rpc_trap_triggered(spawn_id: int, trap_id: String, player_index: int, pos: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("traps"):
		if node.get("spawn_id") == spawn_id:
			node.queue_free()
			break
	EventBus.trap_triggered.emit(trap_id, player_index)
	TrapInstance.spawn_trigger_vfx_static(trap_id, pos)

## host：相机聚焦广播（client 主相机跟随对应 puppet）
func broadcast_camera_focus(player_index: int, duration: float) -> void:
	_rpc_camera_focus.rpc(player_index, duration)

@rpc("authority", "reliable")
func _rpc_camera_focus(player_index: int, duration: float) -> void:
	var player := _find_puppet(player_index)
	if player == null:
		return
	var controller := CameraSystem.get_main_controller()
	if controller == null:
		return
	var focus := PlayerFocusBehavior.new()
	focus.target_player = player
	controller.push_behavior(focus, duration)

## host：时间流速广播（快门慢放）
func broadcast_time_scale(scale: float) -> void:
	_rpc_time_scale.rpc(scale)

@rpc("authority", "unreliable")
func _rpc_time_scale(scale: float) -> void:
	Engine.time_scale = scale

## host：关卡相机分区索引广播（client 用同一分区）
func broadcast_zone_index(idx: int) -> void:
	_rpc_zone_index.rpc(idx)

## ---------------------------------------------------------------- 暂停同步

## 联机暂停（host 权威，广播给对端同步暂停/恢复）。
## 任一端都能发起：host 直接广播；client 向 host 请求，再由 host 统一广播回来。
func set_paused(paused: bool) -> void:
	if not is_online:
		return
	if is_host:
		_rpc_pause.rpc(paused)
		_rpc_pause(paused)   # host 本地也应用
	else:
		_toggle_pause_request.rpc_id(1, paused)

## 当前联机暂停状态（本地缓存，收到广播或主动设置时更新）
var _paused: bool = false

func is_paused_online() -> bool:
	return _paused

## client → host：暂停状态请求
@rpc("any_peer", "reliable")
func _toggle_pause_request(paused: bool) -> void:
	if not is_host:
		return
	_rpc_pause.rpc(paused)
	_paused = paused

## host → client：暂停状态广播
@rpc("authority", "reliable")
func _rpc_pause(paused: bool) -> void:
	_paused = paused
	EventBus.game_paused_changed.emit(paused)

## ---------------------------------------------------------------- 结算广播

## host：广播结算结果给 client。放在 autoload 上保证 client 即使还停在
## 加载/关卡未就绪状态也能收到（节点级 RPC 在目标节点不存在时会被丢弃）。
func broadcast_settlement(results: Dictionary) -> void:
	var payload := results.duplicate(true)
	# round 由 SettlementSystem 生成（与照片预览同号），client 端按此去重
	if not payload.has("round"):
		_round += 1
		payload["round"] = _round
	if payload.has("photo") and payload["photo"] is Image:
		var photo: Image = payload["photo"]
		if photo.get_width() > 1280:
			photo = _downscale_image(photo, 1280)
		payload["photo_png"] = photo.save_png_to_buffer()
		payload.erase("photo")
	if payload.has("mask") and payload["mask"] is Image:
		var mask: Image = payload["mask"]
		if mask.get_width() > 1280:
			mask = _downscale_image(mask, 1280)
		payload["mask_png"] = mask.save_png_to_buffer()
		payload.erase("mask")
	if is_host and is_online:
		_rpc_settlement.rpc(payload)

## host → client：结算结果送达（autoload 常驻，不限关卡节点）
@rpc("authority", "reliable")
func _rpc_settlement(payload: Dictionary) -> void:
	var round := int(payload.get("round", 0))
	if round <= _played_round:
		return  # 已展示过的局，跳过（防跨局/重复刷新）
	if payload.has("photo_png"):
		var photo := Image.new()
		photo.load_png_from_buffer(payload["photo_png"])
		payload["photo"] = photo
		payload.erase("photo_png")
	if payload.has("mask_png"):
		var mask := Image.new()
		mask.load_png_from_buffer(payload["mask_png"])
		payload["mask"] = mask
		payload.erase("mask_png")
	last_settlement = payload
	EventBus.settlement_received.emit(payload)

## client：最近的结算结果缓存（关卡未就绪时先到先存，就绪后 take 补收）。
var last_settlement: Dictionary = {}

## 结算局序号：host 递增；client 记录「已实际展示」的局用于去重
var _round: int = 0
var _played_round: int = 0

## host 生成一个结算局序号（照片预览与最终结果共用同一 round）
func next_settlement_round() -> int:
	_round += 1
	return _round

## host：拍照完成即广播照片预览（分数未出，仅让 client 早点看到照片）
func broadcast_settlement_preview(photo_img: Image, round: int) -> void:
	if not (is_host and is_online):
		return
	var img := photo_img
	if img and img.get_width() > 0:
		# 与最终结算一致降采样，避免全尺寸高分图 PNG 编码慢 + 大包阻塞 reliable 通道
		# （未压缩时可达 4096 宽、数 MB，会导致预览迟到、结算分数被卡住）
		if img.get_width() > 1280:
			img = _downscale_image(img, 1280)
		_rpc_settlement_preview.rpc(round, img.save_png_to_buffer())

## host → client：照片预览广播（分数未出，仅照片）
@rpc("authority", "reliable")
func _rpc_settlement_preview(round: int, photo_png: PackedByteArray) -> void:
	if photo_png.is_empty():
		return
	var photo := Image.new()
	var err := photo.load_png_from_buffer(photo_png)
	if err != OK:
		return
	last_preview_photo = photo
	last_preview_round = round
	EventBus.settlement_preview_received.emit(photo, round)

var last_preview_photo: Image = null
var last_preview_round: int = 0

## 关卡就绪后补收缓存的照片预览（若最终结果还没到，先展示照片）
func take_preview_photo() -> Dictionary:
	if last_preview_photo == null or last_preview_round <= _played_round:
		return {}
	return {"photo": last_preview_photo, "round": last_preview_round}

func take_settlement() -> Dictionary:
	var round := int(last_settlement.get("round", 0))
	if last_settlement.is_empty() or round <= _played_round:
		return {}
	return last_settlement.duplicate(true)

## 关卡展示完某一局结算后调用，推进已播局号并清缓存（防止跨局残留重播）
func mark_settlement_played(round: int) -> void:
	if round > _played_round:
		_played_round = round
	last_settlement = {}

## ---------------------------------------------------------------- 表情同步

## host：广播本轮各角色表情索引（client 应用于对应 puppet）
func broadcast_faces(faces: Array) -> void:
	if is_host and is_online:
		_rpc_faces.rpc(faces)

## host → client：表情索引广播（autoload 常驻，client 关卡未就绪也不丢，靠 take 补收）
@rpc("authority", "reliable")
func _rpc_faces(faces: Array) -> void:
	last_faces = faces
	EventBus.faces_received.emit(faces)

var last_faces: Array = []

## 关卡就绪后补收本轮表情
func take_faces() -> Array:
	var f := last_faces
	last_faces = []
	return f

## host：单个角色表情变化（动作触发，reliable 低频事件）
func broadcast_face_changed(player_index: int, face_index: int) -> void:
	if is_host and is_online:
		_rpc_face_changed.rpc(player_index, face_index)

## host → client：单个角色表情变化
@rpc("authority", "reliable")
func _rpc_face_changed(player_index: int, face_index: int) -> void:
	EventBus.face_changed.emit(player_index, face_index)

func _downscale_image(img: Image, max_width: int) -> Image:
	var scale := float(max_width) / float(img.get_width())
	var new_size := Vector2i(max_width, maxi(1, int(img.get_height() * scale)))
	img.resize(new_size.x, new_size.y, Image.INTERPOLATE_BILINEAR)
	return img

@rpc("authority", "reliable")
func _rpc_zone_index(idx: int) -> void:
	zone_index = idx
