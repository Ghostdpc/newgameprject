## 职责：通用房间关卡 —— 快速把场景/模型资源接入为正式战斗关卡
## 用法（见 docs/dev/新关卡接入指南.md）：
##   1. 复制模板场景根挂本脚本，Stage/Room 挂 RoomSource
##   2. RoomSource 填 scene_path（.tscn 预摆好用 NONE；.glb 用 SCALE_TO_FIT）
##   3. 编辑器摆 CameraZones（每个 zone 内含主相机 + SpawnPoints + ItemHotspots）
##      开局随机选一个 zone：其相机生效、出生点/道具点启用
##   4. 如需调整碰撞分类，改下方 @export 关键字数组
##
## 内置：主相机读选中 zone 的相机节点位姿、地板/墙/大家具静态 trimesh 碰撞、
##       小摆件转 PhysicalProp（可撞飞）、完整流程交互（S0~S7 对齐 demo_stage）
## 兼容：无 CameraZone 时回退旧的 MainCamera / SpawnPoints / ItemHotspots 单组结构。

class_name GlbStageLevel
extends LevelBase

## S5 快门慢放时长（真实毫秒）
const SHUTTER_SLOWMO_MS := 550

@onready var _hud: HUD = get_node_or_null("HUD/MainLayer") as HUD

var _slowmo_end_msec: int = 0
## 拍照前 3 秒逐步减速慢放控制器（battle 倒數至 threshold 時啟動；道具加時回升則取消復原）
var _shutter_slowmo: ShutterSlowmoController

# ------------------------------------------------------------------
# 碰撞分类：按 mesh 名称关键字匹配（不同资源命名不同，可在 Inspector 覆盖）
# ------------------------------------------------------------------

## 静态碰撞（trimesh，阻挡玩家）：地板 / 墙 / 门 / 大家具
@export var static_keywords: Array[String] = [
	"Fort_Floors", "Residential_Wall", "Residential_DoorC", "Door_01", "DoorTrim",
	"BayTrim02", "SkyLight", "Window", "Wallpaper",
	"Bed_Single", "Dresser", "DisplayCase", "Shelf_Tall", "Shelf_Open", "CampingShelve",
	"GamingTable", "GamingChair", "Armchair", "Chair", "Desk_01", "NightStand",
]

## 可撞飞物件（转 PhysicalProp）：书、手机、星星、摆件等
@export var prop_keywords: Array[String] = [
	"BookPile", "BookStack", "Games_0", "Dice", "PlayerPiece",
	"Cell_Phone", "ArchitectTools", "Pencil",
	"TrashCan", "BeanBag", "DeskLamp", "Footrest", "Basket",
	"Plush", "Slippers", "Backpack", "Sword_", "Trophy",
]

## 是否自动生成碰撞（false 时场景物体不加任何碰撞体，可在 Inspector 关闭）
@export var generate_collisions := true

## 忽略（无碰撞、无物理）：地毯、线、装饰等
@export var ignore_keywords: Array[String] = [
	"Rug", "Carpet", "Wire", "Wires", "Poster", "BasePhotos",
	"WeaponBoard", "Sword_Plaque", "WallLight", "RoundLight",
	"Red_Carpet", "BedRoll", "Telescope", "FrostedGlass", "Concrete_Trim",
	"GlowingStar", "ObjectiveBoard",
]

@onready var _room_root: Node3D = get_node_or_null("Stage/Room") as Node3D

## 本关所有相机分组（容器下挂 CameraZone 脚本或本脚本子类）
const GENERATED_STATIC_BODY_NAME := "GeneratedRoomCollision"
const SKIP_ROOM_COLLISION_META := &"skip_room_collision"

var _zones: Array[CameraZone] = []
## 本次游戏选中的分组
var _active_zone: CameraZone = null

func get_player_count() -> int:
	return clampi(GameManager.lobby_player_count, 2, 4)

## 按大厅已加入的槽位生成玩家（P1/P3 加入则只出 P1、P3）
func get_player_slots() -> Array[int]:
	var slots := GameManager.get_joined_slots()
	if slots.is_empty():
		return super.get_player_slots()
	return slots

func get_spawn_points() -> Array[Vector3]:
	# 有选中分组则用分组出生点
	if _active_zone:
		var pts := _active_zone.get_spawn_points()
		if not pts.is_empty():
			return pts
	# 回退：旧结构 SpawnPoints 节点
	if _spawn_root and _spawn_root.get_child_count() > 0:
		return super.get_spawn_points()
	return [
		Vector3(-1.0, 0.5, 1.0),
		Vector3(2.5, 0.5, -1.0),
		Vector3(-1.0, 0.5, -3.0),
		Vector3(2.5, 0.5, -3.0),
	]

