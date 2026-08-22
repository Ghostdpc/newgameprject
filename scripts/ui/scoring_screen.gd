## 职责：S6/S7 结算界面（改版）—— 斜置胶片框(最终照片) + 四角头像卡
## （P字标 + 白色总分 + 随玩家色的 +xx 刷分特效 + 冠军皇冠）+ 底部六边形双按钮
## 评分数据来自 SettlementSystem（settlement_completed），本界面只负责表现。

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

# ---- 胶片框（手绘贴图版，DreamMaker 生成 + 洋红抠透明）
const FRAME_W := 1080.0
const FRAME_H := 720.0   # 与贴图 1536x1024 同比例 1.5
const TILT_DEG := -5.0
const FILM_TEX := preload("res://assets/textures/ui/film_frame.png")
## 中心窗口在贴图里的比例矩形（实测），用于放置照片
const FILM_HOLE := Rect2(0.071, 0.176, 0.857, 0.633)

# ---- 四角头像卡布局
const CARD_W := 260.0
const CARD_H := 300.0
const BUBBLE_X := 30.0
const BUBBLE_Y := 20.0
const BUBBLE_S := 200.0
const BODY_W := 210.0
const BODY_TOP := 24.0
const EYES_W := 88.0
const LABEL_H := 64.0
const MARGIN := 24.0

const TINT_SHADER := preload("res://resources/ui/card_tint.gdshader")
## 分数字体：Kaph（总分/键位 Regular，+xx 弹字 Italic）
const FONT_SCORE := preload("res://assets/fonts/Kaph-Regular.otf")
const FONT_SCORE_ITALIC := preload("res://assets/fonts/Kaph-Italic.otf")
const COLOR_OUTLINE := Color(0.02, 0.02, 0.03, 1)

@onready var _root: Control = $Root

var _dim_rect: ColorRect
var _film: Control
var _photo_rect: TextureRect
var _mask_panel: PanelContainer
var _mask_rect: TextureRect
var _btn_row: HBoxContainer
var _btn_restart: Control
var _btn_lobby: Control

var _player_hud: PlayerHUD = null
var _results: Dictionary = {}
var _skip_requested := false
var _sequence_running := false
var _sequence_done := false
var _cards: Dictionary = {}

func _ready() -> void:
	_root.hide()
	EventBus.stage_changed.connect(_on_stage_changed)
	_build_dim()
	_build_film_frame()
	_build_buttons()
	_build_mask_panel()

## 新一轮开始（重开/返回）时收起结算界面、恢复战斗卡片
func _on_stage_changed(stage: int) -> void:
	if stage != GameManager.GameStage.SCORING and _root.visible:
		_root.hide()
		if _player_hud:
			_player_hud.show()

# ---------------------------------------------------------------- 静态搭建
func _build_dim() -> void:
	_dim_rect = ColorRect.new()
	_dim_rect.color = Color(0, 0, 0, 0.28)
	_dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim_rect)

## 斜置胶片框：手绘贴图 + 中心窗口放照片
func _build_film_frame() -> void:
	_film = Control.new()
	_film.size = Vector2(FRAME_W, FRAME_H)
	_film.anchor_left = 0.5
	_film.anchor_top = 0.5
	_film.anchor_right = 0.5
	_film.anchor_bottom = 0.5
	_film.offset_left = -FRAME_W * 0.5
	_film.offset_top = -FRAME_H * 0.5
	_film.offset_right = FRAME_W * 0.5
	_film.offset_bottom = FRAME_H * 0.5
	_film.pivot_offset = _film.size * 0.5
	_film.rotation = deg_to_rad(TILT_DEG)
	_film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_film)

	# 照片先加（垫底），外扩 10px 让边缘藏进手绘白边下
	_photo_rect = TextureRect.new()
	var pad := 10.0
	_photo_rect.offset_left = FILM_HOLE.position.x * FRAME_W - pad
	_photo_rect.offset_top = FILM_HOLE.position.y * FRAME_H - pad
	_photo_rect.offset_right = (FILM_HOLE.position.x + FILM_HOLE.size.x) * FRAME_W + pad
	_photo_rect.offset_bottom = (FILM_HOLE.position.y + FILM_HOLE.size.y) * FRAME_H + pad
	_photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film.add_child(_photo_rect)

	# 手绘胶片框贴图盖在上面
	var frame := TextureRect.new()
	frame.texture = FILM_TEX
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film.add_child(frame)

