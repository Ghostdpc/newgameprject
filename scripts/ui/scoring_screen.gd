## 职责：S6/S7 结算界面 —— 斜置胶片框(最终照片) + 复用 PlayerPanel 四角头像卡
## + 底部六边形双按钮。评分数据来自 SettlementSystem（settlement_completed），
## 本界面只负责表现；卡片刷分动画由 PlayerPanel 提供（set_total / pop_plus / show_crown）。
## 静态布局在 scoring_screen.tscn 中可视化摆放（策划可拖动），六边形按钮因结构相同用代码生成。

class_name ScoringScreen
extends CanvasLayer

signal flow_finished(action: String)   # "restart" / "lobby"

## 评分 RT（ID 遮罩）调试面板，正常游戏不显示
@export var show_mask_debug: bool = false

const DIM_ORDER: Array = [
	["ratio", "画面比例"],
	["center", "C位"],
	["outfit", "服装表现"],
	["facing", "镜头朝向"],
]

@onready var _root: Control = $Root
@onready var _film: Control = $Root/Film
@onready var _photo_rect: TextureRect = $Root/Film/Photo
@onready var _btn_restart: Control = $Root/BtnRow/BtnRestart
@onready var _btn_lobby: Control = $Root/BtnRow/BtnLobby
@onready var _dim_rect: ColorRect = $Root/Dim

var _mask_panel: PanelContainer
var _mask_rect: TextureRect

var _player_hud: PlayerHUD = null
var _results: Dictionary = {}
var _skip_requested := false
var _sequence_running := false
var _sequence_done := false

func _ready() -> void:
	_root.hide()
	EventBus.stage_changed.connect(_on_stage_changed)
	_bind_button(_btn_restart, "restart")
	_bind_button(_btn_lobby, "lobby")
	_build_mask_panel()

## 新一轮开始（重开/返回）时收起结算界面、恢复战斗道具槽
func _on_stage_changed(stage: int) -> void:
	if stage != GameManager.GameStage.SCORING and _root.visible:
		_root.hide()
		if _player_hud:
			_player_hud.exit_scoring_style()

## 底部六边形按钮：hover 放大 + 左键点击
func _bind_button(btn: Control, action: String) -> void:
	btn.mouse_entered.connect(func(): btn.scale = Vector2(1.1, 1.1))
	btn.mouse_exited.connect(func(): btn.scale = Vector2.ONE)
	btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_do_action(action))

func _do_action(action: String) -> void:
	SoundMgr.play("confirm" if action == "restart" else "ui_click")
	flow_finished.emit(action)

## 评分 RT（ID 遮罩）调试面板：贴在结算画面右侧
func _build_mask_panel() -> void:
	_mask_panel = PanelContainer.new()
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

# ---------------------------------------------------------------- 结算入口
func setup(player_hud: PlayerHUD) -> void:
	_player_hud = player_hud

func show_results(results: Dictionary) -> void:
	_results = results
	_skip_requested = false
	_sequence_done = false
	_run_total = {}
	_root.show()
	# 保留四角 PlayerPanel 显示（战斗 HUD 顶部/取景框由 HUD.enter_scoring_mode 隐藏）
	if _player_hud:
		_player_hud.reset_scoreboards()
		_player_hud.enter_scoring_style()
	var img: Image = results.get("photo")
	if img and img.get_width() > 0:
		_photo_rect.texture = ImageTexture.create_from_image(img)
	var mask_img: Image = results.get("mask")
	if show_mask_debug and mask_img and mask_img.get_width() > 0:
		_mask_rect.texture = ImageTexture.create_from_image(mask_img)
		_mask_panel.show()
	else:
		_mask_panel.hide()
	_film.scale = Vector2(0.7, 0.7)
	_film.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_film, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_film, "modulate:a", 1.0, 0.25)
	_begin_sequence.call_deferred()

# ---------------------------------------------------------------- 逐维刷分
func _begin_sequence() -> void:
	await _run_scoring()
	_finish_champion()

