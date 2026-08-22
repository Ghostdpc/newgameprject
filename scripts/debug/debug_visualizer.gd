## 職責：開發調試可視化（碰撞體 / 骨骼線 / 角色數據面板），熱鍵 F1/F2/F3 切換
## 碰撞體與骨骼線均自繪並開啟 no_depth_test，穿透模型可見
## F3 數據面板：遍歷所有玩家，實時顯示角色持有道具/速度/狀態等運行時數據

class_name DebugVisualizer
extends Node3D

const DEBUG_BONE_COLOR: Color = Color(0.0, 1.0, 1.0, 1.0)
const DEBUG_COLLISION_COLOR: Color = Color(1.0, 0.6, 0.0, 1.0)
const CAPSULE_SEGMENTS: int = 16
const PANEL_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.72)
const PANEL_WIDTH: int = 260
const PANEL_PADDING: int = 10

var _collisions_on: bool = false
var _bones_on: bool = false
var _data_panel_on: bool = false

var _bone_mesh: MeshInstance3D
var _collision_mesh: MeshInstance3D
var _immediate: ImmediateMesh
var _line_mat: StandardMaterial3D
var _collision_mat: StandardMaterial3D

# F3 數據面板
var _overlay: CanvasLayer
var _panel_root: HBoxContainer

func _ready() -> void:
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = DEBUG_BONE_COLOR
	_line_mat.no_depth_test = true
	_bone_mesh = MeshInstance3D.new()
	_bone_mesh.name = "DebugBoneLines"
	_bone_mesh.mesh = ImmediateMesh.new()
	add_child(_bone_mesh)
	_bone_mesh.visible = false

	_collision_mat = StandardMaterial3D.new()
	_collision_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_collision_mat.albedo_color = DEBUG_COLLISION_COLOR
	_collision_mat.no_depth_test = true
	_collision_mesh = MeshInstance3D.new()
	_collision_mesh.name = "DebugCollisionShapes"
	_collision_mesh.mesh = ImmediateMesh.new()
	add_child(_collision_mesh)
	_collision_mesh.visible = false

	_build_data_overlay()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			_toggle_collisions()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F2:
			_toggle_bones()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F3:
			_toggle_data_panel()
			get_viewport().set_input_as_handled()

func _toggle_collisions() -> void:
	_collisions_on = not _collisions_on
	_collision_mesh.visible = _collisions_on
	print("DebugVisualizer: collisions = ", _collisions_on)

func _toggle_bones() -> void:
	_bones_on = not _bones_on
	_bone_mesh.visible = _bones_on
	print("DebugVisualizer: bones = ", _bones_on)

func _toggle_data_panel() -> void:
	_data_panel_on = not _data_panel_on
	_overlay.visible = _data_panel_on
	print("DebugVisualizer: data_panel = ", _data_panel_on)

func _process(_delta: float) -> void:
	if _bones_on:
		_rebuild_bone_lines()
	if _collisions_on:
		_rebuild_collisions()
	if _data_panel_on:
		_refresh_data_panel()

## 遍歷所有玩家身上的 Skeleton3D 畫骨線（父骨→子骨）
func _rebuild_bone_lines() -> void:
	var imm: ImmediateMesh = _bone_mesh.mesh as ImmediateMesh
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for player in get_tree().get_nodes_in_group("players"):
		var skeletons := _find_all_skeletons(player as Node)
		for skeleton in skeletons:
			var sk := skeleton as Skeleton3D
			if not sk:
				continue
			for i in sk.get_bone_count():
				var parent_idx: int = sk.get_bone_parent(i)
				if parent_idx == -1:
					continue
				var from: Vector3 = sk.global_transform * sk.get_bone_global_pose(parent_idx).origin
				var to: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
				imm.surface_add_vertex(from)
				imm.surface_add_vertex(to)
	imm.surface_end()

## 遍歷所有角色（players 組），只畫角色身上的碰撞體線框
func _rebuild_collisions() -> void:
	var imm: ImmediateMesh = _collision_mesh.mesh as ImmediateMesh
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _collision_mat)
	for player in get_tree().get_nodes_in_group("players"):
		for child in (player as Node).find_children("*", "CollisionShape3D", true, false):
			var cs := child as CollisionShape3D
			if not cs or not cs.shape:
				continue
			var tf := cs.global_transform
			if cs.shape is CapsuleShape3D:
				_draw_capsule(imm, tf, cs.shape as CapsuleShape3D)
			elif cs.shape is BoxShape3D:
				_draw_box(imm, tf, cs.shape as BoxShape3D)
	imm.surface_end()

