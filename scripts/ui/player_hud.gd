## 职责：四角玩家面板管理器
## 生成 4 个 PlayerPanel 到四角，响应服装/道具信号刷新
## P1 左上 / P2 右上 / P3 左下 / P4 右下

class_name PlayerHUD
extends Control

const PANEL_COLORS: Array[Color] = [
	Color(0.2, 0.45, 0.9),   # P1 蓝
	Color(0.9, 0.55, 0.1),   # P2 橙
	Color(0.2, 0.8, 0.3),    # P3 绿
	Color(0.6, 0.3, 0.9),    # P4 紫
]

## 玩家数量（2-4，由关卡/流程注入，默认 4）
var player_count: int = 4

var _panels: Array[PlayerPanel] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_signals()

func setup(count: int) -> void:
	player_count = clampi(count, 2, 4)
	_clear_panels()
	_build_panels()

func _clear_panels() -> void:
	for p in _panels:
		p.queue_free()
	_panels.clear()

func _build_panels() -> void:
	for i in player_count:
		var panel := PlayerPanel.new()
		panel.setup(i, PANEL_COLORS[i])
		add_child(panel)
		_position_panel(panel, i)
		_panels.append(panel)

func _position_panel(panel: Control, index: int) -> void:
	var margin := 24.0
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	match index:
		0:  # 左上
			panel.anchor_left = 0.0
			panel.anchor_top = 0.0
			panel.anchor_right = 0.0
			panel.anchor_bottom = 0.0
			panel.offset_left = margin
			panel.offset_top = margin
			panel.grow_horizontal = Control.GROW_DIRECTION_END
			panel.grow_vertical = Control.GROW_DIRECTION_END
		1:  # 右上
			panel.anchor_left = 1.0
			panel.anchor_top = 0.0
			panel.anchor_right = 1.0
			panel.anchor_bottom = 0.0
			panel.offset_left = -margin
			panel.offset_top = margin
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.grow_vertical = Control.GROW_DIRECTION_END
		2:  # 左下
			panel.anchor_left = 0.0
			panel.anchor_top = 1.0
			panel.anchor_right = 0.0
			panel.anchor_bottom = 1.0
			panel.offset_left = margin
			panel.offset_top = -margin
			panel.grow_horizontal = Control.GROW_DIRECTION_END
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		3:  # 右下
			panel.anchor_left = 1.0
			panel.anchor_top = 1.0
			panel.anchor_right = 1.0
			panel.anchor_bottom = 1.0
			panel.offset_left = -margin
			panel.offset_top = -margin
			panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

func _connect_signals() -> void:
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.item_used.connect(_on_item_used)
	EventBus.outfit_changed.connect(_on_outfit_changed)

func _on_item_picked_up(player_index: int, item_id: String) -> void:
	var panel := _get_panel(player_index)
	if not panel:
		return
	panel.set_item(_load_icon(item_id))

func _on_item_used(player_index: int, _item_id: String) -> void:
	var panel := _get_panel(player_index)
	if not panel:
		return
	panel.flash_item_used()

func _on_outfit_changed(player_index: int, slot: int, item_id: String) -> void:
	var panel := _get_panel(player_index)
	if not panel:
		return
	panel.set_outfit_slot(slot, _load_icon(item_id) if item_id != "" else null)

func _get_panel(player_index: int) -> PlayerPanel:
	if player_index < 0 or player_index >= _panels.size():
		return null
	return _panels[player_index]

## 图标资源映射（demo 版走 ItemIcons 静态表，正式版与资源同事约定）
func _load_icon(item_id: String) -> Texture2D:
	return ItemIcons.load_icon(item_id)

# ---------------------------------------------------------------- S6/S7 支持
## 给所有面板创建评分区
func prepare_scoreboards(dim_defs: Array) -> void:
	for p in _panels:
		p.clear_scoring()
		p.begin_scoring(dim_defs)

func reveal_dimension(player_index: int, key: String, score: float) -> void:
	var panel := _get_panel(player_index)
	if panel:
		panel.reveal_dim(key, score)

func set_total(player_index: int, total: float) -> void:
	var panel := _get_panel(player_index)
	if panel:
		panel.set_total(total)

## 冠军皇冠（其他人收起）
func set_champion(player_index: int) -> void:
	for i in _panels.size():
		_panels[i].show_crown(i == player_index)

func clear_scoreboards() -> void:
	for p in _panels:
		p.clear_scoring()
