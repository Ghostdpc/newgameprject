## 职责：关卡里的"场景加载节点"（@tool）—— 把场景 tscn 挂进关卡
## 用法：关卡 tscn 的 Stage/Room 挂本脚本，填 scene_path 指向场景 tscn
## 缩放：直接用节点自带 scale 属性（关卡层），场景 tscn 内部也可自行缩放（美术层），两层相乘生效
@tool
class_name RoomSource
extends Node3D

## 场景 tscn 路径，编辑器里改此值立即加载显示
@export var scene_path: String = "":
	set(v):
		if scene_path == v:
			return
		scene_path = v
		if is_node_ready():
			_reload()

var _loaded: Node3D = null

func _ready() -> void:
	_reload()

func _reload() -> void:
	if _loaded:
		_loaded.queue_free()
		_loaded = null
	if scene_path.is_empty():
		return
	var res := load(scene_path)
	if res is PackedScene:
		_loaded = res.instantiate() as Node3D
		add_child(_loaded)
