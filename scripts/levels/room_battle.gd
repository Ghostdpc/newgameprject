## 职责：正式房间关卡 —— 接入 Fortnite Skye Room 作为战斗舞台
## - 房间缩放由 Room 节点上的 RoomPreview(@tool) 脚本控制，编辑器里实时预览
## - 地板/墙/大家具生成静态 trimesh 碰撞（阻挡玩家移动）
## - 小摆件转成 PhysicalProp（RigidBody3D），可被玩家飞扑/抓取撞飞

class_name RoomBattle
extends LevelBase

## S5 快门慢放时长（真实毫秒）
const SHUTTER_SLOWMO_MS := 550

@onready var _hud: HUD = get_node_or_null("HUD/MainLayer") as HUD

var _slowmo_end_msec: int = 0

# ------------------------------------------------------------------
# 碰撞分类：按 mesh 名称关键字匹配
# ------------------------------------------------------------------

## 静态碰撞（trimesh，阻挡玩家，不参与物理模拟）
## 地板 / 墙 / 门 / 门框 / 大家具
const STATIC_KEYWORDS: Array[String] = [
	"Fort_Floors", "Residential_Wall", "Residential_DoorC", "Door_01", "DoorTrim",
	"BayTrim02", "SkyLight", "Window", "Wallpaper",
	"Bed_Single", "Dresser", "DisplayCase", "Shelf_Tall", "Shelf_Open",
	"GamingTable", "Desk_01", "Dresser", "NightStand",
]

## 可撞飞物件（转 PhysicalProp，group "physical_prop"）
## 小摆件：书、手机、星星、笔、游戏手柄、球等
const PROP_KEYWORDS: Array[String] = [
	"BookPile", "BookStack", "Games_0", "Dice", "PlayerPiece",
	"Cell_Phone", "GlowingStar", "ArchitectTools", "Pencil",
	"TrashCan", "BeanBag", "DeskLamp", "Footrest", "Basket",
	"Plush", "Slippers", "Backpack", "Sword_", "Trophy",
]

## 忽略（无碰撞、无物理）：地毯、线、装饰贴花等
const IGNORE_KEYWORDS: Array[String] = [
	"Rug", "Carpet", "Wire", "Wires", "Poster", "BasePhotos",
	"WeaponBoard", "Sword_Plaque", "WallLight", "RoundLight",
	"Red_Carpet", "BedRoll", "Telescope", "FrostedGlass", "Concrete_Trim",
	"CampingShelve", "Trash", "ObjectiveBoard",
]

@onready var _room_root: Node3D = get_node_or_null("Stage/Room") as Node3D

## 出生点（房间中心坐标系，米）
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-1.0, 0.5, 1.0),
	Vector3(2.5, 0.5, -1.0),
	Vector3(-1.0, 0.5, -3.0),
	Vector3(2.5, 0.5, -3.0),
]

func get_player_count() -> int:
	return clampi(GameManager.lobby_player_count, 2, 4)

func get_spawn_points() -> Array[Vector3]:
	# 优先场景内 SpawnPoints 节点（策划摆放），否则默认四角（房间中心坐标系）
	if _spawn_root and _spawn_root.get_child_count() > 0:
		return super.get_spawn_points()
	return SPAWN_POINTS.duplicate()

func _setup_level() -> void:
	_ensure_room()
	_generate_collisions()
	_add_item_hotspots()
	# 结算界面：连接 player_hud + flow_finished（对齐 demo_stage）
	var scoring := get_node_or_null("ScoringScreen")
	if scoring and scoring.has_method("setup"):
		var player_hud := get_node_or_null("HUD/PlayerLayer/PlayerHUD")
		if player_hud:
			scoring.setup(player_hud)
		if scoring.has_signal("flow_finished") and not scoring.flow_finished.is_connected(_on_flow_finished):
			scoring.flow_finished.connect(_on_flow_finished)

