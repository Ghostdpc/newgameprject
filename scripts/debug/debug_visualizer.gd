## 職責：開發調試可視化（碰撞體 / 骨骼線 / 角色數據面板），熱鍵 F1/F2/F3 切換
## 碰撞體與骨骼線均自繪並開啟 no_depth_test，穿透模型可見
## F3 數據面板：遍歷所有玩家，實時顯示角色持有道具/速度/狀態等運行時數據
## F4 暫停/恢復倒計時（凍結結算用）
## F5 對 P1 注入道具並立即使用（測試道具效果用）
## F6 打開/關閉道具調試列表（點擊道具名立即對 P1 觸發效果）
## F7 清除場上全部陷阱，在 P1 腳下强制生成一個香蕉皮（視覺排查用）

class_name DebugVisualizer
extends Node3D

const DEBUG_BONE_COLOR: Color = Color(0.0, 1.0, 1.0, 1.0)
const DEBUG_COLLISION_COLOR: Color = Color(1.0, 0.6, 0.0, 1.0)
const CAPSULE_SEGMENTS: int = 16
const PANEL_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.72)
const PANEL_WIDTH: int = 260
const PANEL_PADDING: int = 10

## F1 碰撞體三態循環：0=關 → 1=僅玩家 → 2=全部(含場景/道具) → 0
enum CollisionShow { OFF, PLAYERS, ALL }
var _collision_show: CollisionShow = CollisionShow.OFF
var _bones_on: bool = false
var _data_panel_on: bool = false
var _timer_paused: bool = false
var _item_list_on: bool = false

## F5 循環注入的道具 id 列表（按順序循環）
const DEBUG_ITEM_CYCLE: Array[String] = [
	"energy_drink",
	"banana_peel",
	"fast_forward_crank",
	"slow_hourglass",
	"time_battery",
	"time_scissors",
	"camera_remote",
]
var _debug_item_index: int = 0

var _bone_mesh: MeshInstance3D
var _collision_mesh: MeshInstance3D
var _immediate: ImmediateMesh
var _line_mat: StandardMaterial3D
var _collision_mat: StandardMaterial3D

# F3 數據面板
var _overlay: CanvasLayer
var _panel_root: HBoxContainer

# F6 道具調試列表
var _item_list_overlay: CanvasLayer
var _item_list_panel: VBoxContainer

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
	_build_item_list_overlay()

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
		elif event.physical_keycode == KEY_F4:
			_toggle_timer_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F5:
			_inject_item_to_p1()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F6:
			_toggle_item_list()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F7:
			_force_respawn_banana()
			get_viewport().set_input_as_handled()

func _toggle_collisions() -> void:
	_collision_show = (_collision_show + 1) % 3
	_collision_mesh.visible = _collision_show != CollisionShow.OFF
	print("DebugVisualizer: collisions = ", _collision_show)

func _toggle_bones() -> void:
	_bones_on = not _bones_on
	_bone_mesh.visible = _bones_on
	print("DebugVisualizer: bones = ", _bones_on)

func _toggle_data_panel() -> void:
	_data_panel_on = not _data_panel_on
	_overlay.visible = _data_panel_on
	print("DebugVisualizer: data_panel = ", _data_panel_on)

## F4：暫停 / 恢復倒計時（凍結結算用）
func _toggle_timer_pause() -> void:
	_timer_paused = not _timer_paused
	# time_scale = 0 凍結，1 恢復；不觸碰 stage_time_remaining 值
	GameManager.time_scale = 0.0 if _timer_paused else 1.0
	print("DebugVisualizer: timer_paused = ", _timer_paused,
		"  (time_scale = ", GameManager.time_scale, ")")

## F5：對 P1 注入下一個道具並立即使用
func _inject_item_to_p1() -> void:
	var players: Array = get_tree().get_nodes_in_group("players")
	var p1: PlayerController = null
	for node in players:
		var pc := node as PlayerController
		if pc and pc.player_index == 0:
			p1 = pc
			break
	if p1 == null:
		push_warning("DebugVisualizer: P1 not found")
		return
	var item_id: String = DEBUG_ITEM_CYCLE[_debug_item_index % DEBUG_ITEM_CYCLE.size()]
	_debug_item_index += 1
	p1.held_item_id = item_id
	p1.use_held_item()
	print("DebugVisualizer: injected item '%s' to P1" % item_id)

