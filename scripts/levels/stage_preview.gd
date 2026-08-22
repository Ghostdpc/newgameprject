## 职责：场景资源预览与缩放（@tool）—— 挂在关卡 Stage 下的"舞台资源"节点
## 用法：新建关卡时，在 Stage 下建一个 Node3D 挂本脚本，填 scene_path + room_scale：
## - 编辑器里改 scene_path 自动加载 glb 显示
## - 编辑器里改 room_scale 实时缩放模型（语义 = 资源最长边目标米数）
## 运行时同样生效，无需额外代码
@tool
class_name StagePreview
extends Node3D

## 场景资源路径（.glb / .gltf），编辑器里改此值立即加载显示
@export var scene_path: String = "":
	set(v):
		if scene_path == v:
			return
		scene_path = v
		if is_node_ready():
			_reload()

## 目标最长边（米）。资源原始最长边由脚本实测，改此值实时等比缩放
@export var room_scale: float = 8.0:
	set(v):
		room_scale = v
		if is_node_ready():
			_apply_scale()

var _loaded: Node3D = null
## 资源原始最长边（scale=1 时实测）
var _raw_longest: float = 0.0

func _ready() -> void:
	_reload()

func _reload() -> void:
	if _loaded:
		_loaded.queue_free()
		_loaded = null
	_raw_longest = 0.0
	scale = Vector3.ONE
	if scene_path.is_empty():
		return
	var res := load(scene_path)
	if res is PackedScene:
		_loaded = res.instantiate() as Node3D
		add_child(_loaded)
		if Engine.is_editor_hint():
			_loaded.owner = get_tree().edited_scene_root
		_raw_longest = _measure_longest()
	_apply_scale()

func _apply_scale() -> void:
	if _raw_longest > 0.0 and room_scale > 0.0:
		scale = Vector3.ONE * (room_scale / _raw_longest)

func _measure_longest() -> float:
	var bounds := AABB()
	var has := false
	for mi in _collect_meshes(self):
		var m: MeshInstance3D = mi as MeshInstance3D
		if m.mesh == null:
			continue
		var aabb := m.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var p := m.global_transform * Vector3(x, y, z)
					if has:
						bounds = bounds.expand(p)
					else:
						bounds = AABB(p, Vector3.ZERO)
						has = true
	if not has:
		return 0.0
	var s := bounds.size
	return maxf(s.x, maxf(s.y, s.z))

func _collect_meshes(root: Node) -> Array:
	var result: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			result.append(n)
		for c in n.get_children():
			stack.append(c)
	return result
