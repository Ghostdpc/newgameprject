## 职责：快门后结算 —— visibility layer override + 四维评分
##
## 流程：收到 photo_taken(贴图) → 给演员 mesh 追加 layer 2 + ID 材质
##       → MaskCamera（共享主场景 world）渲一帧 → 像素统计
##       → ScoreAnalyzer 四维评分 → settlement_completed(results)
##
## 四维（docs/dev/scoring_system_design.md）：画面比例 25% / C位 25% / 服装 25% / 朝向 25%
## 各维绝对分（0~1，不做玩家间归一），加权和 ×100 得 0~100 总分。
##
## 遮罩原理（docs/dev/scoring_mask_fix_design.md §二）：
##   MaskViewport 共享主场景 world_3d（不设独立 world）→ 主场景几何继续写深度缓冲。
##   MaskCamera.cull_mask = layer 2 only → 只看演员 ID 色输出到颜色缓冲。
##   被场景物体/其他演员挡住的片段被 GPU z-test 自然剔除。
##   解决：T-pose（演员 mesh 在原位，骨骼动画照常驱动）+ 遮挡（深度共享）。

class_name SettlementSystem
extends Node

signal settlement_completed(results: Dictionary)

const ScoreAnalyzerScript := preload("res://scripts/systems/score_analyzer.gd")

const MASK_LAYER: int   = 2
const MASK_LAYER_BIT: int = 1 << (MASK_LAYER - 1)   # bit 1 = layer 2
const MASK_SIZE := Vector2i(640, 360)

## 四玩家 ID 色（纯饱和原色，与 PlayerConfig 实际色不同，避免混淆）
## 从 score_config.json["id_colors"] 加载；此为默认值
const DEFAULT_ID_COLORS: Array = [
	[1.0, 0.0, 0.0],   # P1 红
	[0.0, 1.0, 0.0],   # P2 绿
	[0.0, 0.0, 1.0],   # P3 蓝
	[1.0, 1.0, 0.0],   # P4 黄
]

var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _mask_env: Environment
var _busy: bool = false
var _score_config: Dictionary = {}
var _id_materials: Array = []   # Array[StandardMaterial3D]，按 player_index 索引
var _suspended_effects: Array = []   # 掩码渲染期间挂起处理的 CharacterEffects
var _main_cull_saved: Array = []     # 掩码渲染期间临时排除 MASK 层的主相机 cull_mask

func _ready() -> void:
	# 联机：结算只在 host 执行（mask 渲染读 host 真实场景），client 收广播结果
	if NetManager.is_online and not NetManager.is_host:
		return
	EventBus.photo_taken.connect(_on_photo_taken)
	_score_config = ConfigLoader.load_config("score_config")
	_build_mask_viewport()
	_build_id_materials()

## ---- 初始化 ----

func _build_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "MaskViewport"
	_mask_viewport.size = MASK_SIZE
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask_viewport.msaa_3d = Viewport.MSAA_DISABLED
	# 不设 world_3d，继承主场景 → 主场景几何参与深度测试（解决遮挡问题）
	add_child(_mask_viewport)
	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	# layer 1（bit 0）= 场景几何，参与深度测试提供遮挡；layer 2（bit 1）= 演员 ID 色输出
	# 场景物体颜色不匹配任何 ID 色，不影响像素统计
	_mask_camera.cull_mask = 1 | MASK_LAYER_BIT
	_mask_camera.current = true
	# 关键：给掩码相机一套干净 Environment，覆盖世界环境的 tonemap/glow/adjustment。
	# 否则主场景 WorldEnvironment（Filmic tonemap + 去饱和 + glow）会把纯 ID 色偏移，
	# 使 _match_actor 全部失配 → 掩码「看不到」玩家 → ratio/center 算不出。
	_build_mask_env()
	_mask_camera.environment = _mask_env
	_mask_viewport.add_child(_mask_camera)

## 干净掩码环境：线性 tonemap、无 glow/adjustment/ssao、纯黑背景。
## unshaded ID 色原样输出（纯原色在 sRGB/linear 下不变），背景/天空为 0。
func _build_mask_env() -> void:
	_mask_env = Environment.new()
	_mask_env.background_mode = Environment.BG_COLOR
	_mask_env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	_mask_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_mask_env.ambient_light_color = Color.WHITE
	_mask_env.ambient_light_energy = 1.0
	_mask_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

