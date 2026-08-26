## 职责：大厅玩家卡片视图（空位 / 已加入 / 已就绪 三态），纯视图无交互逻辑
## 交互由 lobby.gd 统一处理，本卡片只负责按状态切换贴图、配色与按钮提示

class_name LobbyCard
extends Control

enum State { EMPTY, JOINED, READY }

const TEX_SOLID: Texture2D = preload("res://assets/textures/ui/lobby/avatar_solid.png")
const TEX_WIRE: Texture2D = preload("res://assets/textures/ui/lobby/avatar_wire.png")
## 横幅染色：已加入=方块键粉色 / 已准备=三角键青绿色（不随角色色）
const COLOR_JOINED := Color(0.96, 0.29, 0.62)
const COLOR_READY := Color(0.24, 0.86, 0.59)
const BADGES: Array[Texture2D] = [
	preload("res://assets/textures/ui/card/card_p1.png"),
	preload("res://assets/textures/ui/card/card_p2.png"),
	preload("res://assets/textures/ui/card/card_p3.png"),
	preload("res://assets/textures/ui/card/card_p4.png"),
]

@onready var _face: TextureRect = $CardFace
@onready var _badge: TextureRect = $PBadge
@onready var _avatar: TextureRect = $Avatar
@onready var _banner_joined: TextureRect = $BannerJoined
@onready var _banner_ready: TextureRect = $BannerReady
@onready var _prompt_join: Control = $PromptJoin
@onready var _prompt_ready: Control = $PromptReady
@onready var _prompt_cancel_ready: Control = $PromptCancelReady
@onready var _device_label: Label = $DeviceLabel

var color := Color.WHITE

func setup(index: int, c: Color) -> void:
	color = c
	_badge.texture = BADGES[index % BADGES.size()]
	set_state(State.EMPTY)

## 卡片下方显示本角色操作方式（如「键盘1」「手柄2」）；text 为空则隐藏
func set_device(text: String) -> void:
	if _device_label == null:
		return
	_device_label.text = text
	_device_label.visible = not text.is_empty()

func set_state(s: State) -> void:
	var joined := s != State.EMPTY
	_face.modulate = color.lerp(Color.WHITE, 0.45) if joined else Color(0.62, 0.64, 0.72)
	_avatar.texture = TEX_SOLID if joined else TEX_WIRE
	_avatar.modulate = color if joined else Color(0.14, 0.16, 0.22)

	_banner_joined.visible = s == State.JOINED
	_banner_joined.modulate = COLOR_JOINED
	_banner_ready.visible = s == State.READY
	_banner_ready.modulate = COLOR_READY

	_prompt_join.visible = s == State.EMPTY
	_prompt_ready.visible = s == State.JOINED
	_prompt_cancel_ready.visible = s == State.READY
