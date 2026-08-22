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
const RESPAWN_HEIGHT: float = 8.0   ## 重生空中高度（落下）
const SPAWN_RANGE: float = 12.0     ## 隨機復活 xz 範圍

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2),
	Color(0.2, 0.4, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.8, 0.1),
]

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
@onready var _photo_camera: Camera3D = get_node_or_null("PhotoViewport/PhotoCamera") as Camera3D
@onready var _photo_controller: CameraController = get_node_or_null("PhotoViewport/PhotoCamera/CameraController") as CameraController
@onready var _settlement: Node = get_node_or_null("SettlementSystem")
@onready var _results_panel: Node = get_node_or_null("ResultsPanel")
@onready var _flash: ColorRect = get_node_or_null("HUD/ShutterFlash") as ColorRect
@onready var _stage_root: Node3D = get_node_or_null("Stage") as Node3D
@onready var _actors_root: Node3D = get_node_or_null("Actors") as Node3D
@onready var _spawn_root: Node3D = get_node_or_null("SpawnPoints") as Node3D

func _ready() -> void:
	await get_tree().process_frame

	_setup_cameras()
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
	var count: int = mini(get_player_count(), spawns.size())
	for i in count:
		var player: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
		player.player_index = i
		player.player_color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		player.position = spawns[i % spawns.size()]
		player.add_to_group("settlement_actor")
		(_actors_root if _actors_root else self).add_child(player)

## 同步四角玩家面板数量
func _setup_player_hud() -> void:
	var hud := get_node_or_null("HUD/PlayerHUD")
	if hud and hud.has_method("setup"):
		hud.setup(get_player_count())

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

## 場地範圍內隨機一點
func _random_spawn_position() -> Vector3:
	return Vector3(randf_range(-SPAWN_RANGE, SPAWN_RANGE), 1.0, randf_range(-SPAWN_RANGE, SPAWN_RANGE))

## 讀秒期間在複活點顯示可見標記（黃色半透明光柱）
func _create_respawn_marker(pos: Vector3) -> Node3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = RESPAWN_HEIGHT
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color.YELLOW
	m.material_override = mat
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
	if _photo_controller:
		_photo_controller.init(_photo_camera)
		var pf := FixedShotBehavior.new()
		pf.position = photo_cam_pos
		pf.look_target = photo_cam_look
		_photo_controller.push_behavior(pf)
		CameraSystem.register_photo_camera(_photo_controller)

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

func _on_battle_started() -> void:
	_on_level_battle_started()

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
	_flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.3)

func _on_settlement_completed(results: Dictionary) -> void:
	if _results_panel and _results_panel.has_method("show_results"):
		_results_panel.show_results(results)
		_results_panel.show()
	_on_level_settlement(results)

func _on_level_settlement(_results: Dictionary) -> void:
	pass
