## 職責：快門後結算 —— 遮罩占比分析 + 六維評分框架（Demo 版）
##
## 流程：收到 photo_taken(貼圖) → 生成遮罩克隆 → 渲染 ID 遮罩視口 → 像素統計
##       → 計算六維分數 → settlement_completed(results)
##
## 六維（策劃案 10-評分與結算）：入鏡20% / 站位20% / 朝向15% / 遮擋15% / 服裝15% / Pose15%
## Demo 實作：入鏡（投影 bbox 裁切比）、遮擋（可見像素/預期像素）、站位（質心距畫面中心）
## 朝向/服裝/Pose 暫以 0 分佔位（屬 Pose 系統與換裝系統負責人）
## 正式計分演算法由 ScoreSystem 替換（待策劃確認權重與細則）
##
## 遮罩原理：快門瞬間把每個演員的網格克隆成「專屬純色」副本、場景遮擋物克隆成黑色，
## 放入只渲染 MASK_LAYER 的獨立視口重拍一張 → 每個玩家實際可見像素一目了然，
## 遮擋/出框自動成立（同 PhotoParty 原型驗證過的做法）

class_name SettlementSystem
extends Node

signal settlement_completed(results: Dictionary)

const MASK_LAYER: int = 2
const MASK_SIZE := Vector2i(320, 180)
const COLOR_TOLERANCE: float = 0.06      # 顏色匹配容差（sRGB 微偏移防護）
const ACTOR_FILL_FACTOR: float = 0.55    # 角色填充 bbox 的估計比例（膠囊體近似）
const MIN_VISIBLE_PX: int = 20           # 低於此像素視為完全出鏡

const W_FRAMING := 0.20
const W_POSITION := 0.20
const W_FACING := 0.15
const W_OCCLUSION := 0.15
const W_COSTUME := 0.15
const W_POSE := 0.15

var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _clones_root: Node3D
var _busy: bool = false

func _ready() -> void:
	EventBus.photo_taken.connect(_on_photo_taken)
	_build_mask_viewport()

func _build_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "MaskViewport"
	_mask_viewport.size = MASK_SIZE
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# 獨立純黑世界，避免主場景天空/光照污染像素統計
	var world := World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	world.environment = env
	_mask_viewport.world_3d = world
	add_child(_mask_viewport)
	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.cull_mask = MASK_LAYER
	_mask_viewport.add_child(_mask_camera)

func _on_photo_taken(texture: ViewportTexture) -> void:
	if _busy:
		return
	# texture 為 null 時（無真實截圖，如 test scene 直接觸發 battle_ended）
	# 仍繼續結算流程，_analyze_async 內部有空圖兜底
	_busy = true
	_analyze_async(texture)

func _analyze_async(texture: ViewportTexture) -> void:
	var photo_image := texture.get_image()
	if photo_image == null:
		# headless/dummy 渲染器拿不到真实画面，用空图兜底（正式环境不会触发）
		push_warning("SettlementSystem: 截图为空（可能是 headless 渲染），像素分析降级为零")
		photo_image = Image.create_empty(_mask_viewport.size.x, _mask_viewport.size.y, false, Image.FORMAT_RGBA8)

	var cam := _get_photo_camera()
	if cam == null:
		push_warning("SettlementSystem: 找不到攝影相機，無法結算")
		_busy = false
		return

	_spawn_mask_clones()
	_sync_mask_camera(cam)
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var mask_image := _mask_viewport.get_texture().get_image()
	if mask_image == null:
		mask_image = Image.create_empty(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_RGBA8)
	_clear_mask_clones()
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var results := _analyze(photo_image, mask_image, cam)
	_busy = false
	settlement_completed.emit(results)

func _get_photo_camera() -> Camera3D:
	var controller := CameraSystem.get_photo_controller()
	if controller == null or not controller.has_method("get_camera"):
		return null
	return controller.get_camera()

## ---- 遮罩克隆 ----

func _spawn_mask_clones() -> void:
	_clones_root = Node3D.new()
	_clones_root.name = "MaskClones"
	add_child(_clones_root)
	var actor_set: Dictionary = {}
	for actor in get_tree().get_nodes_in_group("settlement_actor"):
		if not (actor is Node3D):
			continue
		actor_set[actor] = true
		var color: Color = actor.player_color if "player_color" in actor else Color.WHITE
		_clone_meshes(actor as Node3D, _flat_material(color))
	for occ in get_tree().get_nodes_in_group("photo_occluder"):
		if actor_set.has(occ) or not (occ is Node3D):
			continue
		_clone_meshes(occ as Node3D, _flat_material(Color.BLACK))

func _clone_meshes(source: Node3D, mat: StandardMaterial3D) -> void:
	for mi in _collect_meshes(source):
		if mi.mesh == null:
			continue
		var clone := MeshInstance3D.new()
		clone.mesh = mi.mesh
		clone.material_override = mat
		clone.layers = MASK_LAYER
		clone.global_transform = mi.global_transform
		_clones_root.add_child(clone)

func _clear_mask_clones() -> void:
	if _clones_root:
		_clones_root.queue_free()
		_clones_root = null

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

func _sync_mask_camera(photo_cam: Camera3D) -> void:
	_mask_camera.global_transform = photo_cam.global_transform
	_mask_camera.fov = photo_cam.fov
	_mask_camera.near = photo_cam.near
	_mask_camera.far = photo_cam.far

