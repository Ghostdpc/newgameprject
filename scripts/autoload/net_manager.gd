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

## 玩家状态名 → 快照内枚举 int（压缩传输：30Hz×多人不再每包传字符串）
const STATE_ENUM: Dictionary = {
	"Idle": 0, "Move": 1, "Jump": 2, "Dive": 3, "Fly": 4,
	"Stunned": 5, "BananaSlide": 6, "Death": 7,
	"RespawnWaiting": 8, "RespawnFall": 9,
}
const STATE_NAMES: Array = ["Idle", "Move", "Jump", "Dive", "Fly", "Stunned", "BananaSlide", "Death", "RespawnWaiting", "RespawnFall"]

## 结算大图分块大小（ENet reliable 单包舒适区，避免超大包 head-of-line 阻塞）
const SETTLEMENT_CHUNK_SIZE: int = 24576
## 结算/预览 RPC 走独立 transfer_channel，避免与 ordered 快照抢 channel 0
const CHUNK_CHANNEL: int = 1

## 断线重连宽限期（ms）：席位标记「掉线」保留，超时未重连才释放
const RECONNECT_GRACE_MS: int = 10000

## 握手/席位关键日志写文件（双开无控制台也能排查）
func _log_net(side: String, msg: String) -> void:
	var line := "[%s] [%s] %s\n" % [side, Time.get_time_string_from_system(), msg]
	print(line)
	# append 模式：seek_end 后追加，避免每条日志读回整文件再全量重写（O(n²)）。
	# READ_WRITE 不会创建不存在的文件，首次运行先 WRITE 建文件再 append。
	var f := FileAccess.open("user://net_debug.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://net_debug.log", FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string(line)
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

## 席位所有权 0-3：{"kind": SeatKind, "device": int, "peer_id": int, "ready": bool, "reconnecting": bool}
var seat_owners: Array = []

var _enet: ENetMultiplayerPeer
## seat -> RemoteInputProvider（host 侧远端席位输入源）
var _remote_inputs: Dictionary = {}
## 快照广播间隔（30Hz，墙钟驱动）
const SNAPSHOT_INTERVAL_MS: int = 33
var _last_snapshot_msec: int = 0
## 关卡相机分区索引（host 选择后广播，client 读取；-1 = 未定）
var zone_index: int = -1
## client：是否已通知 UI 进入大厅（防重复切场景）
var _lobby_entered: bool = false
## 游戏玩法时间流速（快门慢放）。不用 Engine.time_scale 全局慢放，避免 UI/全部节点受影响
var gameplay_time_scale: float = 1.0
## client：宿主快照时间戳 → 本端时间线的平滑偏移估计（网络抖动不进插值轴）
var _clock_offset: float = -1e18
## player_index -> PlayerController 注册表（避免 _find_* 每帧 group 全扫）
var _player_registry: Dictionary = {}
## host：断线席位宽限截止时刻 seat -> msec（超时未重连才释放）
var _reconnect_deadlines: Dictionary = {}

# ---------------------------------------------------------------- 断线重连
## client 最近一次连接信息（重连用）
var _last_ip: String = ""
var _last_port: int = DEFAULT_PORT
var _last_password: String = ""
var _intentional_leave: bool = false
## client：收到 host 主动关房广播（区别于意外断线，跳过重连）
var _host_closed: bool = false
var _reconnecting: bool = false
var _reconnect_attempts: int = 0
## client：加入连接看门狗起点（ms）。非 0 表示加入在途，超时未连上则报失败
var _connect_started_msec: int = 0
const CONNECT_TIMEOUT_MS: int = 5000
## 断线前的本端席位（重连后按此重新申请）
var _saved_my_seats: Array = []
## 断线前的本端 peer_id（重连恢复原座时向 host 证明身份）
var _saved_peer_id: int = -1
const RECONNECT_MAX_ATTEMPTS: int = 5
const RECONNECT_DELAY_MS: int = 1000

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
	# 加入连接看门狗：ENet create_client 已返回但连接未建立（不可达 IP 等）时，
	# 超时强制报失败，避免 UI 卡「正在连接...」无反馈（重连路径由 _on_connection_failed 接管，这里不重复触发）
	if not is_host and _connect_started_msec != 0:
		if Time.get_ticks_msec() - _connect_started_msec > CONNECT_TIMEOUT_MS:
			_connect_started_msec = 0
			_force_fail_connect()
			return
	# 注意：RemoteInputProvider 的边缘推进在 apply_input（RPC 到达）时完成。
	# 不能在 physics 每帧无条件 prev=cur —— RPC 在 idle 阶段更新 cur，physics 阶段的
	# 无条件推进会在状态机查询前把新 level 移入 prev，导致 cur==prev、边缘恒 false。
	# client：上行本端席位输入（仅已绑定设备的席位，60Hz）
	if is_online and not is_host:
		for seat in get_my_seats():
			if GameManager.player_devices[seat] != -2:
				send_local_input(seat)
	# host：状态快照广播（~30Hz，基于墙钟而非物理帧数，避免物理 FPS 变化改变快照率）
	if is_host:
		var now := Time.get_ticks_msec()
		if now - _last_snapshot_msec >= SNAPSHOT_INTERVAL_MS:
			_last_snapshot_msec = now
			_broadcast_state_snapshot()
		_check_reconnect_grace()

func _init_seats() -> void:
	seat_owners.clear()
	for i in MAX_SEATS:
		seat_owners.append({"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false, "reconnecting": false})

# ---------------------------------------------------------------- 创建 / 加入 / 离开

## host 开房（listen server）。生成中文房间码。返回 Error
## ENet 只能绑单一协议栈（Windows 下 "::" 默认仅 IPv6），由 prefer_ipv6 选栈：
##   false=局域网（优先 IPv4），true=跨网（优先 IPv6）。所选栈无地址时自动回退另一栈。
func host_game(p_room_name: String, p_password: String = "", port: int = DEFAULT_PORT, prefer_ipv6: bool = false) -> Error:
	ipv4_code = ""
	ipv6_code = ""
	_intentional_leave = false
	_reconnecting = false
	_reconnect_attempts = 0
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
	_intentional_leave = false
	_reconnecting = false
	_reconnect_attempts = 0
	_last_ip = ip
	_last_port = port
	_last_password = p_password
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(ip, port)
	if err != OK:
		_enet = null
		return err
	multiplayer.multiplayer_peer = _enet
	is_online = true
	password = p_password
	_connect_started_msec = Time.get_ticks_msec()  # 起连接看门狗（reconnect 也走此，由 _try_reconnect 保留重置）
	return OK

func leave_game() -> void:
	_intentional_leave = true
	_host_closed = false
	_reconnecting = false
	_reconnect_attempts = 0
	_connect_started_msec = 0
	_remote_inputs.clear()
	_lobby_entered = false
	# host 主动关房：先广播关房信号（reliable），flush 确保送出后再 close
	# （必须在 is_host/is_online 复位前广播，否则客户端当成意外掉线走进重连）
	if is_host and is_online:
		rpc("_host_closed_notice")
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.flush()
	is_host = false
	is_online = false
	my_peer_id = 0
	ipv4_code = ""
	ipv6_code = ""
	gameplay_time_scale = 1.0
	_clock_offset = -1e18
	_clear_local_input_state()
	_reconnect_deadlines.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_enet = null
	_init_seats()

## 清空本端输入上行状态（序号/历史），换座/离房后不残留旧去重基准
func _clear_local_input_state() -> void:
	_next_input_seq.clear()
	_input_history.clear()

# ---------------------------------------------------------------- 席位所有权

func get_seat_owner(seat: int) -> Dictionary:
	if seat < 0 or seat >= MAX_SEATS:
		return {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false, "reconnecting": false}
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
	seat_owners[seat] = {"kind": SeatKind.LOCAL, "device": device, "peer_id": -1, "ready": false, "reconnecting": false}
	_sync_seat_owners()

func free_seat(seat: int) -> void:
	seat_owners[seat] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false, "reconnecting": false}
	_reconnect_deadlines.erase(seat)
	_sync_seat_owners()

func free_peer_seats(peer_id: int) -> void:
	for i in MAX_SEATS:
		if seat_owners[i]["peer_id"] == peer_id:
			seat_owners[i] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false, "reconnecting": false}
			_reconnect_deadlines.erase(i)
	_sync_seat_owners()

## host：某 peer 掉线，席位标记「重连中」+ 宽限期，超时才释放（而非立即 free 导致重连后不 respawn）
func _mark_peer_seats_reconnecting(peer_id: int) -> void:
	var now := Time.get_ticks_msec()
	for i in MAX_SEATS:
		var o: Dictionary = seat_owners[i]
		if o["kind"] == SeatKind.REMOTE and o["peer_id"] == peer_id:
			o["reconnecting"] = true
			_reconnect_deadlines[i] = now + RECONNECT_GRACE_MS
			var prov = _remote_inputs.get(i)
			if prov:
				prov.reset()  # 清残留输入，避免掉线期间幽灵持续移动
	_sync_seat_owners()

## host：宽限期到期仍未重连 → 释放席位
func _check_reconnect_grace() -> void:
	if _reconnect_deadlines.is_empty():
		return
	var now := Time.get_ticks_msec()
	var expired: Array = []
	for seat in _reconnect_deadlines:
		if now >= int(_reconnect_deadlines[seat]):
			expired.append(seat)
	for seat in expired:
		_reconnect_deadlines.erase(seat)
		var o: Dictionary = seat_owners[seat]
		if o["kind"] == SeatKind.REMOTE and o.get("reconnecting", false):
			seat_owners[seat] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false, "reconnecting": false}
			_sync_seat_owners()

