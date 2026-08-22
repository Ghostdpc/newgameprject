## 职责：S5/S6/S7 —— 快门后照片居中放大 → 四角面板逐维刷分（任意确认键加速）
##       → 总分排名 → 冠军皇冠 + 重开/返回房间（交互文档 §7）
## 评分数据来自 SettlementSystem（settlement_completed），本界面只负责表现。

class_name ScoringScreen
extends CanvasLayer

signal flow_finished(action: String)   # "restart" / "lobby"

const DIM_ORDER: Array = [
	["ratio", "画面比例"],
	["center", "C位"],
	["outfit", "服装表现"],
	["facing", "镜头朝向"],
]

@onready var _root: Control = $Root
@onready var _photo_rect: TextureRect = $Root/PhotoFrame/VBox/PhotoRect
@onready var _caption: Label = $Root/PhotoFrame/VBox/CaptionLabel
@onready var _dim_callout: Label = $Root/DimCallout
@onready var _score_hint: Label = $Root/ScoreHint
@onready var _champion_box: Control = $Root/ChampionBox
@onready var _champion_label: Label = $Root/ChampionBox/VBox/ChampionLabel
@onready var _restart_btn: Button = $Root/ChampionBox/VBox/ButtonRow/RestartButton
@onready var _lobby_btn: Button = $Root/ChampionBox/VBox/ButtonRow/LobbyButton

var _player_hud: PlayerHUD = null
var _results: Dictionary = {}
var _skip_requested: bool = false
var _sequence_running: bool = false
var _mask_panel: Control = null
var _mask_rect: TextureRect = null

func _ready() -> void:
	_root.hide()
	_restart_btn.pressed.connect(func(): flow_finished.emit("restart"))
	_lobby_btn.pressed.connect(func(): flow_finished.emit("lobby"))
	EventBus.stage_changed.connect(_on_stage_changed)
	_build_mask_panel()

## 新一轮开始（重开/返回）时收起结算界面与评分面板
func _on_stage_changed(stage: int) -> void:
	if stage != GameManager.GameStage.SCORING and _root.visible:
		_root.hide()
		if _player_hud:
			_player_hud.clear_scoreboards()

## 评分 RT（ID 遮罩）调试面板：贴在结算画面右侧，方便核对像素评分
func _build_mask_panel() -> void:
	_mask_panel = PanelContainer.new()
	_mask_panel.name = "MaskPanel"
	_mask_panel.anchor_left = 1.0
	_mask_panel.anchor_top = 0.5
	_mask_panel.anchor_right = 1.0
	_mask_panel.anchor_bottom = 0.5
	_mask_panel.offset_left = -420.0
	_mask_panel.offset_top = -220.0
	_mask_panel.offset_right = -40.0
	_mask_panel.offset_bottom = 40.0
	_mask_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mask_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_mask_panel.hide()
	_root.add_child(_mask_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_mask_panel.add_child(vbox)

	var label := Label.new()
	label.text = "评分RT · ID遮罩（只算玩家）"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	_mask_rect = TextureRect.new()
	_mask_rect.custom_minimum_size = Vector2(320, 180)
	_mask_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mask_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(_mask_rect)

func setup(player_hud: PlayerHUD) -> void:
	_player_hud = player_hud

func show_results(results: Dictionary) -> void:
	_results = results
	_skip_requested = false
	_root.show()
	_champion_box.hide()
	_score_hint.show()
	_dim_callout.text = "—— 系统四维评分 ——"
	# 照片居中放大（S6：照片居中放很大）
	var img: Image = results.get("photo")
	if img and img.get_width() > 0:
		_photo_rect.texture = ImageTexture.create_from_image(img)
	var mask_img: Image = results.get("mask")
	if mask_img and mask_img.get_width() > 0:
		_mask_rect.texture = ImageTexture.create_from_image(mask_img)
		_mask_panel.show()
	else:
		_mask_panel.hide()
	_caption.text = "快门瞬间 · 主题：摄影棚乱斗"
	_photo_rect.pivot_offset = _photo_rect.size * 0.5
	_photo_rect.modulate.a = 0.0
	_photo_rect.scale = Vector2(0.55, 0.55)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_photo_rect, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_photo_rect, "modulate:a", 1.0, 0.3)
	_begin_sequence.call_deferred()

func _begin_sequence() -> void:
	await _run_scoring()
	_finish_champion()

# ---------------------------------------------------------------- 逐维刷分
func _run_scoring() -> void:
	if _player_hud == null:
		return
	_sequence_running = true
	_player_hud.prepare_scoreboards(DIM_ORDER)
	await _wait(0.7)
	for dim_def in DIM_ORDER:
		var key := String(dim_def[0])
		var dim_name := String(dim_def[1])
		_callout(dim_name)
		for actor in _results.get("actors", []):
			var dims: Dictionary = actor.get("dimensions", {})
			var d: Dictionary = dims.get(key, {})
			var score: float = d.get("score", 0.0)
			_player_hud.reveal_dimension(int(actor.get("player_index", -1)), key, score)
			await _wait(0.1)
		await _wait(0.55)
	# 总分
	for actor in _results.get("actors", []):
		_player_hud.set_total(int(actor.get("player_index", -1)), float(actor.get("total", 0.0)))
	_callout("总分排名")
	_sequence_running = false
	await _wait(1.0)

func _callout(text: String) -> void:
	_dim_callout.text = text
	_dim_callout.pivot_offset = _dim_callout.size * 0.5
	_dim_callout.scale = Vector2(1.35, 1.35)
	_dim_callout.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_dim_callout, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _wait(seconds: float) -> void:
	var actual := 0.05 if _skip_requested else seconds
	await get_tree().create_timer(actual).timeout

# ---------------------------------------------------------------- 冠军结算
func _finish_champion() -> void:
	var actors: Array = _results.get("actors", [])
	if actors.is_empty():
		return
	# settlement 已按总分降序排序
	var champion: Dictionary = actors[0]
	var idx := int(champion.get("player_index", 0))
	if _player_hud:
		_player_hud.set_champion(idx)
	_champion_label.text = "★ 冠军 · P%d" % (idx + 1)
	_champion_box.show()
	_champion_box.pivot_offset = _champion_box.size * 0.5
	_champion_box.scale = Vector2(0.7, 0.7)
	_champion_box.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_champion_box, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_champion_box, "modulate:a", 1.0, 0.25)
	_score_hint.hide()
	_callout("评分结束 · 称号仅表现，不影响系统分数")
	_restart_btn.grab_focus()

# ---------------------------------------------------------------- 输入加速
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var is_accept := event.is_action_pressed("ui_accept") \
		or (event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	if _sequence_running and is_accept:
		_skip_requested = true
		get_viewport().set_input_as_handled()