## ---- 計分 ----

func _analyze(photo: Image, mask: Image, cam: Camera3D) -> Dictionary:
	var actors := get_tree().get_nodes_in_group("settlement_actor")
	var vp_size := Vector2(_mask_viewport.size)
	var total_px: int = _mask_viewport.size.x * _mask_viewport.size.y
	var frame := Rect2(Vector2.ZERO, vp_size)

	# 像素統計：按演員顏色匹配
	var counts := {}
	var targets := {}
	for actor in actors:
		var color: Color = actor.player_color if "player_color" in actor else Color.WHITE
		counts[actor] = 0
		targets[actor] = color
	var w := _mask_viewport.size.x
	var h := _mask_viewport.size.y
	for y in h:
		for x in w:
			var c := mask.get_pixel(x, y)
			for actor in targets:
				var t: Color = targets[actor]
				if absf(c.r - t.r) <= COLOR_TOLERANCE and absf(c.g - t.g) <= COLOR_TOLERANCE and absf(c.b - t.b) <= COLOR_TOLERANCE:
					counts[actor] += 1
					break

	# 逐演員六維計算
	var actor_results: Array = []
	for actor in actors:
		var idx: int = actor.player_index if "player_index" in actor else -1
		var color: Color = actor.player_color if "player_color" in actor else Color.WHITE
		var visible_px: int = counts[actor]
		var aabb_world := _actor_world_aabb(actor as Node3D)
		var bbox := _project_aabb(cam, aabb_world, vp_size)
		var clipped := bbox.intersection(frame)
		var bbox_area: float = bbox.get_area()
		var framing: float = 0.0
		if bbox_area > 1.0:
			framing = clampf(clipped.get_area() / bbox_area, 0.0, 1.0)
		var behind: bool = cam.is_position_behind(aabb_world.get_center())
		if behind:
			framing = 0.0
		var position_score: float = 0.0
		if not behind:
			var centroid: Vector2 = cam.unproject_position(aabb_world.get_center())
			var dist: float = (centroid - vp_size * 0.5).length()
			position_score = clampf(1.0 - dist / (vp_size.length() * 0.5), 0.0, 1.0)
		var expected_px: float = clipped.get_area() * ACTOR_FILL_FACTOR
		var occlusion: float = 0.0
		if expected_px > 1.0:
			occlusion = clampf(float(visible_px) / expected_px, 0.0, 1.0)
		var in_photo: bool = visible_px >= MIN_VISIBLE_PX

		# 六維明細（0~100），朝向/服裝/Pose 佔位
		var dim := {
			"framing": {"label": "入鏡完整度", "norm": framing if in_photo else 0.0, "weight": W_FRAMING},
			"position": {"label": "站位優勢", "norm": position_score if in_photo else 0.0, "weight": W_POSITION},
			"facing": {"label": "鏡頭朝向", "norm": 0.0, "weight": W_FACING, "tbd": true},
			"occlusion": {"label": "清晰度(遮擋)", "norm": occlusion if in_photo else 0.0, "weight": W_OCCLUSION},
			"costume": {"label": "服裝表現", "norm": 0.0, "weight": W_COSTUME, "tbd": true},
			"pose": {"label": "Pose表現", "norm": 0.0, "weight": W_POSE, "tbd": true},
		}
		var total: float = 0.0
		for key in dim:
			var d: Dictionary = dim[key]
			d["score"] = d["norm"] * d["weight"] * 100.0
			total += d["score"]
		actor_results.append({
			"player_index": idx,
			"color": color,
			"in_photo": in_photo,
			"visible_px": visible_px,
			"percent": float(visible_px) / float(total_px),
			"dimensions": dim,
			"total": total,
		})
	actor_results.sort_custom(func(a, b): return a["total"] > b["total"])

	return {
		"photo": photo,
		"mask": mask,
		"actors": actor_results,
		"resolution": vp_size,
	}

func _actor_world_aabb(actor: Node3D) -> AABB:
	var result := AABB()
	var has := false
	for mi in _collect_meshes(actor):
		if mi.mesh == null:
			continue
		var local_aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		if not has:
			result = local_aabb
			has = true
		else:
			result = result.merge(local_aabb)
	if not has:
		result = AABB(actor.global_position, Vector3(0.8, 1.8, 0.8))
	return result

func _project_aabb(cam: Camera3D, aabb: AABB, vp_size: Vector2) -> Rect2:
	var min_v := Vector2.ONE * 1e9
	var max_v := Vector2.ONE * -1e9
	var any_front := false
	for i in 8:
		var corner := Vector3(
			aabb.position.x if (i & 1) == 0 else aabb.end.x,
			aabb.position.y if (i & 2) == 0 else aabb.end.y,
			aabb.position.z if (i & 4) == 0 else aabb.end.z)
		if cam.is_position_behind(corner):
			continue
		any_front = true
		var p: Vector2 = cam.unproject_position(corner)
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	if not any_front:
		return Rect2()
	min_v = min_v.clamp(Vector2(-vp_size.x, -vp_size.y), vp_size * 2.0)
	max_v = max_v.clamp(Vector2(-vp_size.x, -vp_size.y), vp_size * 2.0)
	return Rect2(min_v, max_v - min_v)

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