func _build_id_materials() -> void:
	_id_materials.clear()
	var raw_colors: Array = _score_config.get("id_colors", DEFAULT_ID_COLORS)
	for i in 4:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if i < raw_colors.size():
			var c = raw_colors[i]
			mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
		else:
			mat.albedo_color = Color.WHITE
		_id_materials.append(mat)

## ---- 主流程 ----

func _on_photo_taken(texture: ViewportTexture) -> void:
	if _busy:
		return
	_busy = true
	_analyze_async(texture)

func _analyze_async(texture: ViewportTexture) -> void:
	# 拍照瞬间请求高分辨率重渲一帧（演员此刻仍为正常材质，尚未套 ID 掩码）；
	# 失败则回退到当前实时预览贴图（低分）。
	var photo_image: Image = null
	var controller := CameraSystem.get_photo_controller()
	if controller != null and controller.has_method("capture_high_res"):
		photo_image = await controller.capture_high_res()
	if photo_image == null:
		photo_image = _photo_or_empty(texture)

	# 实拍照片完成：服装等演出道具可安全清空（评分读的是数据层，不依赖 mesh）
	EventBus.photo_captured.emit()

	_save_photo_png(photo_image)

	# 联机：拍照完成立即把照片同步给 client（分数未出，只先展示照片），
	# 不等 mask/分析完成，避免 client 一直等到结算分析全部跑完。
	var round := -1
	if NetManager.is_online and NetManager.is_host:
		round = NetManager.next_settlement_round()
		NetManager.broadcast_settlement_preview(photo_image, round)

	var cam := _get_photo_camera()
	if cam == null:
		push_warning("SettlementSystem: 找不到摄影相机，无法结算")
		_busy = false
		return

	# 按 player_index 分配 ID 材质
	var actors := _get_actors()
	var override_table := _apply_id_overrides(actors)

	# 隔离主画面：演员 mesh 已被改为「只在 MASK 层」，再让主相机排除 MASK 层，
	# 则主相机既不渲染带 ID 材质的演员（不会变纯色），也不会误显示 MASK。
	# 演员在主画面短暂不绘制（被快门白闪盖住），远好于闪现纯色。
	_hide_mask_layer_from_main()

	# 冻结 PhotoViewport：照片相机 cull_mask=1 已排除 MASK 层（此刻演员只在 MASK 层，
	# 不冻结会渲成「没有演员的场景」）。冻结后照片 RT 保持快门那帧的干净画面。
	var photo_vp := _get_photo_viewport() as SubViewport
	var prev_photo_mode: int = -1
	if photo_vp != null:
		prev_photo_mode = photo_vp.render_target_update_mode
		photo_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_sync_mask_camera(cam)
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	var mask_image := _mask_viewport.get_texture().get_image()
	if mask_image == null:
		mask_image = Image.create_empty(_mask_viewport.size.x, _mask_viewport.size.y, false, Image.FORMAT_RGBA8)
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_revert_id_overrides(override_table)
	_restore_main_cull()

	# 还原 PhotoViewport 更新模式（override 已撤销，恢复渲染的是干净照片）
	if photo_vp != null and prev_photo_mode >= 0:
		photo_vp.render_target_update_mode = prev_photo_mode

	var results := _analyze(photo_image, mask_image, cam, actors)
	if round > 0:
		results["round"] = round
	_busy = false
	settlement_completed.emit(results)

## ---- ID 材质 override ----

## 给所有演员 mesh 设为「只在 MASK 层」 + ID 材质。
## 返回 override_table：Array[{mi, orig_layers, orig_override}]，还原用。
##
## 关键：设为 MASK-only（移除原 layer1）——配合主相机排除 MASK 层，
## 主画面就不会渲染这些带 ID 材质的 mesh（不会闪现纯色）；MaskCamera 仍渲染它们。
##
## 注意：CharacterEffects._process 每帧把身体 mesh 的 material_override 重写成玩家 tint 色，
## 会在掩码渲染的 await 帧里覆盖掉 ID 材质 → 掩码变真实色 → 颜色匹配失败。
## 因此染色前挂起演员的 CharacterEffects 处理，还原时恢复。
func _apply_id_overrides(actors: Array) -> Array:
	var table: Array = []
	_suspended_effects.clear()
	for actor in actors:
		var node := actor as Node3D
		if node == null:
			continue
		_suspend_material_writers(node)
		var idx: int = clampi(int(actor.player_index) if "player_index" in actor else 0, 0, _id_materials.size() - 1)
		var mat: StandardMaterial3D = _id_materials[idx]
		for mi in _collect_meshes(node):
			table.append({
				"mi": mi,
				"orig_layers": mi.layers,
				"orig_override": mi.material_override,
			})
			mi.layers = MASK_LAYER_BIT   # 只在 MASK 层，主/照片相机（不含 MASK）不渲染
			mi.material_override = mat
	return table