## 房间已由编辑器摆放（Stage/Room 节点挂 RoomPreview 脚本控制缩放），这里只取引用
func _ensure_room() -> void:
	if not _stage_root:
		return
	_room_root = _stage_root.get_node_or_null("Room") as Node3D

## 覆写基类：主相机直接读 MainCamera 节点在编辑器里的位姿（所见即所得）
func _setup_cameras() -> void:
	if _main_controller and _main_camera:
		_main_controller.init(_main_camera)
		var fixed := FixedShotBehavior.new()
		fixed.position = _main_camera.global_position
		# 看向点 = 相机位置 + forward * 10（保持编辑器中调好的朝向）
		fixed.look_target = _main_camera.global_position + (-_main_camera.global_basis.z) * 10.0
		_main_controller.push_behavior(fixed)
		CameraSystem.register_main_camera(_main_controller)
	# 拍照相机 rig 依旧走 group 查找
	var rigs := get_tree().get_nodes_in_group("photo_camera_rig")
	if not rigs.is_empty():
		_photo_rig = rigs[0] as PhotoCameraRig

func _generate_collisions() -> void:
	if not _room_root:
		return
	for mi in _collect_meshes(_room_root):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.mesh == null:
			continue
		var nm := m.name
		if _matches_any(nm, IGNORE_KEYWORDS):
			continue
		if _matches_any(nm, PROP_KEYWORDS):
			_convert_to_prop(m)
		elif _matches_any(nm, STATIC_KEYWORDS):
			_add_static_body(m)

func _matches_any(name: String, keywords: Array[String]) -> bool:
	for k in keywords:
		if name.contains(k):
			return true
	return false

func _convert_to_prop(mi: MeshInstance3D) -> void:
	# 用 PhysicalProp 包装。关键：先记 saved_global，再 reparent，最后设回 prop 的 global
	var saved_global := mi.global_transform
	var saved_parent := mi.get_parent()
	# 1) 拆 mesh 出原父
	saved_parent.remove_child(mi)
	# 2) 建 prop 并塞 mesh（mesh 相对 prop 置零变换）
	var prop := PhysicalProp.new()
	prop.name = "Prop_" + mi.name
	prop.prop_mass = 2.0
	prop.freeze = true  # 初始冻结，被撞/抓时才解冻
	prop.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	# 3) prop 挂回原父，恢复全局位姿
	saved_parent.add_child(prop)
	prop.global_transform = saved_global

func _add_static_body(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	body.name = "Col"
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
	var hr := get_node_or_null("ItemHotspots")
	if not hr:
		return
	for c in hr.get_children():
		if c is Node3D:
			c.add_to_group("item_hotspot")

# ---------------------------------------------------------------
# 流程交互（对齐 demo_stage 的 S0~S7 完整体验）
# ---------------------------------------------------------------

## 关卡加载完成 → 自动进入流程（主题公布 3s 由 GameManager 驱动）
func _on_level_ready() -> void:
	GameManager.start_game()

## S5 快门：最后帧定格前 0.5x 慢放（白闪由基类处理）
func _on_level_battle_ended() -> void:
	Engine.time_scale = 0.5
	_slowmo_end_msec = Time.get_ticks_msec() + SHUTTER_SLOWMO_MS

func _process(_delta: float) -> void:
	if _slowmo_end_msec > 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_slowmo_end_msec = 0
		Engine.time_scale = 1.0

## S6/S7：结算完成 → 隐藏战斗 HUD 顶部/取景框，交给结算界面演出
func _on_level_settlement(_results: Dictionary) -> void:
	if _hud:
		_hud.enter_scoring_mode()

## 结算界面 flow_finished：重开 / 返回房间
func _on_flow_finished(action: String) -> void:
	Engine.time_scale = 1.0
	GameManager.time_rate = 1.0
	if action == "restart":
		# 重开：重载场景重置房间碰撞与可动摆件
		get_tree().change_scene_to_file("res://scenes/levels/room_battle.tscn")
	else:
		GameManager.enter_lobby()
