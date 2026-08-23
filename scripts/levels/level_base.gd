## 职责：拍照抢镜头关卡的玩法骨架（基类）
## 所有关卡共用一套玩法逻辑：相机 / 玩家生成 / 快门拍照 / 结算
## 子类只需覆写差异 hook（舞台布置、出生点、相机参数、特殊玩法）
## 只读现有流程接口（EventBus 信号），不修改流程管理

class_name LevelBase
extends Node3D

# ---- 玩家 ----（由关卡子类或场景节点提供，控制靠 PlayerController 内建）
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

# ---- 出界與重生（玩家順應，基類預設）----
const FALL_Y: float = -5.0          ## 低於此高度視為出界死亡
const RESPAWN_WAIT: float = 2.0     ## 死亡讀秒到重生
const RESPAWN_HEIGHT: float = 4.0   ## 重生空中高度（落下；場景有屋頂，8m 會穿頂）
const SPAWN_RANGE: float = 12.0     ## 隨機復活 xz 範圍

# ---- 相机默认参数 ----（子类可覆写）
@export var main_cam_pos: Vector3 = Vector3(16.0, 13.0, 15.0)
@export var main_cam_look: Vector3 = Vector3(0.0, 1.0, 1.0)
@export var main_cam_fov: float = 50.0

## 拍照相机：舞台正面固定机位、略微俯拍（策划案 09）
@export var photo_cam_pos: Vector3 = Vector3(0.0, 2.5, 12.0)
@export var photo_cam_look: Vector3 = Vector3(0.0, 1.2, 0.0)
@export var photo_cam_fov: float = 45.0

# ---- 节点引用（通用节点在场景中由关卡手动放置）----
@onready var _main_camera: Camera3D = get_node_or_null("MainCamera") as Camera3D
@onready var _main_controller: CameraController = get_node_or_null("MainCamera/CameraController") as CameraController
@onready var _settlement: Node = get_node_or_null("SettlementSystem")
@onready var _scoring_screen: Node = get_node_or_null("ScoringScreen")
@onready var _flash: ColorRect = get_node_or_null("HUD/FlashLayer/ShutterFlash") as ColorRect
@onready var _stage_root: Node3D = get_node_or_null("Stage") as Node3D
@onready var _actors_root: Node3D = get_node_or_null("Actors") as Node3D
@onready var _spawn_root: Node3D = get_node_or_null("SpawnPoints") as Node3D

## 拍照相机 rig（通过 group 查找，策划可任意命名/摆放）
var _photo_rig: PhotoCameraRig = null

func _ready() -> void:
	await get_tree().process_frame

	_setup_cameras()
	_setup_capture_highlight()
	_spawn_players()
	_setup_player_hud()
	_connect_signals()

	# 子类挂载（特殊玩法）
	_setup_level()

	# 进入对局（流程由 GameManager/匹配同事控制，关卡只在场景加载后准备好）
	_on_level_ready()

# ---------------------------------------------------------------
# 子类扩展点
# ---------------------------------------------------------------

## 关卡差异配置：舞台布置、道具、出生点、相机参数等
func _setup_level() -> void:
	pass

## 关卡加载完成后的回调（此时玩家已生成、相机已就位）
func _on_level_ready() -> void:
	pass

## 进入混战（battle_started）时的关卡特有逻辑
func _on_level_battle_started() -> void:
	pass

## 混战结束（battle_ended）→ 快门前的关卡特有逻辑
func _on_level_battle_ended() -> void:
	pass

## 收到实拍照片时的关卡特有逻辑
func _on_level_photo_taken(_texture: ViewportTexture) -> void:
	pass

## 每帧关卡特有更新
func _level_process(_delta: float) -> void:
	pass

## 决胜时刻提示（最后 3 秒）关卡特有逻辑
func _on_level_decisive_moment() -> void:
	pass

# ---------------------------------------------------------------
# 玩家生成（只实例化 + 赋值，控制靠 PlayerController 内建）
# ---------------------------------------------------------------

## 真人数量 2-4（由关卡或流程配置，默认 4）
func get_player_count() -> int:
	return 4