## 还原所有被修改的 mesh 的 layers 和 material_override，并恢复被挂起的效果组件
func _revert_id_overrides(table: Array) -> void:
	for entry in table:
		var mi = entry["mi"]
		if is_instance_valid(mi):
			mi.layers = entry["orig_layers"]
			mi.material_override = entry["orig_override"]
	for fx in _suspended_effects:
		if is_instance_valid(fx):
			fx.set_process(true)
	_suspended_effects.clear()

## 挂起会每帧重写 material_override 的组件（CharacterEffects），避免覆盖 ID 材质
func _suspend_material_writers(actor: Node3D) -> void:
	var fx := actor.get_node_or_null("CharacterEffects")
	if fx != null and fx.is_processing():
		fx.set_process(false)
		_suspended_effects.append(fx)

## 掩码渲染期间让主相机排除 MASK 层：演员（此刻只在 MASK 层）不会显示在主画面上，
## 避免快门瞬间人物闪现纯 ID 色。渲完 _restore_main_cull 还原。
func _hide_mask_layer_from_main() -> void:
	_main_cull_saved.clear()
	for cam in get_tree().get_nodes_in_group("main_camera"):
		if cam is Camera3D:
			_main_cull_saved.append({"cam": cam, "cull": (cam as Camera3D).cull_mask})
			(cam as Camera3D).cull_mask &= ~MASK_LAYER_BIT

func _restore_main_cull() -> void:
	for e in _main_cull_saved:
		var cam: Camera3D = e["cam"]
		if is_instance_valid(cam):
			cam.cull_mask = e["cull"]
	_main_cull_saved.clear()

## ---- 工具 ----

func _get_actors() -> Array:
	var result: Array = []
	for actor in get_tree().get_nodes_in_group("settlement_actor"):
		if actor is Node3D and actor.is_in_group("players"):
			result.append(actor)
	return result

func _photo_or_empty(texture: ViewportTexture) -> Image:
	if texture == null:
		return Image.create_empty(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_RGBA8)
	var img := texture.get_image()
	if img == null:
		push_warning("SettlementSystem: 截图为空（headless 渲染降级为零）")
		return Image.create_empty(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_RGBA8)
	return img

## 每轮结束把拍照照片落地为 png（user://photos/ 目录）
func _save_photo_png(img: Image) -> void:
	if img == null or img.is_empty():
		return
	var dir := "user://photos"
	var d := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if d != OK and d != ERR_ALREADY_EXISTS:
		push_warning("SettlementSystem: 创建 %s 失败（err=%d）" % [dir, d])
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/photo_%s.png" % [dir, stamp]
	var err := img.save_png(path)
	if err == OK:
		print("SettlementSystem: 照片已保存 %s" % ProjectSettings.globalize_path(path))
	else:
		push_warning("SettlementSystem: 照片保存失败（err=%d）" % err)

func _get_photo_camera() -> Camera3D:
	var controller := CameraSystem.get_photo_controller()
	if controller == null or not controller.has_method("get_camera"):
		return null
	return controller.get_camera()