## client → host：申请加入一个空席位（带本端设备号 + 期望槽位 + 旧 peer_id 证明身份）。
## 优先恢复「掉线中」的旧座（重连恢复原座），其次 preferred 空位，最后第一个空位。
@rpc("any_peer", "reliable")
func _join_request(device: int, preferred: int = -1, old_peer: int = -1) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	_log_net("host", "_join_request peer=%d dev=%d pref=%d old=%d" % [peer, device, preferred, old_peer])
	# 同一 peer 已占座（非重连中）→ 直接回已占座，防快速点击重复分配席位
	for i in MAX_SEATS:
		var own: Dictionary = seat_owners[i]
		if own["kind"] == SeatKind.REMOTE and own["peer_id"] == peer and not own.get("reconnecting", false):
			_join_ok.rpc_id(peer, i)
			return
	# 重连恢复原座：preferred 席位正被旧 peer 标记「掉线」，且身份匹配
	if preferred >= 0 and preferred < MAX_SEATS:
		var po: Dictionary = seat_owners[preferred]
		if po["kind"] == SeatKind.REMOTE and po.get("reconnecting", false) and po["peer_id"] == old_peer:
			seat_owners[preferred] = {"kind": SeatKind.REMOTE, "device": device, "peer_id": peer, "ready": false, "reconnecting": false}
			_reconnect_deadlines.erase(preferred)
			_sync_seat_owners()
			_join_ok.rpc_id(peer, preferred)
			return
		if po["kind"] == SeatKind.EMPTY:
			seat_owners[preferred] = {"kind": SeatKind.REMOTE, "device": device, "peer_id": peer, "ready": false, "reconnecting": false}
			_sync_seat_owners()
			_join_ok.rpc_id(peer, preferred)
			return
	for i in MAX_SEATS:
		if seat_owners[i]["kind"] == SeatKind.EMPTY:
			seat_owners[i] = {"kind": SeatKind.REMOTE, "device": device, "peer_id": peer, "ready": false, "reconnecting": false}
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
		seat_owners[seat] = {"kind": SeatKind.EMPTY, "device": -2, "peer_id": -1, "ready": false, "reconnecting": false}
		_reconnect_deadlines.erase(seat)
		_sync_seat_owners()

