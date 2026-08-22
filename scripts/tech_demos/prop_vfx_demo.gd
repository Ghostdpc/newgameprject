## 职责：边缘 UIMask + 保留的 3D 脚底圈 / 眩晕星预览。

extends Node3D

const WORLD_VFX_SCENE := preload("res://scenes/fx/world_item_vfx.tscn")
const FULLSCREEN_POST_SCENE := preload("res://scenes/fx/fullscreen_item_post.tscn")

@onready var _target: Node3D = $Target
@onready var _camera: Camera3D = $Camera3D
@onready var _title: Label = $Ui/Title

var _overlay: FullscreenItemPost
var _index := 0
var _sequence := [
	[WorldItemVfx.Kind.FEET_RING, "能量饮料 · 3D 脚底能量圈", "", Color(1.0, 0.56, 0.06, 1.0), 3.0],
	[WorldItemVfx.Kind.FEET_RING, "香蕉皮 · 3D 落地警示圈", "", Color(1.0, 0.82, 0.08, 1.0), 0.8],
	[WorldItemVfx.Kind.BANANA_STUN, "香蕉皮 · 3D 眩晕星星", "", Color.WHITE, 1.5],
	[WorldItemVfx.Kind.FEET_RING, "快进 · 红色边缘 UIMask / 速度条纹", "fast", Color(1.0, 0.12, 0.04, 1.0), 3.0],
	[WorldItemVfx.Kind.FEET_RING, "慢放 · 蓝色边缘 UIMask / 缓流条纹", "slow", Color(0.14, 0.66, 1.0, 1.0), 3.0],
	[WorldItemVfx.Kind.FEET_RING, "加时 · 绿色边缘 UIMask / 扩张脉冲", "add", Color(0.20, 1.0, 0.38, 1.0), 1.0],
	[WorldItemVfx.Kind.FEET_RING, "减时 · 红色边缘 UIMask / 警告抖动", "sub", Color(1.0, 0.06, 0.04, 1.0), 1.0],
	[WorldItemVfx.Kind.FEET_RING, "相机遥控器 · 金色边缘 UIMask / 取景框", "camera", Color(1.0, 0.76, 0.16, 1.0), 2.5],
]

func _ready() -> void:
	_camera.global_position = Vector3(0.0, 3.7, 8.6)
	_camera.look_at(Vector3(0.0, 1.05, 0.0))
	_overlay = FULLSCREEN_POST_SCENE.instantiate() as FullscreenItemPost
	add_child(_overlay)
	_loop_preview()

func _loop_preview() -> void:
	while is_inside_tree():
		_play_current()
		await get_tree().create_timer(3.4).timeout
		_index = (_index + 1) % _sequence.size()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_RIGHT:
		_index = (_index + 1) % _sequence.size()
		_play_current()
	elif key.keycode == KEY_LEFT:
		_index = (_index - 1 + _sequence.size()) % _sequence.size()
		_play_current()
	elif key.keycode == KEY_SPACE:
		_play_current()

func _play_current() -> void:
	var entry: Array = _sequence[_index]
	_title.text = String(entry[1]) + "\n← / → 切换 · 空格重播"
	var effect := WORLD_VFX_SCENE.instantiate() as WorldItemVfx
	effect.configure(int(entry[0]), float(entry[4]), _target, entry[3] as Color)
	add_child(effect)
	var screen_mode := String(entry[2])
	if not screen_mode.is_empty():
		_overlay.play(screen_mode, float(entry[4]))