func _run_scoring() -> void:
	_sequence_running = true
	await _wait(0.8)
	for dim_def in DIM_ORDER:
		var key := String(dim_def[0])
		for actor in _results.get("actors", []):
			var idx := int(actor.get("player_index", -1))
			var d: Dictionary = actor.get("dimensions", {}).get(key, {})
			_pop_plus(idx, float(d.get("score", 0.0)))
			await _wait(0.12)
		await _wait(0.5)
	# 惩罚扣分（被炸等）：四维加分后统一亮出 -xx
	var has_penalty := false
	for actor in _results.get("actors", []):
		if int(actor.get("penalty", 0)) > 0:
			has_penalty = true
			break
	if has_penalty:
		await _wait(0.4)
		for actor in _results.get("actors", []):
			var idx := int(actor.get("player_index", -1))
			var penalty := int(actor.get("penalty", 0))
			if penalty > 0:
				_pop_minus(idx, float(penalty))
				await _wait(0.12)
		await _wait(0.5)
	_sequence_running = false
	_sequence_done = true
	await _wait(0.6)

## +xx 弹字（由 PlayerPanel 提供 scale 弹跳效果）+ 总分累加
func _pop_plus(index: int, score: float) -> void:
	if not _player_hud:
		return
	var panel: PlayerPanel = _player_hud.get_panel(index)
	if not panel:
		return
	var total: float = _run_total.get(index, 0.0) + score
	_run_total[index] = total
	panel.set_total(total)
	panel.pop_plus(score)
	if score > 0.01:
		SoundMgr.play("score_tick", true)

## -xx 弹字（惩罚）+ 总分扣减，clamp 到 0
func _pop_minus(index: int, score: float) -> void:
	if not _player_hud:
		return
	var panel: PlayerPanel = _player_hud.get_panel(index)
	if not panel:
		return
	var total: float = maxf(0.0, _run_total.get(index, 0.0) - score)
	_run_total[index] = total
	panel.set_total(total)
	panel.pop_minus(score)

var _run_total: Dictionary = {}

func _wait(seconds: float) -> void:
	var actual := 0.05 if _skip_requested else seconds
	await get_tree().create_timer(actual).timeout

# ---------------------------------------------------------------- 冠军
func _finish_champion() -> void:
	var actors: Array = _results.get("actors", [])
	if actors.is_empty() or not _player_hud:
		return
	# 最高分（actors 已按 total 降序）；≤0 视为无人上镜，无冠军
	var top: float = float(actors[0].get("total", 0.0))
	if top <= 0.0:
		return
	# 并列冠军：所有 total == 最高分的玩家都戴皇冠
	for actor in actors:
		if is_equal_approx(float(actor.get("total", 0.0)), top):
			var idx := int(actor.get("player_index", 0))
			_player_hud.get_panel(idx).show_crown(true)
	SoundMgr.play("champion")

# ---------------------------------------------------------------- 输入
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if _sequence_running:
		var dev := _host_device()
		var is_host_accept: bool
		if dev == -1 or dev == -2:
			is_host_accept = event is InputEventKey or event.is_action_pressed("ui_accept")
		elif event is InputEventJoypadButton:
			is_host_accept = (event as InputEventJoypadButton).device == dev \
				and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
		else:
			is_host_accept = false
		if is_host_accept:
			_skip_requested = true
			get_viewport().set_input_as_handled()
		return
	if not _sequence_done:
		return
	# 重开：ui_accept / 键盘 A / 手柄 A
	var is_restart := event.is_action_pressed("ui_accept") \
		or (event is InputEventKey and event.physical_keycode == KEY_A) \
		or (event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	# 返回大厅：ui_cancel / 键盘 X / 手柄 B
	var is_lobby := event.is_action_pressed("ui_cancel") \
		or (event is InputEventKey and event.physical_keycode == KEY_X) \
		or (event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	if is_restart:
		get_viewport().set_input_as_handled()
		_do_action("restart")
	elif is_lobby:
		get_viewport().set_input_as_handled()
		_do_action("lobby")

func _host_device() -> int:
	if GameManager.player_devices.is_empty():
		return -2
	return GameManager.player_devices[0]