## 底部六边形双按钮：再来一局(A) / 返回(X)
func _build_buttons() -> void:
	_btn_row = HBoxContainer.new()
	_btn_row.anchor_left = 0.5
	_btn_row.anchor_top = 1.0
	_btn_row.anchor_right = 0.5
	_btn_row.anchor_bottom = 1.0
	_btn_row.offset_left = -300.0
	_btn_row.offset_top = -150.0
	_btn_row.offset_right = 300.0
	_btn_row.offset_bottom = -16.0
	_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_row.add_theme_constant_override("separation", 90)
	_btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_btn_row)
	_btn_restart = _make_hex_button("icon_restart", "A", "restart")
	_btn_lobby = _make_hex_button("icon_exit", "X", "lobby")

func _make_hex_button(icon_key: String, key_text: String, action: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(120, 140)
	c.mouse_filter = Control.MOUSE_FILTER_STOP

	var hex := TextureRect.new()
	hex.texture = ItemIcons.load_icon("card_hex")
	hex.size = Vector2(110, 126)
	hex.position = Vector2(5, 0)
	hex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(hex)

	var icon := TextureRect.new()
	icon.texture = ItemIcons.load_icon(icon_key)
	icon.size = Vector2(66, 66)
	icon.position = Vector2(27, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon)

	var key := Label.new()
	key.text = key_text
	key.add_theme_font_override("font", FONT_SCORE)
	key.add_theme_font_size_override("font_size", 34)
	key.add_theme_color_override("font_color", Color.WHITE)
	key.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	key.add_theme_constant_override("outline_size", 10)
	key.position = Vector2(40, 104)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(key)

	c.pivot_offset = Vector2(60, 70)
	c.mouse_entered.connect(func(): c.scale = Vector2(1.1, 1.1))
	c.mouse_exited.connect(func(): c.scale = Vector2.ONE)
	c.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_do_action(action))
	_btn_row.add_child(c)
	return c

func _do_action(action: String) -> void:
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
	_root.show()
	if _player_hud:
		_player_hud.hide()
	var img: Image = results.get("photo")
	if img and img.get_width() > 0:
		_photo_rect.texture = ImageTexture.create_from_image(img)
	var mask_img: Image = results.get("mask")
	if show_mask_debug and mask_img and mask_img.get_width() > 0:
		_mask_rect.texture = ImageTexture.create_from_image(mask_img)
		_mask_panel.show()
	else:
		_mask_panel.hide()
	_clear_cards()
	for actor in results.get("actors", []):
		_build_card(int(actor.get("player_index", -1)), actor)
	_film.scale = Vector2(0.7, 0.7)
	_film.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_film, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_film, "modulate:a", 1.0, 0.25)
	_begin_sequence.call_deferred()

func _clear_cards() -> void:
	for data in _cards.values():
		(data["root"] as Node).queue_free()
	_cards.clear()

# ---------------------------------------------------------------- 四角头像卡
func _build_card(index: int, actor: Dictionary) -> void:
	if index < 0:
		return
	var color: Color = actor.get("color", PlayerConfig.get_color(index))
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_card(root, index)
	_root.add_child(root)
	var is_right := index % 2 == 1

	var bubble := TextureRect.new()
	bubble.texture = ItemIcons.load_icon("card_bubble")
	bubble.position = Vector2(BUBBLE_X, BUBBLE_Y)
	bubble.size = Vector2(BUBBLE_S, BUBBLE_S)
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	bubble.flip_h = is_right
	bubble.flip_v = index >= 2
	_apply_tint(bubble, color)
	root.add_child(bubble)

	var body := TextureRect.new()
	body.texture = ItemIcons.load_icon("card_body")
	var body_h := BODY_W * body.texture.get_size().y / body.texture.get_size().x
	body.size = Vector2(BODY_W, body_h)
	body.position = Vector2((CARD_W - BODY_W) * 0.5, BODY_TOP)
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_apply_tint(body, color)
	root.add_child(body)

	var eyes := TextureRect.new()
	eyes.texture = ItemIcons.load_icon("card_eyes")
	var eyes_h := EYES_W * eyes.texture.get_size().y / eyes.texture.get_size().x
	eyes.size = Vector2(EYES_W, eyes_h)
	eyes.position = Vector2(CARD_W * 0.5 - EYES_W * 0.5, BODY_TOP + body_h * 0.42 - eyes_h * 0.5)
	eyes.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eyes.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	root.add_child(eyes)

	var label := TextureRect.new()
	label.texture = ItemIcons.load_icon("card_p%d" % (index + 1))
	var label_w := LABEL_H * label.texture.get_size().x / label.texture.get_size().y
	label.size = Vector2(label_w, LABEL_H)
	label.position = Vector2(-16.0 if not is_right else CARD_W - label_w + 4.0, -16.0)
	label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_apply_tint(label, color)
	root.add_child(label)

	var crown := TextureRect.new()
	crown.texture = ItemIcons.load_icon("crown")
	crown.size = Vector2(96, 76)
	crown.position = Vector2(BUBBLE_X + BUBBLE_S - 78.0, -52.0)
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	crown.hide()
	root.add_child(crown)

	var total := Label.new()
	total.add_theme_font_override("font", FONT_SCORE)
	total.add_theme_font_size_override("font_size", 68)
	total.add_theme_color_override("font_color", Color.WHITE)
	total.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	total.add_theme_constant_override("outline_size", 14)
	total.text = "0"
	total.size = Vector2(170, 84)
	if is_right:
		total.position = Vector2(CARD_W - 158.0, 230.0)
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		total.position = Vector2(-12.0, 230.0)
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(total)

	_cards[index] = {
		"root": root, "crown": crown, "total": total,
		"shown": 0.0, "color": color,
		"plus_pos": Vector2(BUBBLE_X + BUBBLE_S + 4.0 if not is_right else BUBBLE_X - 84.0, BUBBLE_Y + 30.0),
	}

