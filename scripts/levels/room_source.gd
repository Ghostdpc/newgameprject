## 职责：关卡里的"场景加载节点"（@tool）—— 把场景 tscn 挂进关卡
## 用法：关卡 tscn 的 Stage/Room 挂本脚本，填 scene_path 指向场景 tscn
## 缩放：直接用节点自带 scale 属性（关卡层），场景 tscn 内部也可自行缩放（美术层），两层相乘生效
##
## 加载：编辑器（@tool）用同步 load 立即预览；运行时 priority 用后台线程预加载
##   缓存（ResourceLoader.load_threaded_request），instantiate 前才从缓存取，
##   避免大 GLB/贴图首帧同步读盘卡死。
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
	# 编辑器预览：同步 load（@tool）
	if Engine.is_editor_hint():
		if _loaded:
			_loaded.queue_free()
			_loaded = null
		if scene_path.is_empty():
			return
		var res := load(scene_path)
		if res is PackedScene:
			_loaded = res.instantiate() as Node3D
			add_child(_loaded)
		return

	# 运行时：优先从后台线程预加载缓存取，未预载（直接 change_scene 无 LoadingScreen）则同步 load 兜底
	var packed: PackedScene = null
	if scene_path.is_empty():
		return
	if ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		packed = load(scene_path) as PackedScene
	if packed:
		# 重复加载（scene_path 变更或二次 _reload）前先清理旧实例，避免泄漏
		if _loaded:
			_loaded.queue_free()
			_loaded = null
		_loaded = packed.instantiate() as Node3D
		add_child(_loaded)