## 复活从策划摆放的出生点中选取，避免随机落在房间外。
func _random_spawn_position() -> Vector3:
	var spawn_points := get_spawn_points()
	if not spawn_points.is_empty():
		return spawn_points.pick_random()
	return super._random_spawn_position()

## 先选相机分组再走基类流程，保证 _setup_cameras 读到的就是选中相机的位姿
func _ready() -> void:
	await _select_zone()
	super._ready()

func _setup_level() -> void:
	_ensure_room()
	_generate_collisions()
	_add_item_hotspots()
	# 拍照前 3 秒逐步减速慢放（快門張力）：道具加時回升時自動取消復原
	_shutter_slowmo = ShutterSlowmoController.new()
	_shutter_slowmo.name = "ShutterSlowmo"
	add_child(_shutter_slowmo)
	# 结算界面：连接 player_hud + flow_finished
	var scoring := get_node_or_null("ScoringScreen") as ScoringScreen
	if scoring:
		var player_hud := get_node_or_null("HUD/PlayerLayer/PlayerHUD") as PlayerHUD
		if player_hud:
			scoring.setup(player_hud)
		if not scoring.flow_finished.is_connected(_on_flow_finished):
			scoring.flow_finished.connect(_on_flow_finished)

## 舞台资源由 Stage/Room 节点（挂 RoomSource 脚本）负责加载与缩放，这里只取引用
func _ensure_room() -> void:
	if not _stage_root:
		return
	_room_root = _stage_root.get_node_or_null("Room") as Node3D

## 主相机读选中 zone 的相机节点在编辑器里的位姿（所见即所得）
func _setup_cameras() -> void:
	# 有选中分组：把分组相机位姿同步到 MainCamera，使其成为真正生效的相机
	if _active_zone:
		var zc := _active_zone.get_camera()
		if zc and _main_camera:
			_main_camera.global_transform = zc.global_transform
			_main_camera.fov = zc.fov
			_main_camera.near = zc.near
			_main_camera.far = zc.far
	if _main_controller and _main_camera:
		_main_controller.init(_main_camera)
		var fixed := FixedShotBehavior.new()
		fixed.position = _main_camera.global_position
		fixed.look_target = _main_camera.global_position + (-_main_camera.global_basis.z) * 10.0
		_main_controller.push_behavior(fixed)
		CameraSystem.register_main_camera(_main_controller)
		_main_camera.add_to_group("main_camera")
		_main_camera.current = true
	var viewfinder := get_node_or_null("HUD/MainLayer/CameraViewfinder") as Control
	if viewfinder:
		viewfinder.add_to_group("camera_viewfinder")
	var rigs := get_tree().get_nodes_in_group("photo_camera_rig")
	if not rigs.is_empty():
		_photo_rig = rigs[0] as PhotoCameraRig

## 收集所有相机分组并选一个；无分组则回退旧单组结构。
## 在 _setup_cameras 前调用（_onready 变量此时可能尚未初始化，勿依赖）。
## 联机：host 权威选分区并广播，client 用同一分区（避免相机/出生点/道具点错位）。
func _select_zone() -> void:
	_collect_zones()
	if _zones.is_empty():
		return
	if NetManager.is_online and not NetManager.is_host:
		# client：等待 host 广播的分区索引（最多约 3 秒）
		var guard := 0
		while NetManager.zone_index < 0 and guard < 600:
			await get_tree().process_frame
			guard += 1
		var idx := clampi(NetManager.zone_index, 0, _zones.size() - 1)
		_active_zone = _zones[idx]
	else:
		var idx := randi() % _zones.size()
		_active_zone = _zones[idx]
		if NetManager.is_online and NetManager.is_host:
			NetManager.broadcast_zone_index(idx)
	_apply_active_zone()

## 收集关卡里的 CameraZone（含根/子节点挂 CameraZone 脚本的）
func _collect_zones() -> void:
	_zones.clear()
	for n in get_tree().get_nodes_in_group("camera_zone"):
		if n is CameraZone:
			_zones.append(n as CameraZone)
	if _zones.is_empty():
		# 未入组（可能 _ready 前）时直接扫子节点
		var stack: Array[Node] = [self]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is CameraZone and n != self:
				_zones.append(n as CameraZone)
			for c in n.get_children():
				stack.append(c)

## 让选中的 zone 生效：只有选中分组的道具点参与落点。
## 相机位姿由 _setup_cameras 从选中 zone 的相机同步到根 MainCamera；
## zone 内的相机只是编辑器里的"取景预览"，不直接渲染。
func _apply_active_zone() -> void:
	for z in _zones:
		z.deactivate_hotspots()
	_active_zone.activate_hotspots()