func _position_card(card: Control, index: int) -> void:
	match index:
		0:
			card.anchor_left = 0; card.anchor_top = 0; card.anchor_right = 0; card.anchor_bottom = 0
			card.offset_left = MARGIN; card.offset_top = MARGIN
			card.offset_right = MARGIN + CARD_W; card.offset_bottom = MARGIN + CARD_H
		1:
			card.anchor_left = 1; card.anchor_top = 0; card.anchor_right = 1; card.anchor_bottom = 0
			card.offset_left = -MARGIN - CARD_W; card.offset_top = MARGIN
			card.offset_right = -MARGIN; card.offset_bottom = MARGIN + CARD_H
		2:
			card.anchor_left = 0; card.anchor_top = 1; card.anchor_right = 0; card.anchor_bottom = 1
			card.offset_left = MARGIN; card.offset_top = -MARGIN - CARD_H
			card.offset_right = MARGIN + CARD_W; card.offset_bottom = -MARGIN
		3:
			card.anchor_left = 1; card.anchor_top = 1; card.anchor_right = 1; card.anchor_bottom = 1
			card.offset_left = -MARGIN - CARD_W; card.offset_top = -MARGIN - CARD_H
			card.offset_right = -MARGIN; card.offset_bottom = -MARGIN

func _apply_tint(rect: TextureRect, color: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = TINT_SHADER
	m.set_shader_parameter("tint", color)
	rect.material = m

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
	_sequence_running = false
	_sequence_done = true
	await _wait(0.6)

## +xx 特效（玩家色上浮淡出）+ 总分累加弹跳
func _pop_plus(index: int, score: float) -> void:
	var card: Dictionary = _cards.get(index)
	if card.is_empty():
		return
	card["shown"] = card["shown"] + score
	var total: Label = card["total"]
	total.text = "%.0f" % card["shown"]
	total.pivot_offset = total.size * 0.5
	total.scale = Vector2(1.3, 1.3)
	var tb := create_tween()
	tb.tween_property(total, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if score <= 0.01:
		return
	var plus := Label.new()
	plus.add_theme_font_override("font", FONT_SCORE_ITALIC)
	plus.text = "+%.0f" % score
	plus.add_theme_font_size_override("font_size", 42)
	plus.add_theme_color_override("font_color", card["color"])
	plus.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	plus.add_theme_constant_override("outline_size", 10)
	plus.position = card["plus_pos"]
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(card["root"] as Control).add_child(plus)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(plus, "position:y", plus.position.y - 52.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(plus, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tw.chain().tween_callback(plus.queue_free)

func _wait(seconds: float) -> void:
	var actual := 0.05 if _skip_requested else seconds
	await get_tree().create_timer(actual).timeout

# ---------------------------------------------------------------- 冠军
func _finish_champion() -> void:
	var actors: Array = _results.get("actors", [])
	if actors.is_empty():
		return
	var champion: Dictionary = actors[0]
	var card: Dictionary = _cards.get(int(champion.get("player_index", 0)))
	if card.is_empty():
		return
	var crown: TextureRect = card["crown"]
	crown.show()
	crown.pivot_offset = crown.size * 0.5
	crown.scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(crown, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.physical_keycode == KEY_A):
		get_viewport().set_input_as_handled()
		_do_action("restart")
	elif event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.physical_keycode == KEY_X):
		get_viewport().set_input_as_handled()
		_do_action("lobby")

func _host_device() -> int:
	if GameManager.player_devices.is_empty():
		return -2
	return GameManager.player_devices[0]
