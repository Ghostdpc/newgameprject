## 职责：游戏整体流程控制，按 GameConfig 驱动各阶段顺序推进
# 注意：autoload 脚本不使用 class_name，因为 autoload 名称本身即全局引用
# HUD / ResultsOverlay 使用 GameManager.GameStage 时，GameManager 指 autoload 单例，可正常访问枚举

extends Node

enum GameStage {
	MAIN_MENU,       # S0 标题
	LOBBY,           # S1+S2 玩家加入与人数确认
	THEME_ANNOUNCE,  # S3 主题公布（3 秒）
	GRAB_CLOTHES,    # （V1.3 流程已取消，duration=0 自动跳过）
	BATTLE,          # S4 倒计时混战（抢镜头）
	SCORE_SHUTTER,   # S5 快门（由关卡演出，流程不驻留）
	SCORING,         # S6+S7 系统评分 → 冠军结算
}

## 阶段推进顺序（不含 MAIN_MENU，由 start_game 触发）
const STAGE_ORDER: Array = [
	GameStage.THEME_ANNOUNCE,
	GameStage.GRAB_CLOTHES,
	GameStage.BATTLE,
	GameStage.SCORING,
]

var current_stage: GameStage = GameStage.MAIN_MENU
var stage_time_remaining: float = 0.0
## 倒计时速率乘数（1.0 = 正常；由 timer_scale_effect 临时修改）
var time_scale: float = 1.0
var config: GameConfig

## 倒计时倍率（时间道具：快进 2.0 / 慢放 0.5，默认 1.0）
var time_rate: float = 1.0
## 大厅确认的玩家数（2~4，由大厅界面写入，关卡读取）
var lobby_player_count: int = 4
## 加载完成后要进入的关卡场景（goto_level 先展示加载界面）
var pending_level_path: String = "res://scenes/levels/room_stage_battle.tscn"

## 联机角色：host 权威驱动流程，client 跟随广播
func _is_net_host() -> bool:
	return NetManager.is_online and NetManager.is_host

func _is_net_client() -> bool:
	return NetManager.is_online and not NetManager.is_host

## 进入关卡：先展示加载界面，加载界面后台真实预加载关卡，完成后跳关
func goto_level(path: String) -> void:
	if _is_net_client():
		# client 无权推进流程：请求 host 权威切换，host 广播回来再统一走加载
		_request_goto_level.rpc_id(1, path)
		return
	pending_level_path = path
	NetManager.zone_index = -1  # 重置分区索引，client 等待 host 新广播
	if _is_net_host():
		_rpc_goto_level.rpc(path, lobby_player_count)
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")

## client → host：请求进入指定关卡（client 点「再来一局」等）
@rpc("any_peer", "reliable")
func _request_goto_level(path: String) -> void:
	if not _is_net_host():
		return
	goto_level(path)

## host → client：同步关卡加载与玩家数
@rpc("authority", "reliable")
func _rpc_goto_level(path: String, player_count: int) -> void:
	pending_level_path = path
	lobby_player_count = player_count
	NetManager.zone_index = -1  # 重置，等待 host 新分区广播
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")

## 加载界面完成时调用（真实加载失败时兜底）
func enter_pending_level() -> void:
	get_tree().change_scene_to_file(pending_level_path)
## 每个玩家绑定的输入设备（按槽位 0-3，与 player_index 对齐）：
##   -2 = 未绑定（空槽；自动：P1/P2 键盘，P3/P4 手柄）
##   -1 = 键盘（仅 P1/P2 有效）
##   >=0 = 手柄 device id
var player_devices: Array[int] = [-2, -2, -2, -2]

## 已加入的槽位索引（0-3），供关卡按槽位生成对应玩家与面板。
## 联机：以 host 发的席位表为准（host 权威），两端都看到同批在场玩家。
func get_joined_slots() -> Array[int]:
	if NetManager.is_online:
		var slots: Array[int] = []
		for i in NetManager.seat_owners.size():
			var o: Dictionary = NetManager.seat_owners[i]
			if o["kind"] != NetManager.SeatKind.EMPTY:
				slots.append(i)
		return slots
	var slots2: Array[int] = []
	for i in player_devices.size():
		if player_devices[i] != -2:
			slots2.append(i)
	return slots2

var _stage_index: int = -1
var _timer_active: bool = false
## 倒计时广播分桶去重（0.1s 粒度）
var _last_timer_bucket: int = -1

func _ready() -> void:
	config = GameConfig.new()
	config.load()
	KeybindSettings.load_bindings()

## 从主界面进入游戏，重置流程
func start_game() -> void:
	if _is_net_client():
		return
	_stage_index = -1
	time_rate = 1.0
	_advance_stage()

## 结算阶段由玩家手动确认结束（用于 scoring_duration = 0 的情况）
func finish_scoring() -> void:
	_timer_active = false
	_advance_stage()

func _advance_stage() -> void:
	if _is_net_client():
		return
	_stage_index += 1
	if _stage_index >= STAGE_ORDER.size():
		_transition_to(GameStage.MAIN_MENU)
		return
	_transition_to(STAGE_ORDER[_stage_index])