## 参与玩家的槽位索引（0-3）。默认按在场玩家数量取 0..count-1。
func get_player_slots() -> Array[int]:
	return range(get_player_count())

## 出生点列表，子类覆写提供
func get_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _spawn_root:
		for c in _spawn_root.get_children():
			if c is Node3D:
				points.append((c as Node3D).global_position)
	if not points.is_empty():
		return points
	# 默认四角
	return [
		Vector3(-2.0, 0.55, 1.5),
		Vector3(2.4, 0.5, 1.6),
		Vector3(-2.6, 0.5, -1.0),
		Vector3(0.0, 0.5, -2.4),
	]

func _spawn_players() -> void:
	var spawns := get_spawn_points()
	var slots := get_player_slots()
	var count: int = mini(get_player_count(), spawns.size())
	for k in count:
		var slot: int = slots[k] if k < slots.size() else k
		var player: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
		player.player_index = slot
		player.player_color = PlayerConfig.get_color(slot)
		player.position = spawns[slot % spawns.size()]
		player.add_to_group("settlement_actor")
		(_actors_root if _actors_root else self).add_child(player)

## 同步四角玩家面板数量
func _setup_player_hud() -> void:
	var hud := get_node_or_null("HUD/PlayerLayer/PlayerHUD")
	if hud and hud.has_method("setup"):
		hud.setup(get_player_count(), get_player_slots())

# ---------------------------------------------------------------
# 出界與重生
# ---------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var actors := _actors_root if _actors_root else self
	for child in actors.get_children():
		var player := child as PlayerController
		if player and not player.is_dead() and player.global_position.y < FALL_Y:
			_kill_and_respawn(player)

## 出界死亡 → （亮複活光柱）讀秒 → 隨機點空中落下
func _kill_and_respawn(player: PlayerController) -> void:
	var pos := _random_spawn_position()
	player.configure_respawn(Vector3(pos.x, RESPAWN_HEIGHT, pos.z), RESPAWN_WAIT)
	var marker := _create_respawn_marker(pos)
	player.die()
	# 讀秒結束由狀態機轉 RespawnFall，此處清理光柱
	await get_tree().create_timer(RESPAWN_WAIT).timeout
	marker.queue_free()

## 場地範圍內隨機一點（按舞台 AABB 鉗制，避免復活到地圖外）
func _random_spawn_position() -> Vector3:
	var bounds := _get_stage_bounds()
	if bounds.size.x <= 0.1 or bounds.size.z <= 0.1:
		return Vector3(randf_range(-SPAWN_RANGE, SPAWN_RANGE), 1.0, randf_range(-SPAWN_RANGE, SPAWN_RANGE))
	const MARGIN := 0.5
	var x := randf_range(bounds.position.x + MARGIN, bounds.end.x - MARGIN)
	var z := randf_range(bounds.position.z + MARGIN, bounds.end.z - MARGIN)
	return Vector3(x, 1.0, z)

## 舞台 AABB（由 Stage 下所有 mesh 的全局包圍盒合併），失敗時回退 SPAWN_RANGE
func _get_stage_bounds() -> AABB:
	var root: Node = _stage_root if _stage_root else self
	var bounds := AABB()
	var found := false
	for mi in _collect_mesh_instances(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		for cx in [aabb.position.x, aabb.end.x]:
			for cy in [aabb.position.y, aabb.end.y]:
				for cz in [aabb.position.z, aabb.end.z]:
					var p := mi.global_transform * Vector3(cx, cy, cz)
					if found:
						bounds = bounds.expand(p)
					else:
						bounds = AABB(p, Vector3.ZERO)
						found = true
	if not found:
		return AABB(Vector3(-SPAWN_RANGE, 0.0, -SPAWN_RANGE), Vector3(SPAWN_RANGE * 2.0, 0.0, SPAWN_RANGE * 2.0))
	return bounds

func _collect_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			result.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)
	return result