## client 端：本地维护「我申请过的席位 + 设备」一致表（显示/战斗用）
func join_seat(device: int, preferred_seat: int = -1, old_peer: int = -1) -> void:
	if is_host or not is_online:
		return
	_join_request.rpc_id(1, device, preferred_seat, old_peer)

func leave_my_seat(seat: int) -> void:
	if is_host or not is_online:
		return
	_leave_request.rpc_id(1, seat)
	_clear_local_input_state()

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
		_mark_peer_seats_reconnecting(peer_id)
		peer_left.emit(peer_id)

func _on_connected_to_server() -> void:
	my_peer_id = multiplayer.get_unique_id()
	_connect_started_msec = 0  # 连接建立，清看门狗
	_log_net("client", "ENet 连接成功, my_peer_id=%d reconnecting=%s" % [my_peer_id, str(_reconnecting)])
	# 连接建立后上报密码，host 校验通过后分配席位
	_submit_password.rpc_id(1, password)
	if _reconnecting:
		_reconnecting = false
		_reconnect_attempts = 0
		# 重连成功：重新申请断线前的席位（带旧 peer_id 恢复原座，host 收到 join_request 恢复并同步席位表）
		for seat in _saved_my_seats:
			var dev := -2
			if GameManager.player_devices.size() > int(seat):
				dev = int(GameManager.player_devices[int(seat)])
			join_seat(dev, int(seat), _saved_peer_id)
		return
	# 直接进入大厅：ENet 已建立即认为可入局（密码由 host 校验，错会被断开）。
	# 不等待 host 的 _accept_join 回包，避免握手确认丢失导致一直「连接中」。
	if not _lobby_entered:
		_lobby_entered = true
		connected_to_server.emit()

func _on_server_disconnected() -> void:
	if _intentional_leave:
		return  # 主动离开：leave_game 已清理，UI 自行处理
	if _host_closed:
		# host 主动关房：非意外断线，跳过重连直接回标题
		_host_closed = false
		leave_game()
		server_stopped.emit()
		GameManager.enter_title()
		return
	if not is_online and _enet == null:
		return  # 已清理，不重复处理
	# 意外断线：缓存席位与 peer_id 并尝试重连（peer_id 用于恢复原座）
	_saved_my_seats = get_my_seats().duplicate()
	_saved_peer_id = my_peer_id
	_clear_local_input_state()
	is_online = false
	multiplayer.multiplayer_peer = null
	_enet = null
	_log_net("client", "意外断线，开始重连（ip=%s:%d seats=%s old_peer=%d）" % [_last_ip, _last_port, str(_saved_my_seats), _saved_peer_id])
	_start_reconnect()