## 掩码相机完全对齐拍照相机：位姿 + 投影（FRUSTUM/frustum_offset/size/keep_aspect）
## + 视口分辨率。只复制 transform/fov 不够——PhotoCamera 用 PROJECTION_FRUSTUM
## 裁到取景框，漏掉这些参数会导致掩码取景与照片完全对不上。
func _sync_mask_camera(photo_cam: Camera3D) -> void:
	_mask_camera.global_transform = photo_cam.global_transform
	_mask_camera.projection = photo_cam.projection
	_mask_camera.keep_aspect = photo_cam.keep_aspect
	_mask_camera.fov = photo_cam.fov
	_mask_camera.size = photo_cam.size
	_mask_camera.frustum_offset = photo_cam.frustum_offset
	_mask_camera.near = photo_cam.near
	_mask_camera.far = photo_cam.far
	# 视口分辨率必须与拍照取景一致（同宽高比），否则 KEEP_HEIGHT 下水平视野不同 → 取景错位。
	# 优先用取景框原始像素（get_frame_size），使掩码精度不受预览降分辨率影响；
	# 回退到 PhotoViewport 当前尺寸。
	var mask_size := Vector2i.ZERO
	var controller := CameraSystem.get_photo_controller()
	if controller != null and controller.has_method("get_frame_size"):
		mask_size = controller.get_frame_size()
	if mask_size.x <= 0 or mask_size.y <= 0:
		var photo_vp := _get_photo_viewport()
		if photo_vp != null:
			mask_size = photo_vp.size
	if mask_size.x > 0 and mask_size.y > 0:
		_mask_viewport.size = mask_size

func _get_photo_viewport() -> Viewport:
	var controller := CameraSystem.get_photo_controller()
	if controller == null or not controller.has_method("get_render_viewport"):
		return null
	return controller.get_render_viewport()

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

## ---- 计分 ----

func _analyze(photo: Image, mask: Image, cam: Camera3D, actors: Array) -> Dictionary:
	var meta: Array = []
	for actor in actors:
		var node := actor as Node3D
		var idx: int = actor.player_index if "player_index" in actor else -1
		var id_color: Color = _id_color_for(idx)
		meta.append({
			"player_index": idx,
			"color": id_color,
			"facing": _compute_facing(node, cam),
			"outfit": _read_outfit_norm(node),
			"penalty": actor.score_penalty if "score_penalty" in actor else 0,
		})

	var analyzer = ScoreAnalyzerScript.new()
	analyzer.weights = _score_config.get("weights", analyzer.weights)
	analyzer.center_falloff = String(_score_config.get("center_falloff", "linear"))
	analyzer.falloff_k = float(_score_config.get("falloff_k", 4.0))
	analyzer.color_tolerance = float(_score_config.get("color_tolerance", 0.06))
	analyzer.min_visible_px = int(_score_config.get("min_visible_px", 20))

	# 掩码尺寸以实际图像为准（视口分辨率已对齐 PhotoViewport）
	var size: Vector2i = mask.get_size()
	var results := analyzer.analyze(mask, meta, size)
	results["photo"] = photo
	results["mask"] = mask
	return results

## 按 player_index 取对应 ID 色（用于像素匹配）
func _id_color_for(player_index: int) -> Color:
	var idx := clampi(player_index, 0, _id_materials.size() - 1)
	if idx < _id_materials.size():
		return (_id_materials[idx] as StandardMaterial3D).albedo_color
	return Color.WHITE

func _compute_facing(actor: Node3D, cam: Camera3D) -> float:
	var forward := actor.global_basis.z
	var to_cam := cam.global_position - actor.global_position
	return ScoreAnalyzerScript.compute_facing(forward, to_cam)

func _read_outfit_norm(actor: Node3D) -> float:
	# 优先从 GarmentSystem 读取（服装系统接入后的标准路径）
	if actor is PlayerController:
		return GarmentSystem.get_equipped_score(actor as PlayerController)
	# 降级兼容：OutfitManager 件数 × 固定分值（服装系统未接入时）
	var om := actor.get_node_or_null("OutfitManager")
	if om == null or not om.has_method("equipped_slot_count"):
		return 0.0
	var count: int = om.equipped_slot_count()
	var cfg := ConfigLoader.load_config("outfit_scoring")
	var per_slot: float = float(cfg.get("base_per_slot", 0.33))
	var cap: float = float(cfg.get("cap", 1.0))
	var bonuses: Dictionary = cfg.get("item_bonuses", {})

	var raw := float(count) * per_slot
	if om.has_method("get_equipped_ids"):
		for id in (om.get_equipped_ids() as Dictionary).values():
			raw += float(bonuses.get(String(id), 0.0))
	raw = clampf(raw, 0.0, cap)
	if cap <= 0.0:
		return 0.0
	return raw / cap
