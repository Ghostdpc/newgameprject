## 职责：通用 GLB 场景关卡 —— 快速把场景资源接入为正式战斗关卡
## 用法（见 docs/dev/新关卡接入指南.md）：
##   1. 复制模板场景，根节点挂本脚本
##   2. Stage 下放一个 Node3D 挂 StagePreview（scene_path 填 glb，room_scale 调尺寸）
##   3. 编辑器摆 MainCamera / PhotoCameraRig / SpawnPoints / ItemHotspots
##   4. 如需调整碰撞分类，改下方 @export 关键字数组
##
## 内置：主相机读 MainCamera 节点位姿、地板/墙/大家具静态 trimesh 碰撞、
##       小摆件转 PhysicalProp（可撞飞）、完整流程交互（S0~S7 对齐 demo_stage）

class_name GlbStageLevel
extends LevelBase

## S5 快门慢放时长（真实毫秒）
const SHUTTER_SLOWMO_MS := 550

@onready var _hud: HUD = get_node_or_null("HUD/MainLayer") as HUD

var _slowmo_end_msec: int = 0

# ------------------------------------------------------------------
# 碰撞分类：按 mesh 名称关键字匹配（不同资源命名不同，可在 Inspector 覆盖）
# ------------------------------------------------------------------

## 静态碰撞（trimesh，阻挡玩家）：地板 / 墙 / 门 / 大家具
@export var static_keywords: Array[String] = [
	"Fort_Floors", "Residential_Wall", "Residential_DoorC", "Door_01", "DoorTrim",
	"BayTrim02", "SkyLight", "Window", "Wallpaper",
	"Bed_Single", "Dresser", "DisplayCase", "Shelf_Tall", "Shelf_Open",
	"GamingTable", "Desk_01", "NightStand",
]

## 可撞飞物件（转 PhysicalProp）：书、手机、星星、摆件等
@export var prop_keywords: Array[String] = [
	"BookPile", "BookStack", "Games_0", "Dice", "PlayerPiece",
	"Cell_Phone", "GlowingStar", "ArchitectTools", "Pencil",
	"TrashCan", "BeanBag", "DeskLamp", "Footrest", "Basket",
	"Plush", "Slippers", "Backpack", "Sword_", "Trophy",
]

## 忽略（无碰撞、无物理）：地毯、线、装饰等
@export var ignore_keywords: Array[String] = [
	"Rug", "Carpet", "Wire", "Wires", "Poster", "BasePhotos",
	"WeaponBoard", "Sword_Plaque", "WallLight", "RoundLight",
	"Red_Carpet", "BedRoll", "Telescope", "FrostedGlass", "Concrete_Trim",
	"CampingShelve", "Trash", "ObjectiveBoard",
]

@onready var _room_root: Node3D = get_node_or_null("Stage/Room") as Node3D

func get_player_count() -> int:
	return clampi(GameManager.lobby_player_count, 2, 4)

func get_spawn_points() -> Array[Vector3]:
	# 优先场景内 SpawnPoints 节点（策划摆放），否则默认四角
	if _spawn_root and _spawn_root.get_child_count() > 0:
		return super.get_spawn_points()
	return [
		Vector3(-1.0, 0.5, 1.0),
		Vector3(2.5, 0.5, -1.0),
		Vector3(-1.0, 0.5, -3.0),
		Vector3(2.5, 0.5, -3.0),
	]

func _setup_level() -> void:
	_ensure_room()
	_generate_collisions()
	_add_item_hotspots()
	# 结算界面：连接 player_hud + flow_finished
	var scoring := get_node_or_null("ScoringScreen") as ScoringScreen
	if scoring:
		var player_hud := get_node_or_null("HUD/PlayerLayer/PlayerHUD") as PlayerHUD
		if player_hud:
			scoring.setup(player_hud)
		if not scoring.flow_finished.is_connected(_on_flow_finished):
			scoring.flow_finished.connect(_on_flow_finished)

## 舞台资源由 Stage/Room 节点（挂 StagePreview 脚本）负责加载与缩放，这里只取引用
func _ensure_room() -> void:
	if not _stage_root:
		return
	_room_root = _stage_root.get_node_or_null("Room") as Node3D

## 主相机直接读 MainCamera 节点在编辑器里的位姿（所见即所得）
func _setup_cameras() -> void:
	if _main_controller and _main_camera:
		_main_controller.init(_main_camera)
		var fixed := FixedShotBehavior.new()
		fixed.position = _main_camera.global_position
		fixed.look_target = _main_camera.global_position + (-_main_camera.global_basis.z) * 10.0
		_main_controller.push_behavior(fixed)
		CameraSystem.register_main_camera(_main_controller)
		_main_camera.add_to_group("main_camera")
	var viewfinder := get_node_or_null("HUD/MainLayer/CameraViewfinder") as Control
	if viewfinder:
		viewfinder.add_to_group("camera_viewfinder")
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
		if _matches_any(nm, ignore_keywords):
			continue
		if _matches_any(nm, prop_keywords):
			_convert_to_prop(m)
		elif _matches_any(nm, static_keywords):
			_add_static_body(m)

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
	prop.name = "Prop_" + mi.name
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

func _on_level_ready() -> void:
	GameManager.start_game()

func _on_level_battle_ended() -> void:
	Engine.time_scale = 0.5
	_slowmo_end_msec = Time.get_ticks_msec() + SHUTTER_SLOWMO_MS

func _process(_delta: float) -> void:
	if _slowmo_end_msec > 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_slowmo_end_msec = 0
		Engine.time_scale = 1.0

func _on_level_settlement(_results: Dictionary) -> void:
	if _hud:
		_hud.enter_scoring_mode()

func _on_flow_finished(action: String) -> void:
	Engine.time_scale = 1.0
	GameManager.time_rate = 1.0
	if action == "restart":
		get_tree().change_scene_to_file(get_tree().current_scene.scene_file_path)
	else:
		GameManager.enter_lobby()