func _draw_capsule(imm: ImmediateMesh, tf: Transform3D, shape: CapsuleShape3D) -> void:
	var radius: float = shape.radius
	var height: float = shape.height
	var half: float = height * 0.5
	var mid_half: float = half - radius
	# 中段圓柱的上下兩圈
	for ring_y in [mid_half, -mid_half]:
		for i in CAPSULE_SEGMENTS:
			var a0: float = TAU * float(i) / CAPSULE_SEGMENTS
			var a1: float = TAU * float(i + 1) / CAPSULE_SEGMENTS
			imm.surface_add_vertex(tf * Vector3(cos(a0) * radius, ring_y, sin(a0) * radius))
			imm.surface_add_vertex(tf * Vector3(cos(a1) * radius, ring_y, sin(a1) * radius))
	# 兩端半球：沿子午線畫圈
	for i in CAPSULE_SEGMENTS:
		var a: float = TAU * float(i) / CAPSULE_SEGMENTS
		var base: Vector3 = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		# 頂部半球（z 剖面弧）
		imm.surface_add_vertex(tf * (base + Vector3(0, mid_half, 0)))
		imm.surface_add_vertex(tf * (base + Vector3(0, half, 0)))
		# 底部半球
		imm.surface_add_vertex(tf * (base - Vector3(0, mid_half, 0)))
		imm.surface_add_vertex(tf * (base - Vector3(0, half, 0)))
	# 垂直方向連接線（把上下半球的邊緣點連起來，構成網格感）
	for i in CAPSULE_SEGMENTS:
		var a: float = TAU * float(i) / CAPSULE_SEGMENTS
		var dir: Vector3 = Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		imm.surface_add_vertex(tf * (dir + Vector3(0, mid_half, 0)))
		imm.surface_add_vertex(tf * (dir - Vector3(0, mid_half, 0)))

func _draw_box(imm: ImmediateMesh, tf: Transform3D, shape: BoxShape3D) -> void:
	var s: Vector3 = shape.size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-s.x, -s.y, -s.z), Vector3(s.x, -s.y, -s.z),
		Vector3(s.x, -s.y, s.z), Vector3(-s.x, -s.y, s.z),
		Vector3(-s.x, s.y, -s.z), Vector3(s.x, s.y, -s.z),
		Vector3(s.x, s.y, s.z), Vector3(-s.x, s.y, s.z),
	]
	var edges: Array = [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for e in edges:
		imm.surface_add_vertex(tf * corners[e[0]])
		imm.surface_add_vertex(tf * corners[e[1]])

func _find_all_skeletons(n: Node, acc: Array = []) -> Array:
	if n is Skeleton3D:
		acc.append(n)
	for c in n.get_children():
		_find_all_skeletons(c, acc)
	return acc

# ─── F3 數據面板 ─────────────────────────────────────────────────────────────

## 構建 overlay：CanvasLayer → HBoxContainer（每個玩家一個 Panel + Label）
func _build_data_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "DebugDataOverlay"
	_overlay.layer = 128
	_overlay.visible = false
	add_child(_overlay)

	_panel_root = HBoxContainer.new()
	_panel_root.name = "PanelRoot"
	_panel_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel_root.position = Vector2(8.0, 8.0)
	_panel_root.add_theme_constant_override("separation", 8)
	_overlay.add_child(_panel_root)

## 每幀刷新所有玩家數據
func _refresh_data_panel() -> void:
	var players: Array = get_tree().get_nodes_in_group("players")

	# 補齊 / 刪除子面板
	while _panel_root.get_child_count() < players.size():
		_panel_root.add_child(_make_player_panel())
	while _panel_root.get_child_count() > players.size():
		_panel_root.get_child(_panel_root.get_child_count() - 1).queue_free()

	for i in players.size():
		var player := players[i] as PlayerController
		if not player:
			continue
		var label := _panel_root.get_child(i).get_node_or_null("Label") as Label
		if label:
			label.text = _build_player_text(player)

## 組裝單個玩家的文字
func _build_player_text(p: PlayerController) -> String:
	var lines: Array[String] = []
	lines.append("── P%d ──" % (p.player_index + 1))
	lines.append("pos   %s" % _fmt_vec3(p.global_position))
	lines.append("vel   %s" % _fmt_vec3(p.velocity))
	lines.append("floor %s" % str(p.is_on_floor()))

	# 狀態機
	var sm := p.state_machine
	if sm:
		lines.append("state %s" % sm.current_state_name)

	# 道具持有
	var item_txt := p.held_item_id if not p.held_item_id.is_empty() else "none"
	lines.append("item  %s" % item_txt)

	# 布娃娃
	var rag := p.ragdoll_rig
	if rag:
		lines.append("ragdl %s" % str(rag.is_ragdoll_enabled()))

	return "\n".join(lines)

## 建立一個帶背景的 Panel + Label
func _make_player_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.set_content_margin_all(PANEL_PADDING)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	var label := Label.new()
	label.name = "Label"
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 14)
	panel.add_child(label)
	return panel

func _fmt_vec3(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
