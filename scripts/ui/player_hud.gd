## 职责：四角玩家面板管理器
## 四个 PlayerPanel 已预置在 battle_hud.tscn（P1 左上 / P2 右上 / P3 左下 / P4 右下），
## 本脚本只负责：按玩家数量显示/隐藏槽位、响应服装/道具信号刷新数据。
## 卡片位置与内部元素请在 battle_hud.tscn 中直接拖动调整。

class_name PlayerHUD
extends Control

## 玩家数量（2-4，由关卡/流程注入，默认 4）
var player_count: int = 4
## 玩家槽位索引（0-3），默认按数量取 0..count-1（大厅加入空位场景下非连续）
var player_slots: Array[int] = []

## 槽位 -> 面板（预置节点，索引与玩家位置一致）
var _slot_panels: Array[PlayerPanel] = [null, null, null, null]

@onready var _panel_p1: PlayerPanel = $PanelP1
@onready var _panel_p2: PlayerPanel = $PanelP2
@onready var _panel_p3: PlayerPanel = $PanelP3
@onready var _panel_p4: PlayerPanel = $PanelP4

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_panels = [_panel_p1, _panel_p2, _panel_p3, _panel_p4]
	_connect_signals()

func setup(count: int, slots: Array[int] = []) -> void:
	player_count = clampi(count, 2, 4)
	player_slots = slots if not slots.is_empty() else range(player_count)
	_apply_slots()

## 只按槽位 show/hide，不再实例化/释放
func _apply_slots() -> void:
	for slot in 4:
		var panel := _slot_panels[slot]
		if panel == null:
			continue
		if slot in player_slots:
			panel.setup(slot, PlayerConfig.get_color(slot))
			panel.show()
		else:
			panel.hide()

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
	for p in _slot_panels:
		if p != null:
			p.reset_scoring()

## 进入结算：隐藏全部战斗道具槽
func enter_scoring_style() -> void:
	for p in _slot_panels:
		if p != null:
			p.enter_scoring_style()

## 退出结算：恢复道具槽
func exit_scoring_style() -> void:
	for p in _slot_panels:
		if p != null:
			p.exit_scoring_style()
