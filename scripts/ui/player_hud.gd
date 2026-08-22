## 职责：四角玩家面板管理器
## 生成 4 个 PlayerPanel 到四角，响应服装/道具信号刷新
## P1 左上 / P2 右上 / P3 左下 / P4 右下

class_name PlayerHUD
extends Control

const PANEL_SCENE: PackedScene = preload("res://scenes/ui/player_panel.tscn")

## 玩家数量（2-4，由关卡/流程注入，默认 4）
var player_count: int = 4
## 玩家槽位索引（0-3），默认按数量取 0..count-1（大厅加入空位场景下非连续）
var player_slots: Array[int] = []

var _panels: Array[PlayerPanel] = []
## 槽位 -> 面板（空槽保持 null，索引与玩家位置一致）
var _slot_panels: Array[PlayerPanel] = [null, null, null, null]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_signals()

func setup(count: int, slots: Array[int] = []) -> void:
	player_count = clampi(count, 2, 4)
	player_slots = slots if not slots.is_empty() else range(player_count)
	_clear_panels()
	_build_panels()

func _clear_panels() -> void:
	for p in _panels:
		p.queue_free()
	_panels.clear()
	_slot_panels = [null, null, null, null]

func _build_panels() -> void:
	for slot in player_slots:
		var panel: PlayerPanel = PANEL_SCENE.instantiate() as PlayerPanel
		add_child(panel)
		panel.setup(slot, PlayerConfig.get_color(slot))
		_position_panel(panel, slot)
		_panels.append(panel)
		_slot_panels[slot] = panel

## 根节点矩形精确等于卡片尺寸，四角留 margin
func _position_panel(panel: Control, index: int) -> void:
	var margin := 24.0
	var w: float = panel.custom_minimum_size.x
	var h: float = panel.custom_minimum_size.y
	match index:
		0:  # 左上
			panel.anchor_left = 0.0; panel.anchor_top = 0.0
			panel.anchor_right = 0.0; panel.anchor_bottom = 0.0
			panel.offset_left = margin; panel.offset_top = margin
			panel.offset_right = margin + w; panel.offset_bottom = margin + h
		1:  # 右上
			panel.anchor_left = 1.0; panel.anchor_top = 0.0
			panel.anchor_right = 1.0; panel.anchor_bottom = 0.0
			panel.offset_left = -margin - w; panel.offset_top = margin
			panel.offset_right = -margin; panel.offset_bottom = margin + h
		2:  # 左下
			panel.anchor_left = 0.0; panel.anchor_top = 1.0
			panel.anchor_right = 0.0; panel.anchor_bottom = 1.0
			panel.offset_left = margin; panel.offset_top = -margin - h
			panel.offset_right = margin + w; panel.offset_bottom = -margin
		3:  # 右下
			panel.anchor_left = 1.0; panel.anchor_top = 1.0
			panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
			panel.offset_left = -margin - w; panel.offset_top = -margin - h
			panel.offset_right = -margin; panel.offset_bottom = -margin

func _connect_signals() -> void:
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.item_used.connect(_on_item_used)

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

func _get_panel(player_index: int) -> PlayerPanel:
	if player_index < 0 or player_index >= _slot_panels.size():
		return null
	return _slot_panels[player_index]

## 图标资源映射：道具 id → 图标 key → 贴图（走 ItemConfig.get_item_icon + ItemIcons）
func _load_icon(item_id: String) -> Texture2D:
	var icon_key: String = ItemSystem._item_config.get_item_icon(item_id)
	if icon_key == "":
		return null
	return ItemIcons.load_icon(icon_key)

# ---------------------------------------------------------------- 结算复用
## 结算时刷新面板：只做数据/动画透传，不另建卡片
func get_panel(player_index: int) -> PlayerPanel:
	return _get_panel(player_index)

func reset_scoreboards() -> void:
	for p in _panels:
		p.reset_scoring()

## 进入结算：隐藏全部战斗道具槽
func enter_scoring_style() -> void:
	for p in _panels:
		p.enter_scoring_style()

## 退出结算：恢复道具槽
func exit_scoring_style() -> void:
	for p in _panels:
		p.exit_scoring_style()
