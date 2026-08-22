## 職責：拍照舞台 tech demo 總控（場景負責人測試場）
## 整合：KayKit 舞台 + 拍照相機 RT + 快門拍攝 + 遮罩結算
## 流程：開始遊戲 → BATTLE 12 秒（測試加速）→ battle_ended 發拍照請求
##       → CameraSystem 回傳實拍貼圖 → 白閃 → SettlementSystem 結算 → 結算面板 → finish_scoring
## 玩家：P1 鍵盤可操作（WASD/空格/F），另 3 名假人演員佔位

extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2),
	Color(0.2, 0.4, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.8, 0.1),
]
const PHOTO_CAM_POS := Vector3(0.0, 3.0, 12.0)
const PHOTO_CAM_LOOK := Vector3(0.0, 1.2, 0.0)
const MAIN_CAM_POS := Vector3(16.0, 13.0, 15.0)
const MAIN_CAM_LOOK := Vector3(0.0, 1.0, 1.0)
const TEST_BATTLE_SECONDS := 12.0
const DECISIVE_MOMENT := 3.0  # 最後 3 秒決勝時刻（策劃案）

@onready var _stage_root: Node3D = $Stage
@onready var _actors_root: Node3D = $Actors
@onready var _main_camera: Camera3D = $MainCamera
@onready var _main_controller: CameraController = $MainCamera/CameraController
@onready var _photo_camera: Camera3D = $PhotoViewport/PhotoCamera
@onready var _photo_controller: CameraController = $PhotoViewport/PhotoCamera/CameraController
@onready var _settlement: SettlementSystem = $SettlementSystem
@onready var _results_panel: ResultsPanel = $ResultsPanel
@onready var _flash: ColorRect = $HUD/ShutterFlash
@onready var _timer_label: Label = $HUD/VBox/TimerLabel

var _stage_builder: StageBuilder

func _ready() -> void:
	_stage_builder = StageBuilder.new()
	_stage_builder.name = "StageBuilder"
	add_child(_stage_builder)
	_stage_builder.build_show_stage(_stage_root)

	_setup_main_camera()
	_setup_photo_camera()
	_spawn_actors()

	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.stage_timer_updated.connect(_on_stage_timer_updated)
	EventBus.photo_taken.connect(_on_photo_taken)
	_settlement.settlement_completed.connect(_on_settlement_completed)

	# 自動開局（正式流程由主界面触发）
	GameManager.start_game()

func _setup_main_camera() -> void:
	_main_controller.init(_main_camera)
	var fixed := FixedShotBehavior.new()
	fixed.position = MAIN_CAM_POS
	fixed.look_target = MAIN_CAM_LOOK
	_main_controller.push_behavior(fixed)
	CameraSystem.register_main_camera(_main_controller)

func _setup_photo_camera() -> void:
	_photo_controller.init(_photo_camera)
	var fixed := FixedShotBehavior.new()
	fixed.position = PHOTO_CAM_POS
	fixed.look_target = PHOTO_CAM_LOOK
	_photo_controller.push_behavior(fixed)
	CameraSystem.register_photo_camera(_photo_controller)

func _spawn_actors() -> void:
	# P1：真實玩家（鍵盤可操作）
	var player: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
	player.player_index = 0
	player.player_color = PLAYER_COLORS[0]
	player.position = Vector3(-2.0, 0.55, 1.5)
	player.add_to_group("settlement_actor")
	_actors_root.add_child(player)
	# 3 名假人演員（占位測試評分與遮擋）
	var dummy_spots := [
		Vector3(2.4, 0.5, 1.6),
		Vector3(-2.6, 0.5, -1.0),
		Vector3(0.0, 2.5, -2.4),
	]
	for i in 3:
		var dummy := DummyActor.new()
		dummy.player_index = i + 1
		dummy.player_color = PLAYER_COLORS[i + 1]
		dummy.position = dummy_spots[i]
		_actors_root.add_child(dummy)

## BATTLE 開始後把時長縮短為測試值（正式流程用 GameConfig.battle_duration）
func _on_battle_started() -> void:
	# 延遲寫入：GameManager 先 emit battle_started 才賦值 stage_time_remaining，
	# 直接寫會被覆蓋，用 deferred 在階段設置完成後再生效
	call_deferred("_apply_test_duration")

func _apply_test_duration() -> void:
	GameManager.stage_time_remaining = TEST_BATTLE_SECONDS

func _on_battle_ended() -> void:
	EventBus.photo_taken.emit(null)  # 請求拍照；CameraSystem 回傳實拍貼圖

func _on_stage_timer_updated(seconds: float) -> void:
	# 決勝時刻：最後 3 秒倒計時變紅
	if seconds <= DECISIVE_MOMENT:
		_timer_label.modulate = Color(1.0, 0.25, 0.2)
	else:
		_timer_label.modulate = Color.WHITE

func _on_photo_taken(texture: ViewportTexture) -> void:
	if texture == null:
		return
	_do_shutter_flash()

func _do_shutter_flash() -> void:
	_flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.3)

func _on_settlement_completed(results: Dictionary) -> void:
	for data in results.get("actors", []):
		print("[SETTLEMENT] P%d 总分=%.1f 占比=%.2f%% 入镜=%s" % [
			data["player_index"] + 1, data["total"], data["percent"] * 100.0, str(data["in_photo"])])
	_results_panel.show_results(results)
	_results_panel.show()