func _on_connection_failed() -> void:
	is_online = false
	_connect_started_msec = 0
	if _reconnecting:
		_schedule_reconnect_retry()
		return
	connection_failed.emit("connection_failed")

## 加入连接超时强制失败：清理 ENet，非重连时按失败处理（重连路径由 _on_connection_failed 接管）
func _force_fail_connect() -> void:
	is_online = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_enet = null
	if _reconnecting:
		_schedule_reconnect_retry()
		return
	connection_failed.emit("timeout")

## host → client：host 主动关房。client 标记 _host_closed，socket 断开时跳过重连
@rpc("authority", "reliable")
func _host_closed_notice() -> void:
	_log_net("client", "收到 host 主动关房广播")
	_host_closed = true

# ---------------------------------------------------------------- 断线重连

func _start_reconnect() -> void:
	if _reconnecting:
		return
	if _last_ip.is_empty():
		_abort_reconnect()
		return
	_reconnecting = true
	_reconnect_attempts = 0
	_try_reconnect()

func _try_reconnect() -> void:
	_reconnect_attempts += 1
	if _reconnect_attempts > RECONNECT_MAX_ATTEMPTS:
		_abort_reconnect()
		return
	_log_net("client", "重连尝试 %d/%d -> %s:%d" % [_reconnect_attempts, RECONNECT_MAX_ATTEMPTS, _last_ip, _last_port])
	_enet = ENetMultiplayerPeer.new()
	var err := _enet.create_client(_last_ip, _last_port)
	if err != OK:
		_enet = null
		_schedule_reconnect_retry()
		return
	multiplayer.multiplayer_peer = _enet
	is_online = true
	_connect_started_msec = Time.get_ticks_msec()  # 重连也走看门狗
	# 连接成功：_on_connected_to_server 重发密码并重新申请席位

func _schedule_reconnect_retry() -> void:
	await get_tree().create_timer(RECONNECT_DELAY_MS / 1000.0).timeout
	if _reconnecting:
		_try_reconnect()

func _abort_reconnect() -> void:
	_reconnecting = false
	_reconnect_attempts = 0
	leave_game()
	server_stopped.emit()
	GameManager.enter_title()

## client → host：密码鉴权
@rpc("any_peer", "reliable")
func _submit_password(pw: String) -> void:
	if not is_host:
		return
	var peer := multiplayer.get_remote_sender_id()
	_log_net("host", "收到鉴权来自 peer %d" % peer)
	if password != "" and pw != password:
		_log_net("host", "密码不符，断开 peer %d" % peer)
		_rpc_auth_reject.rpc_id(peer)
		multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	_accept_join.rpc_id(peer, room_name)
	# 新加入 peer 先同步当前席位表（否则其本地 seat_owners 保持全空，大厅看不到已占用席位）
	_apply_seat_owners.rpc_id(peer, seat_owners)
	# 迟到加入/重连追赶：把当前阶段、关卡路径、人数、分区同步给该 peer
	GameManager._rpc_catchup.rpc_id(peer, GameManager.current_stage, GameManager.pending_level_path, GameManager.lobby_player_count, zone_index)

## host → client：鉴权拒绝（密码错误），client 标记主动离开避免触发重连
@rpc("authority", "reliable")
func _rpc_auth_reject() -> void:
	_intentional_leave = true
	join_rejected.emit()
	leave_game()
	server_stopped.emit()

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