## 讀秒期間在複活點顯示可見標記（黃色能量柱，能量自下而上湧動）
func _create_respawn_marker(pos: Vector3) -> Node3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = RESPAWN_HEIGHT
	m.mesh = cyl
	# 噪波動畫能量柱：自下而上湧動 + 底部光源向上衰減 + 呼吸脈衝
	var shader := load("res://resources/shaders/respawn_marker.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("col", Color(1.0, 0.95, 0.4, 0.45))
	mat.set_shader_parameter("flow_speed", 1.5)
	mat.set_shader_parameter("pulse", 0.7)
	m.material_override = mat
	m.layers = 4  # layer = UI 標識，不進拍照 RT
	m.position = Vector3(pos.x, RESPAWN_HEIGHT * 0.5, pos.z)
	add_child(m)
	return m

# ---------------------------------------------------------------
# 相机
# ---------------------------------------------------------------

func _setup_cameras() -> void:
	if _main_controller:
		_main_controller.init(_main_camera)
		var fixed := FixedShotBehavior.new()
		fixed.position = main_cam_pos
		fixed.look_target = main_cam_look
		_main_controller.push_behavior(fixed)
		CameraSystem.register_main_camera(_main_controller)
		_main_camera.add_to_group("main_camera")

	# 注册取景框（拍照相机 frustum 跟随它）
	var viewfinder := get_node_or_null("HUD/MainLayer/CameraViewfinder") as Control
	if viewfinder:
		viewfinder.add_to_group("camera_viewfinder")

	# 拍照相机 rig 自己注册（在 rig._ready 里），这里只做查找
	var rigs := get_tree().get_nodes_in_group("photo_camera_rig")
	if not rigs.is_empty():
		_photo_rig = rigs[0] as PhotoCameraRig

## 地面高亮拍照取景区域（半透明黄光）。自解析 main_camera / camera_viewfinder group。
## 已禁用：返回，不再生成高亮。
func _setup_capture_highlight() -> void:
	return
	if get_node_or_null("CaptureZoneHighlight"):
		return
	var hl := CaptureZoneHighlight.new()
	hl.name = "CaptureZoneHighlight"
	add_child(hl)

# ---------------------------------------------------------------
# 信号
# ---------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.stage_timer_updated.connect(_on_stage_timer)
	EventBus.photo_taken.connect(_on_photo_taken)
	if _settlement and _settlement.has_signal("settlement_completed"):
		_settlement.settlement_completed.connect(_on_settlement_completed)
	if _scoring_screen and _scoring_screen.has_signal("flow_finished"):
		_scoring_screen.flow_finished.connect(_on_flow_finished)

func _on_flow_finished(action: String) -> void:
	match action:
		"restart":
			GameManager.start_game()
		"lobby":
			GameManager.enter_lobby()

func _on_battle_started() -> void:
	_on_level_battle_started()
	# 每轮开始：给每个玩家随机一个表情
	var actors := _actors_root if _actors_root else self
	for child in actors.get_children():
		var p := child as PlayerController
		if p:
			p.enter_match_random_face()

func _on_battle_ended() -> void:
	_on_level_battle_ended()
	# 快门拍照请求（CameraSystem 回传实拍贴图）
	EventBus.photo_taken.emit(null)

func _on_stage_timer(seconds: float) -> void:
	const DECISIVE: float = 3.0
	if seconds <= DECISIVE and seconds > 0.0:
		_on_level_decisive_moment()
	_level_process(seconds)

func _on_photo_taken(texture: ViewportTexture) -> void:
	if texture == null:
		return
	_do_shutter_flash()
	_on_level_photo_taken(texture)

func _do_shutter_flash() -> void:
	if not _flash:
		return
	# 注意：ShutterFlash 底色 alpha=0，modulate 是乘算（0×1=0）盖不住。
	# 必须驱动 color:a：快门瞬间全屏不透明白，再 0.3s 淡出。
	# 这层白闪同时遮住结算取掩码那两帧（演员临时移出主相机渲染层）。
	_flash.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.3)

func _on_settlement_completed(results: Dictionary) -> void:
	if _scoring_screen:
		var hud := get_node_or_null("HUD/PlayerLayer/PlayerHUD")
		if hud and _scoring_screen.has_method("setup"):
			_scoring_screen.setup(hud)
		if _scoring_screen.has_method("show_results"):
			_scoring_screen.show_results(results)
	_on_level_settlement(results)

func _on_level_settlement(_results: Dictionary) -> void:
	pass
