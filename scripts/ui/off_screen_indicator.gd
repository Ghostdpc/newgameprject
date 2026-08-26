## 职责：主相机镜头外的玩家 → 屏幕边缘彩色气泡指示
## - 气泡颜色 = 玩家身份色（PlayerConfig）
## - 玩家在镜头内或隐藏（死亡）时不显示

class_name OffScreenIndicator
extends Control

const EDGE_MARGIN := 44.0        # 气泡离屏幕左右边缘留白
const TOP_BOTTOM_MARGIN := 120.0 # 气泡离屏幕上下边缘留白（避开 FilmBorder 上下黑边）
const BUBBLE_SIZE := 30.0        # 气泡直径

## player_index -> 气泡 Control
var _bubbles: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	var camera := _get_main_camera()
	if camera == null or not camera.is_inside_tree() \
			or GameManager.current_stage != GameManager.GameStage.BATTLE:
		_hide_all()
		return
	var vsize := get_viewport().get_visible_rect().size
	for p in get_tree().get_nodes_in_group("players"):
		var player := p as PlayerController
		if player == null:
			continue
		_update_bubble(_get_bubble(player), player, camera, vsize)

func _get_main_camera() -> Camera3D:
	var cams := get_tree().get_nodes_in_group("main_camera")
	if cams.is_empty():
		return null
	return cams[0] as Camera3D

func _get_bubble(player: PlayerController) -> Control:
	if _bubbles.has(player.player_index):
		return _bubbles[player.player_index]
	var bubble := _create_bubble(player.player_index)
	_bubbles[player.player_index] = bubble
	return bubble

func _create_bubble(index: int) -> Control:
	var bubble := Panel.new()
	bubble.name = "OffScreenBubble_%d" % (index + 1)
	bubble.size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color: Color = PlayerConfig.get_color(index)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.9)
	style.border_color = Color.WHITE
	style.set_border_width_all(2)
	style.set_corner_radius_all(BUBBLE_SIZE * 0.5)
	bubble.add_theme_stylebox_override("panel", style)
	add_child(bubble)
	return bubble

func _update_bubble(bubble: Control, player: PlayerController, camera: Camera3D, vsize: Vector2) -> void:
	if not player.visible:
		bubble.hide()
		return
	var world_pos := player.global_position + Vector3(0, 1.0, 0)
	var screen_pos := camera.unproject_position(world_pos)
	var behind := camera.is_position_behind(world_pos)
	if behind:
		# 相机后方的点 unproject 结果被镜像，翻转回正确象限
		screen_pos = vsize - screen_pos
	var on_screen := (not behind
		and screen_pos.x >= EDGE_MARGIN and screen_pos.x <= vsize.x - EDGE_MARGIN
		and screen_pos.y >= TOP_BOTTOM_MARGIN and screen_pos.y <= vsize.y - TOP_BOTTOM_MARGIN)
	if on_screen:
		bubble.hide()
		return
	var clamped := Vector2(
		clampf(screen_pos.x, EDGE_MARGIN, vsize.x - EDGE_MARGIN),
		clampf(screen_pos.y, TOP_BOTTOM_MARGIN, vsize.y - TOP_BOTTOM_MARGIN))
	bubble.position = clamped - Vector2(BUBBLE_SIZE * 0.5, BUBBLE_SIZE * 0.5)
	bubble.show()

func _hide_all() -> void:
	for b in _bubbles.values():
		b.hide()