## client → host：输入 level + 本帧按下沿上行（60Hz，unreliable_ordered）。
## seq：本端单调递增序号，host 回执进快照 ack，供 client 输入重放（reconciliation）。
@rpc("any_peer", "unreliable_ordered")
func submit_input(seat: int, seq: int, move: Vector2, buttons: int, edge: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var o := get_seat_owner(seat)
	if o["kind"] != SeatKind.REMOTE or o["peer_id"] != sender:
		return
	var provider = _remote_inputs.get(seat)
	if provider:
		provider.apply_input(move, buttons, edge, seq)

## client 侧：每个席位下一帧输入序号（上行自增）
var _next_input_seq: Dictionary = {}
## client 侧：输入历史（seat -> Array[{seq, move, buttons, edge}]），校正回放用
var _input_history: Dictionary = {}
const INPUT_HISTORY_MAX: int = 90  # ~1.5s @ 60Hz

## client 侧：采集本地席位输入并上行。每物理帧都发（含序号），保证回放时可重演无变化帧。
func send_local_input(seat: int) -> void:
	if is_host or not is_online:
		return
	var local := PlayerInput.new(seat)
	var level: Dictionary = local.get_input_level()
	var move: Vector2 = level["move"]
	var buttons: int = level["buttons"]
	var edge: int = local.get_input_edge()
	var seq: int = int(_next_input_seq.get(seat, 0))
	_next_input_seq[seat] = seq + 1
	var hist: Array = _input_history.get(seat, [])
	_input_history[seat] = hist
	hist.append({"seq": seq, "move": move, "buttons": buttons, "edge": edge})
	while hist.size() > INPUT_HISTORY_MAX:
		hist.pop_front()
	submit_input.rpc_id(1, seat, seq, move, buttons, edge)

## client：丢弃 ack 之前的输入历史（宿主已确认，无需再回放）
func drop_acked_inputs(seat: int, ack_seq: int) -> void:
	if ack_seq < 0:
		return
	var hist: Array = _input_history.get(seat, [])
	if hist.is_empty():
		return
	while not hist.is_empty() and int(hist[0]["seq"]) <= ack_seq:
		hist.pop_front()

## client：取出待回放的输入（副本，宿主尚未确认的部分）
func take_pending_inputs(seat: int) -> Array:
	var hist: Array = _input_history.get(seat, [])
	var out: Array = []
	for e in hist:
		out.append(e)
	return out

## host 端：注册远端席位的输入源（由 PlayerController 创建时调用）
func register_remote_input(seat: int, provider) -> void:
	_remote_inputs[seat] = provider

func unregister_remote_input(seat: int) -> void:
	_remote_inputs.erase(seat)

# ---------------------------------------------------------------- 状态快照广播

## host：采集全部真实玩家的状态，广播给所有 client。
## 位置/速度量化到 0.01（cm 级/0.01 单位），yaw 量化到 0.01rad，状态用 enum int，带宿主时间戳 + 输入 ack。
func _broadcast_state_snapshot() -> void:
	var snapshots: Array = []
	var now := Time.get_ticks_msec()
	for node in _player_registry.values():
		var p := node as PlayerController
		if p and not p.is_puppet:
			var ack: int = -1
			if p.player_input is RemoteInputProvider:
				ack = (p.player_input as RemoteInputProvider).last_seq
			snapshots.append({
				"i": p.player_index,
				"t": now,
				"px": int(round(p.global_position.x * 100.0)),
				"py": int(round(p.global_position.y * 100.0)),
				"pz": int(round(p.global_position.z * 100.0)),
				"vx": int(round(p.velocity.x * 100.0)),
				"vy": int(round(p.velocity.y * 100.0)),
				"vz": int(round(p.velocity.z * 100.0)),
				"si": STATE_ENUM.get(p.state_machine.current_state_name if p.state_machine else "Idle", 0),
				"yaw": int(round(p.rotation.y * 100.0)),
				"ack": ack,
			})
	if not snapshots.is_empty():
		_apply_state_snapshot.rpc(snapshots)

func _state_name(i: int) -> String:
	if i < 0 or i >= STATE_NAMES.size():
		return "Idle"
	return STATE_NAMES[i]

## host → client：状态快照写入（ordered：防旧快照覆盖新快照导致位置回退）。
## 插值时间轴用宿主时间戳（换算到本端时间线），而非本端到达时刻，网络抖动不进插值。
@rpc("authority", "unreliable_ordered")
func _apply_state_snapshot(snapshots: Array) -> void:
	var arrival := Time.get_ticks_msec()
	for s in snapshots:
		var idx: int = s["i"]
		var host_t: int = s.get("t", arrival)
		var est_offset := arrival - host_t
		_clock_offset = est_offset if _clock_offset < -1e17 else lerpf(_clock_offset, float(est_offset), 0.1)
		var t_local: int = host_t + int(round(_clock_offset))
		var pos := Vector3(float(s["px"]) / 100.0, float(s["py"]) / 100.0, float(s["pz"]) / 100.0)
		var vel := Vector3(float(s["vx"]) / 100.0, float(s["vy"]) / 100.0, float(s["vz"]) / 100.0)
		var state: String = _state_name(int(s.get("si", 0)))
		var yaw: float = float(s.get("yaw", 0)) / 100.0
		var ack: int = int(s.get("ack", -1))
		# 本端预测角色：本地模拟 + 宿主校正（事件仍宿主权威）
		if not is_host and _is_my_seat(idx):
			var predicted := _find_predicted(idx)
			if predicted:
				predicted.apply_prediction_correction(pos, vel, state, yaw, t_local, ack)
				continue
		var puppet := _find_puppet(idx)
		if puppet:
			puppet.apply_remote_state(pos, vel, state, yaw, t_local)

func _is_my_seat(seat: int) -> bool:
	return get_my_seats().has(seat)

## player_index -> PlayerController 注册表：玩家节点入/出场景时注册/注销，_find_* 直接 O(1) 查表
func register_player(p: PlayerController) -> void:
	_player_registry[p.player_index] = p

func unregister_player(p: PlayerController) -> void:
	if _player_registry.get(p.player_index) == p:
		_player_registry.erase(p.player_index)

func _find_predicted(player_index: int) -> PlayerController:
	var p := _player_registry.get(player_index) as PlayerController
	if p and p.is_predicted:
		return p
	return null

func _find_puppet(player_index: int) -> PlayerController:
	var p := _player_registry.get(player_index) as PlayerController
	if p and p.is_puppet:
		return p
	return null

## 任意真实玩家（puppet / predicted / host 本地），用于服装外观等表现同步
func _find_player(player_index: int) -> PlayerController:
	return _player_registry.get(player_index) as PlayerController

# ---------------------------------------------------------------- 道具事件广播

## 全局实体 id 计数器（道具箱/服装/陷阱共用，保证跨类型唯一）
var _next_entity_id: int = 0

## host：在场实体注册表 spawn_id -> {"type": "item"|"garment"|"trap", "id": String, "pos": Vector3}
## client 关卡就绪后按此补收加载期间漏掉的 spawn 广播（全量对账）
var _entity_registry: Dictionary = {}

func next_entity_id() -> int:
	_next_entity_id += 1
	return _next_entity_id

## 在场实体去重：按 spawn_id 查三组
func _has_entity(spawn_id: int) -> bool:
	for node in get_tree().get_nodes_in_group("item_boxes"):
		if node.get("spawn_id") == spawn_id:
			return true
	for node in get_tree().get_nodes_in_group("garment_pickups"):
		if node.get("spawn_id") == spawn_id:
			return true
	for node in get_tree().get_nodes_in_group("traps"):
		if node.get("spawn_id") == spawn_id:
			return true
	return false

## client：关卡就绪后向 host 请求全量实体状态（host 权威，reliable）
func request_entity_state() -> void:
	if is_online and not is_host:
		_request_entity_state.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_entity_state() -> void:
	if not is_host:
		return
	var list: Array = []
	for sid in _entity_registry:
		var e: Dictionary = _entity_registry[sid]
		list.append({"sid": sid, "type": e["type"], "id": e["id"], "pos": e["pos"]})
	_rpc_entity_state.rpc_id(multiplayer.get_remote_sender_id(), list)

## host → client：全量实体状态（补收用；按 spawn_id 去重防双生成）
@rpc("authority", "reliable")
func _rpc_entity_state(list: Array) -> void:
	for e in list:
		var sid: int = e["sid"]
		if _has_entity(sid):
			continue
		var pos: Vector3 = e["pos"]
		var etype: String = e["type"]
		match etype:
			"item":
				ItemSpawner.spawn_box_at(e["id"], pos, sid)
			"garment":
				GarmentSpawner.spawn_pickup_at(e["id"], pos, sid)
			"trap":
				TrapInstance.spawn_visual(e["id"], pos, sid)

## host：道具生成广播（client 在相同位置生成同款）
func broadcast_item_spawn(item_id: String, pos: Vector3, spawn_id: int) -> void:
	_entity_registry[spawn_id] = {"type": "item", "id": item_id, "pos": pos}
	_rpc_item_spawn.rpc(item_id, pos, spawn_id)

@rpc("authority", "reliable")
func _rpc_item_spawn(item_id: String, pos: Vector3, spawn_id: int) -> void:
	if _has_entity(spawn_id):
		return
	ItemSpawner.spawn_box_at(item_id, pos, spawn_id)

## host：服装生成广播
func broadcast_garment_spawn(garment_id: String, pos: Vector3, spawn_id: int) -> void:
	_entity_registry[spawn_id] = {"type": "garment", "id": garment_id, "pos": pos}
	_rpc_garment_spawn.rpc(garment_id, pos, spawn_id)

@rpc("authority", "reliable")
func _rpc_garment_spawn(garment_id: String, pos: Vector3, spawn_id: int) -> void:
	if _has_entity(spawn_id):
		return
	GarmentSpawner.spawn_pickup_at(garment_id, pos, spawn_id)

## host：实体被拾取消失广播（道具箱/服装共用）
func broadcast_entity_despawn(spawn_id: int) -> void:
	_entity_registry.erase(spawn_id)
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

## host：服装穿戴广播（client 同步外观与全部效果）
func broadcast_outfit_changed(player_index: int, slot: int, garment_id: String) -> void:
	_rpc_outfit_changed.rpc(player_index, slot, garment_id)

@rpc("authority", "reliable")
func _rpc_outfit_changed(player_index: int, slot: int, garment_id: String) -> void:
	EventBus.outfit_changed.emit(player_index, slot, garment_id)
	var player := _find_player(player_index)
	if player:
		GarmentSystem.equip_garment_visual(player, garment_id)

## host：陷阱生成广播
func broadcast_trap_spawn(trap_id: String, pos: Vector3, spawn_id: int) -> void:
	_entity_registry[spawn_id] = {"type": "trap", "id": trap_id, "pos": pos}
	_rpc_trap_spawn.rpc(trap_id, pos, spawn_id)

@rpc("authority", "reliable")
func _rpc_trap_spawn(trap_id: String, pos: Vector3, spawn_id: int) -> void:
	if _has_entity(spawn_id):
		return
	TrapInstance.spawn_visual(trap_id, pos, spawn_id)

## host：陷阱触发广播
func broadcast_trap_triggered(spawn_id: int, trap_id: String, player_index: int, pos: Vector3) -> void:
	_entity_registry.erase(spawn_id)
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
	var player := _find_player(player_index)
	if player == null:
		return
	var controller := CameraSystem.get_main_controller()
	if controller == null:
		return
	var focus := PlayerFocusBehavior.new()
	focus.target_player = player
	controller.push_behavior(focus, duration)

## 统一时间流速入口：本地立即生效 + host 广播（避免各调用点漏广播导致 client 永久错位）。
## 玩法慢放不走 Engine.time_scale（全局会拖慢 UI/全部节点），改存 gameplay_time_scale 由玩家控制器应用。
func set_time_scale(scale: float) -> void:
	gameplay_time_scale = scale
	if is_online and is_host:
		_rpc_time_scale.rpc(scale)

## host：时间流速广播（快门慢放；reliable：丢包则永久错位，低频率不值得 unreliable）
func broadcast_time_scale(scale: float) -> void:
	set_time_scale(scale)

@rpc("authority", "reliable")
func _rpc_time_scale(scale: float) -> void:
	gameplay_time_scale = scale

## host：关卡相机分区索引广播（client 用同一分区）
func broadcast_zone_index(idx: int) -> void:
	_rpc_zone_index.rpc(idx)

## ---------------------------------------------------------------- 飞扑命中事件

## host：飞扑命中广播（命中纯宿主物理，client 靠本事件同步 VFX/反馈时序，而非 state 名+位置推断）。
## target_is_prop=true 表示撞物（攻击者自己倒地），否则 target 是被击飞的玩家。
func broadcast_dive_hit(attacker: int, target: int, target_is_prop: bool, hit_pos: Vector3) -> void:
	if is_host and is_online:
		_rpc_dive_hit.rpc(attacker, target, target_is_prop, hit_pos)

@rpc("authority", "unreliable_ordered")
func _rpc_dive_hit(attacker: int, target: int, target_is_prop: bool, hit_pos: Vector3) -> void:
	if is_host:
		return
	if PropVfx:
		PropVfx.spawn_hit_shockwave(hit_pos, Color(1.0, 0.85, 0.30, 1.0))
	SoundMgr.play("hit")
	# 用 _find_player 而非 _find_puppet：受击者可能是本端 predicted 席位（非 puppet），也需即时反馈
	if target_is_prop:
		var a := _find_player(attacker)
		if a:
			a.apply_dive_hit_feedback(false)
	else:
		var t := _find_player(target)
		if t:
			t.apply_dive_hit_feedback(true)

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

## 把字节流切成固定大小块（结算大图分块传输，避免超大 reliable 包阻塞）
func _chunk_bytes(data: PackedByteArray) -> Array:
	var out: Array = []
	if data.is_empty():
		return out
	var n := ceili(float(data.size()) / float(SETTLEMENT_CHUNK_SIZE))
	for i in n:
		var from := i * SETTLEMENT_CHUNK_SIZE
		var to := mini(data.size(), from + SETTLEMENT_CHUNK_SIZE)
		out.append(data.slice(from, to))
	return out

func _join_chunks(parts: Dictionary, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	for i in count:
		var part: PackedByteArray = parts.get(i, PackedByteArray())
		out.append_array(part)
	return out

## host：广播结算结果给 client。放在 autoload 上保证 client 即使还停在
## 加载/关卡未就绪状态也能收到（节点级 RPC 在目标节点不存在时会被丢弃）。
## 大图（photo/mask）分块走独立 transfer_channel，与 ordered 快照互不阻塞。
func broadcast_settlement(results: Dictionary) -> void:
	var meta := results.duplicate(true)
	# round 由 SettlementSystem 生成（与照片预览同号），client 端按此去重
	if not meta.has("round"):
		_round += 1
		meta["round"] = _round
	var photo_bytes := PackedByteArray()
	var mask_bytes := PackedByteArray()
	if meta.has("photo") and meta["photo"] is Image:
		var photo: Image = meta["photo"]
		if photo.get_width() > 1280:
			photo = _downscale_image(photo, 1280)
		photo_bytes = photo.save_png_to_buffer()
		meta.erase("photo")
	if meta.has("mask") and meta["mask"] is Image:
		var mask: Image = meta["mask"]
		if mask.get_width() > 1280:
			mask = _downscale_image(mask, 1280)
		mask_bytes = mask.save_png_to_buffer()
		meta.erase("mask")
	if is_host and is_online:
		var photo_chunks := _chunk_bytes(photo_bytes)
		var mask_chunks := _chunk_bytes(mask_bytes)
		meta["photo_chunks"] = photo_chunks.size()
		meta["mask_chunks"] = mask_chunks.size()
		_rpc_settlement_meta.rpc(meta)
		for i in photo_chunks.size():
			_rpc_settlement_chunk.rpc(int(meta["round"]), 0, i, photo_chunks[i])
		for i in mask_chunks.size():
			_rpc_settlement_chunk.rpc(int(meta["round"]), 1, i, mask_chunks[i])

## client 分块重组缓存（meta 先到，chunk 后到，齐了组装）
var _settlement_meta: Dictionary = {}
var _settlement_photo_parts: Dictionary = {}
var _settlement_mask_parts: Dictionary = {}

## host → client：结算元数据（round + 分数等 + 大图分块数），走独立通道
@rpc("authority", "call_remote", "reliable", CHUNK_CHANNEL)
func _rpc_settlement_meta(meta: Dictionary) -> void:
	_settlement_meta = meta
	_settlement_photo_parts.clear()
	_settlement_mask_parts.clear()
	_try_assemble_settlement()

## host → client：结算大图分块（kind 0=photo / 1=mask），走独立通道
@rpc("authority", "call_remote", "reliable", CHUNK_CHANNEL)
func _rpc_settlement_chunk(round: int, kind: int, index: int, data: PackedByteArray) -> void:
	if round != int(_settlement_meta.get("round", -1)):
		return
	var parts := _settlement_photo_parts if kind == 0 else _settlement_mask_parts
	parts[index] = data
	_try_assemble_settlement()

func _try_assemble_settlement() -> void:
	if _settlement_meta.is_empty():
		return
	var round := int(_settlement_meta.get("round", 0))
	if round <= _played_round:
		_settlement_meta = {}
		_settlement_photo_parts.clear()
		_settlement_mask_parts.clear()
		return  # 已展示过的局，跳过（防跨局/重复刷新）
	var photo_chunks := int(_settlement_meta.get("photo_chunks", 0))
	var mask_chunks := int(_settlement_meta.get("mask_chunks", 0))
	if _settlement_photo_parts.size() < photo_chunks or _settlement_mask_parts.size() < mask_chunks:
		return
	var payload := _settlement_meta.duplicate(true)
	if photo_chunks > 0:
		var photo := Image.new()
		if photo.load_png_from_buffer(_join_chunks(_settlement_photo_parts, photo_chunks)) == OK:
			payload["photo"] = photo
	if mask_chunks > 0:
		var mask := Image.new()
		if mask.load_png_from_buffer(_join_chunks(_settlement_mask_parts, mask_chunks)) == OK:
			payload["mask"] = mask
	payload.erase("photo_chunks")
	payload.erase("mask_chunks")
	_settlement_meta = {}
	_settlement_photo_parts.clear()
	_settlement_mask_parts.clear()
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

## host：拍照完成即广播照片预览（分数未出，仅让 client 早点看到照片）。分块走独立通道。
func broadcast_settlement_preview(photo_img: Image, round: int) -> void:
	if not (is_host and is_online):
		return
	var img := photo_img
	if img and img.get_width() > 0:
		# 与最终结算一致降采样，避免全尺寸高分图 PNG 阻塞
		if img.get_width() > 1280:
			img = _downscale_image(img, 1280)
		var bytes := img.save_png_to_buffer()
		var chunks := _chunk_bytes(bytes)
		_rpc_settlement_preview_meta.rpc(round, chunks.size())
		for i in chunks.size():
			_rpc_settlement_preview_chunk.rpc(round, i, chunks[i])

## client 预览分块重组缓存
var _preview_meta_round: int = -1
var _preview_chunk_count: int = 0
var _preview_parts: Dictionary = {}

## host → client：照片预览元数据（round + 分块数），走独立通道
@rpc("authority", "call_remote", "reliable", CHUNK_CHANNEL)
func _rpc_settlement_preview_meta(round: int, chunk_count: int) -> void:
	_preview_meta_round = round
	_preview_chunk_count = chunk_count
	_preview_parts.clear()
	_try_assemble_preview()

## host → client：照片预览分块，走独立通道
@rpc("authority", "call_remote", "reliable", CHUNK_CHANNEL)
func _rpc_settlement_preview_chunk(round: int, index: int, data: PackedByteArray) -> void:
	if round != _preview_meta_round:
		return
	_preview_parts[index] = data
	_try_assemble_preview()

func _try_assemble_preview() -> void:
	if _preview_meta_round < 0 or _preview_parts.size() < _preview_chunk_count:
		return
	var round := _preview_meta_round
	var photo := Image.new()
	var err := photo.load_png_from_buffer(_join_chunks(_preview_parts, _preview_chunk_count))
	_preview_meta_round = -1
	_preview_chunk_count = 0
	_preview_parts.clear()
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