func _transition_to(stage: GameStage) -> void:
	if _is_net_client():
		return
	# 返回大厅前先重置全员就绪（host 权威，再广播），避免 client 收到 LOBBY 时带上旧就绪态
	if stage == GameStage.LOBBY:
		NetManager.enter_lobby_reset_ready()
	if _is_net_host():
		_rpc_transition.rpc(stage)
	_apply_stage(stage)
	# MAIN_MENU / LOBBY 无计时，_apply_stage 已切场景
	if stage == GameStage.MAIN_MENU or stage == GameStage.LOBBY:
		return
	var duration := _get_stage_duration(stage)
	# SCORING 且 duration = 0：停留直到 finish_scoring() 被呼叫
	if stage == GameStage.SCORING and duration <= 0.0:
		_timer_active = false
		return
	# 其他阶段 duration = 0：跳过
	if duration <= 0.0:
		call_deferred("_advance_stage")
		return
	stage_time_remaining = duration
	_last_timer_bucket = -1
	_timer_active = true

## 阶段落地（host 本地 / client 广播 / catchup 三路共用）：状态 + 事件 + 场景切换。
## 不含 host 独有逻辑（就绪重置 / 计时），避免 host/client 双写分叉。
func _apply_stage(stage: GameStage) -> void:
	current_stage = stage
	EventBus.stage_changed.emit(stage)
	match stage:
		GameStage.MAIN_MENU:
			_timer_active = false
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		GameStage.LOBBY:
			_timer_active = false
			get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
		GameStage.BATTLE:
			EventBus.battle_started.emit()

## host → client：阶段推进复制（场景切换 + 事件）
@rpc("authority", "reliable")
func _rpc_transition(stage: int) -> void:
	_apply_stage(stage as GameStage)

## host → 单个 peer：迟到加入/断线重连的状态追赶（当前阶段 + 关卡 + 人数 + 相机分区）
@rpc("authority", "reliable")
func _rpc_catchup(stage: int, level_path: String, player_count: int, zone: int) -> void:
	NetManager.zone_index = zone
	lobby_player_count = player_count
	match stage:
		GameStage.MAIN_MENU, GameStage.LOBBY:
			_apply_stage(stage as GameStage)
		_:
			# 正在对局中：走统一加载流程进入当前关卡（实体状态由 NetManager.request_entity_state 补收）
			current_stage = stage as GameStage
			EventBus.stage_changed.emit(stage)
			if level_path.is_empty():
				level_path = pending_level_path
			pending_level_path = level_path
			get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")

func _get_stage_duration(stage: GameStage) -> float:
	match stage:
		GameStage.THEME_ANNOUNCE: return config.theme_announce_duration
		GameStage.GRAB_CLOTHES:   return config.grab_clothes_duration
		GameStage.BATTLE:         return config.battle_duration
		GameStage.SCORING:        return config.scoring_duration
	return 0.0

func _process(delta: float) -> void:
	if _is_net_client():
		return  # client 计时由 host 广播驱动
	if not _timer_active:
		return
	stage_time_remaining -= delta * time_rate
	stage_time_remaining = maxf(stage_time_remaining, 0.0)
	EventBus.stage_timer_updated.emit(stage_time_remaining)
	if _is_net_host():
		# 节流到 ~10Hz（按 0.1s 分桶去重），避免每渲染帧高频发 + 抖动
		var bucket := int(stage_time_remaining * 10.0)
		if bucket != _last_timer_bucket:
			_last_timer_bucket = bucket
			_rpc_timer.rpc(stage_time_remaining)
	if stage_time_remaining <= 0.0:
		_timer_active = false
		time_rate = 1.0
		if current_stage == GameStage.BATTLE:
			EventBus.battle_ended.emit()
		_advance_stage()

## host → client：倒计时同步（ordered 防倒退；10Hz 节流后丢失自愈）
@rpc("authority", "unreliable_ordered")
func _rpc_timer(seconds: float) -> void:
	stage_time_remaining = seconds
	EventBus.stage_timer_updated.emit(seconds)

## 加时/减时（交互文档：减时最低保留 1 秒）。返回实际变化量（供飞字显示）
func add_time(delta_seconds: float) -> float:
	var before := stage_time_remaining
	var after := before + delta_seconds
	if delta_seconds < 0.0:
		after = maxf(after, 1.0)
	after = maxf(after, 0.0)
	stage_time_remaining = after
	EventBus.stage_timer_updated.emit(stage_time_remaining)
	return after - before

## 进入大厅（返回房间 / 标题→进入）
func enter_lobby() -> void:
	if _is_net_client():
		# client 无权推进流程：请求 host 权威返回大厅，host 广播回来
		_request_enter_lobby.rpc_id(1)
		return
	get_tree().paused = false
	time_rate = 1.0
	_timer_active = false
	_transition_to(GameStage.LOBBY)

## client → host：请求返回大厅
@rpc("any_peer", "reliable")
func _request_enter_lobby() -> void:
	if not _is_net_host():
		return
	enter_lobby()

## 返回标题
func enter_title() -> void:
	get_tree().paused = false
	time_rate = 1.0
	_timer_active = false
	_transition_to(GameStage.MAIN_MENU)

## 进入键位设置
func enter_settings() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/keybind_settings.tscn")
