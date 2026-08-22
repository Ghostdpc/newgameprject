## 职责：服装拾取反馈气泡（交互文档 §8 头顶拾取气泡）
## - 装备服装时，玩家头顶浮现「泡泡+图标」气泡（沿用玩家卡泡泡视觉语言）
## - 泡泡染玩家身份色（card_tint 保明度染色），图标居中
## - 演出：弹入(0.18s) → 停留跟随 → 上浮+淡出；总时长 2.5s
## - 连续拾取时旧气泡立即替换；玩家在镜头外/隐藏时不显示
## - 道具拾取图标已改由 PlayerHeadIcon 单独显示，此处不再响应 item_picked_up

class_name PickupBubbles
extends Control

const TINT_SHADER := preload("res://resources/ui/card_tint.gdshader")

const BUBBLE_SIZE := 96.0        # 泡泡边长
const ICON_SIZE := 52.0          # 图标边长
const HEAD_OFFSET := Vector3(0.0, 1.7, 0.0)
const LIFE_TOTAL := 2.0          # 总时长
const LIFE_FLOAT := 0.7          # 开始上浮的时间点
const FLOAT_PX := 70.0           # 上浮距离

## player_index -> 当前气泡数据 { root, player, age, visible_ok, tint_mat }
var _active: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.outfit_changed.connect(_on_outfit_changed)

# ---------------------------------------------------------------- 事件
func _on_outfit_changed(player_index: int, _slot: int, item_id: String) -> void:
	if not _stage_ok() or item_id == "":
		return
	_spawn(player_index, _load_icon(item_id))

func _stage_ok() -> bool:
	var s := GameManager.current_stage
	return s == GameManager.GameStage.BATTLE or s == GameManager.GameStage.GRAB_CLOTHES

## 图标映射：服装 id 直查 ItemIcons；道具 id 走 ItemConfig 的 icon key
func _load_icon(item_id: String) -> Texture2D:
	var tex := ItemIcons.load_icon(item_id)
	if tex:
		return tex
	var icon_key: String = ItemSystem._item_config.get_item_icon(item_id)
	if icon_key != "":
		return ItemIcons.load_icon(icon_key)
	return null

# ---------------------------------------------------------------- 生成/替换
func _spawn(player_index: int, icon: Texture2D) -> void:
	var player := _get_player(player_index)
	if player == null:
		return
	# 连续拾取：旧气泡立即替换
	if _active.has(player_index):
		var old: Node = _active[player_index]["root"]
		old.queue_free()
		_active.erase(player_index)

	var root := Control.new()
	root.name = "PickupBubble_P%d" % (player_index + 1)
	root.size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 10

	var bubble := TextureRect.new()
	bubble.texture = ItemIcons.load_icon("card_bubble")
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	bubble.size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = TINT_SHADER
	mat.set_shader_parameter("tint", PlayerConfig.get_color(player_index))
	bubble.material = mat
	root.add_child(bubble)

	if icon:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 泡泡内圆中心略偏上（尾巴在下方）
		icon_rect.position = Vector2(
			(BUBBLE_SIZE - ICON_SIZE) * 0.5,
			(BUBBLE_SIZE - ICON_SIZE) * 0.5 - BUBBLE_SIZE * 0.06)
		icon_rect.size = Vector2(ICON_SIZE, ICON_SIZE)
		root.add_child(icon_rect)

	# 弹入：以底部为轴心从 0.4 放大
	root.pivot_offset = Vector2(BUBBLE_SIZE * 0.5, BUBBLE_SIZE * 0.9)
	root.scale = Vector2(0.4, 0.4)
	root.modulate.a = 0.0
	add_child(root)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 1.0, 0.1)

	_active[player_index] = { "root": root, "player": player, "age": 0.0, "bubble": bubble }

func _get_player(player_index: int) -> PlayerController:
	for p in get_tree().get_nodes_in_group("players"):
		var pc := p as PlayerController
		if pc and pc.player_index == player_index:
			return pc
	return null

# ---------------------------------------------------------------- 跟随/演出
func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var camera := _get_main_camera()
	var vsize := get_viewport().get_visible_rect().size
	for idx in _active.keys():
		var data: Dictionary = _active[idx]
		var root: Control = data["root"]
		if not is_instance_valid(root):
			_active.erase(idx)
			continue
		data["age"] += delta
		var age: float = data["age"]
		# 到期回收
		if age >= LIFE_TOTAL:
			root.queue_free()
			_active.erase(idx)
			continue
		# 上浮 + 淡出段
		if age > LIFE_FLOAT:
			var t := (age - LIFE_FLOAT) / (LIFE_TOTAL - LIFE_FLOAT)
			root.position.y -= FLOAT_PX * delta / (LIFE_TOTAL - LIFE_FLOAT)
			root.modulate.a = 1.0 - t
		# 世界 → 屏幕跟随
		var player: PlayerController = data["player"]
		if camera == null or not is_instance_valid(player) or not player.visible:
			root.hide()
			continue
		var world_pos := player.global_position + HEAD_OFFSET
		if camera.is_position_behind(world_pos):
			root.hide()
			continue
		var sp := camera.unproject_position(world_pos)
		if sp.x < -BUBBLE_SIZE or sp.x > vsize.x + BUBBLE_SIZE \
				or sp.y < -BUBBLE_SIZE or sp.y > vsize.y + BUBBLE_SIZE:
			root.hide()
			continue
		root.show()
		root.position.x = sp.x - BUBBLE_SIZE * 0.5
		# 上浮段不重置 y 基准：未上浮时锚定头顶
		if age <= LIFE_FLOAT:
			root.position.y = sp.y - BUBBLE_SIZE * 0.95
		# 尾巴朝向角色：角色在屏幕右半时水平镜像（默认尾巴右下）
		var bub: TextureRect = data["bubble"]
		if bub:
			bub.flip_h = sp.x > vsize.x * 0.5

func _get_main_camera() -> Camera3D:
	var cams := get_tree().get_nodes_in_group("main_camera")
	if cams.is_empty():
		return null
	return cams[0] as Camera3D