func _generate_collisions() -> void:
	if not generate_collisions or not _room_root:
		return
	for mi in _collect_meshes(_room_root):
		var mesh := mi as MeshInstance3D
		if not _is_collision_candidate(mesh):
			continue
		var mesh_name := mesh.name
		if _matches_any(mesh_name, ignore_keywords):
			continue
		if _matches_any(mesh_name, prop_keywords):
			_convert_to_prop(mesh)
		elif _matches_any(mesh_name, static_keywords):
			_add_static_body(mesh)

## 只为游戏中实际可见的关卡网格生成碰撞。
## 这会自动排除美术隐藏的旧物件，避免留下“看不见但会挡人”的碰撞体。
func _is_collision_candidate(mesh: MeshInstance3D) -> bool:
	if mesh == null or mesh.mesh == null:
		return false
	if not mesh.is_visible_in_tree() or mesh.layers == 0:
		return false
	if bool(mesh.get_meta(SKIP_ROOM_COLLISION_META, false)):
		return false
	if mesh.get_parent() is PhysicalProp:
		return false
	return mesh.get_node_or_null(GENERATED_STATIC_BODY_NAME) == null and mesh.get_node_or_null("Col") == null

func _matches_any(name: String, keywords: Array[String]) -> bool:
	for k in keywords:
		if name.contains(k):
			return true
	return false

func _convert_to_prop(mi: MeshInstance3D) -> void:
	var saved_global := mi.global_transform
	var saved_parent := mi.get_parent()
	saved_parent.remove_child(mi)
	var prop := PhysicalProp.new()
	prop.name = "GeneratedRoomProp_" + mi.name
	prop.set_meta(SKIP_ROOM_COLLISION_META, true)
	prop.prop_mass = 2.0
	prop.freeze = true
	# RigidBody 不可帶非單位縮放：房間 room_scale 使摆件世界 scale≈0.03，
	# RigidBody 帶此縮放會令物理碰撞體在 unfreeze(鬆手)/受力(飛撲)時錯誤膨脹→頂飛玩家。
	# 對策：prop 只取正交部分(scale=1，物理穩定)，縮放烘焙進 mesh 子節點與碰撞 shape，視覺不變。
	var ortho := saved_global.orthonormalized()
	mi.transform = ortho.affine_inverse() * saved_global   # mesh 相對 prop：純縮放
	prop.add_child(mi)
	prop.transform = saved_parent.global_transform.affine_inverse() * ortho
	saved_parent.add_child(prop)

func _add_static_body(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = GENERATED_STATIC_BODY_NAME
	body.set_meta(SKIP_ROOM_COLLISION_META, true)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)

func _collect_meshes(root: Node) -> Array:
	var result: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			result.append(n)
		for c in n.get_children():
			stack.append(c)
	return result

func _add_item_hotspots() -> void:
	# 有选中分组则只启用该分组的道具点
	if _active_zone:
		_active_zone.activate_hotspots()
		return
	var hr := get_node_or_null("ItemHotspots")
	if not hr:
		return
	for c in hr.get_children():
		if c is Node3D:
			c.add_to_group("item_hotspot")

# ---------------------------------------------------------------
# 流程交互（对齐 demo_stage 的 S0~S7 完整体验）
# ---------------------------------------------------------------

func _on_level_ready() -> void:
	GameManager.start_game()

func _on_level_battle_ended() -> void:
	# 拍照觸發：取消减速慢放，回到正常再進 0.5x 定格快門
	if _shutter_slowmo and _shutter_slowmo.active:
		_shutter_slowmo.cancel()
	Engine.time_scale = 0.5
	_slowmo_end_msec = Time.get_ticks_msec() + SHUTTER_SLOWMO_MS
	# 联机：广播慢放流速
	if NetManager.is_online and NetManager.is_host:
		NetManager.broadcast_time_scale(0.5)

func _process(delta: float) -> void:
	# 联机 client：慢放由 host 权威，client 收广播（不本地驱动）
	if NetManager.is_online and not NetManager.is_host:
		return
	# 倒數至拍照前 3 秒 → 逐步减速慢放（道具加時回升時 controller 內部會取消復原）
	if _shutter_slowmo and GameManager.current_stage == GameManager.GameStage.BATTLE:
		_shutter_slowmo.update_trigger(GameManager.stage_time_remaining)
	if _slowmo_end_msec > 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_slowmo_end_msec = 0
		Engine.time_scale = 1.0
		if NetManager.is_online and NetManager.is_host:
			NetManager.broadcast_time_scale(1.0)

func _on_level_settlement(_results: Dictionary) -> void:
	if _hud:
		_hud.enter_scoring_mode()

func _on_flow_finished(action: String) -> void:
	Engine.time_scale = 1.0
	GameManager.time_rate = 1.0
	if action == "restart":
		GameManager.goto_level(get_tree().current_scene.scene_file_path)
	else:
		GameManager.enter_lobby()