func _process(_delta: float) -> void:
	if _bones_on:
		_rebuild_bone_lines()
	if _collision_show != CollisionShow.OFF:
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

## 畫碰撞體線框：PLAYERS=只角色，ALL=整棵樹全部（含場景靜態體/道具）
func _rebuild_collisions() -> void:
	var imm: ImmediateMesh = _collision_mesh.mesh as ImmediateMesh
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES, _collision_mat)
	if _collision_show == CollisionShow.ALL:
		for child in get_tree().root.find_children("*", "CollisionShape3D", true, false):
			_draw_shape(imm, child as CollisionShape3D)
	else:
		for player in get_tree().get_nodes_in_group("players"):
			for child in (player as Node).find_children("*", "CollisionShape3D", true, false):
				_draw_shape(imm, child as CollisionShape3D)
	imm.surface_end()

func _draw_shape(imm: ImmediateMesh, cs: CollisionShape3D) -> void:
	if not cs or not cs.shape:
		return
	var tf := cs.global_transform
	if cs.shape is CapsuleShape3D:
		_draw_capsule(imm, tf, cs.shape as CapsuleShape3D)
	elif cs.shape is BoxShape3D:
		_draw_box(imm, tf, cs.shape as BoxShape3D)

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

# ─── F6 道具調試列表 ──────────────────────────────────────────────────────────

func _build_item_list_overlay() -> void:
	_item_list_overlay = CanvasLayer.new()
	_item_list_overlay.name = "DebugItemListOverlay"
	_item_list_overlay.layer = 129
	_item_list_overlay.visible = false
	add_child(_item_list_overlay)

	var bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	style.set_content_margin_all(12)
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bg.position = Vector2(-220.0, 8.0)
	_item_list_overlay.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	bg.add_child(vbox)
	_item_list_panel = vbox

	var title := Label.new()
	title.text = "── 道具調試 [F6] ──"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	for item_id in DEBUG_ITEM_CYCLE:
		var btn := Button.new()
		btn.text = item_id
		btn.custom_minimum_size = Vector2(180.0, 32.0)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_debug_item_btn.bind(item_id))
		vbox.add_child(btn)

func _toggle_item_list() -> void:
	_item_list_on = not _item_list_on
	_item_list_overlay.visible = _item_list_on
	print("DebugVisualizer: item_list = ", _item_list_on)

func _on_debug_item_btn(item_id: String) -> void:
	var players: Array = get_tree().get_nodes_in_group("players")
	var p1: PlayerController = null
	for node in players:
		var pc := node as PlayerController
		if pc and pc.player_index == 0:
			p1 = pc
			break
	if p1 == null:
		push_warning("DebugVisualizer: P1 not found")
		return
	p1.held_item_id = item_id
	p1.use_held_item()
	print("DebugVisualizer: [F6 list] used item '%s' on P1" % item_id)

# ─── F7 強制刷新香蕉皮 ───────────────────────────────────────────────────────

## F7：清除場上所有陷阱，在 P1 腳下重新生成一個香蕉皮（視覺排查用）
func _force_respawn_banana() -> void:
	# 1. 清除所有現有陷阱
	for node in get_tree().get_nodes_in_group("traps"):
		node.queue_free()
	# 2. 找 P1
	var p1: PlayerController = null
	for node in get_tree().get_nodes_in_group("players"):
		var pc := node as PlayerController
		if pc and pc.player_index == 0:
			p1 = pc
			break
	if p1 == null:
		push_warning("DebugVisualizer F7: P1 not found")
		return
	# 3. 直接構建 TrapInstance 並放在 P1 前方 1m 處（y 貼地）
	var trap_def: TrapDef = ItemSystem._item_config.get_trap("banana_peel")
	if trap_def == null:
		push_warning("DebugVisualizer F7: banana_peel trap_def not found")
		return
	var inst := TrapInstance.new()
	inst.setup(trap_def, p1)
	get_tree().current_scene.add_child(inst)
	var forward := -p1.global_transform.basis.z.normalized()
	var spawn_pos := p1.global_position + forward * 1.0
	spawn_pos.y = 0.8
	inst.global_position = spawn_pos
