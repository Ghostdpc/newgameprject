## 职责：关卡里的「相机分组」容器 —— 一组主相机 + 对应出生点 + 道具刷新点
## 用法（编辑器）：
##   1. 关卡根节点下新建 Node3D 挂本脚本（或直接放一个 CameraZone 节点）
##   2. 容器下放一个 Camera3D（取名随意，建议 MainCamera），直接拖位姿/FOV
##   3. 容器下放 SpawnPoints 和 ItemHotspots 容器，各自加子 Node3D 摆点
## 运行时由关卡脚本随机选一个 zone：选中 zone 的相机生效、出生点/道具点启用。
class_name CameraZone
extends Node3D

## 本分组的相机（放空则取容器下第一个 Camera3D）
@export var camera: Camera3D

func _ready() -> void:
	add_to_group("camera_zone")

## 取分组内相机（优先 @export 指定，否则第一个 Camera3D 子节点）
func get_camera() -> Camera3D:
	if camera and is_instance_valid(camera):
		return camera
	for c in get_children():
		if c is Camera3D:
			return c as Camera3D
	return null

## 取分组内出生点（SpawnPoints 容器下所有 Node3D 的全局坐标）
func get_spawn_points() -> Array[Vector3]:
	var root := get_node_or_null("SpawnPoints") as Node3D
	var points: Array[Vector3] = []
	if root:
		for c in root.get_children():
			if c is Node3D:
				points.append((c as Node3D).global_position)
	return points

## 取分组内道具刷新点（ItemHotspots 容器）
func get_hotspot_root() -> Node3D:
	return get_node_or_null("ItemHotspots") as Node3D

## 把本分组道具点注册到 item_hotspot 组（由关卡在选中本 zone 时调用）
func activate_hotspots() -> void:
	var root := get_hotspot_root()
	if root == null:
		return
	for c in root.get_children():
		if c is Node3D:
			c.add_to_group("item_hotspot")

## 清掉本分组道具点的 item_hotspot 组标记（未选中的 zone 不参与落点）
func deactivate_hotspots() -> void:
	var root := get_hotspot_root()
	if root == null:
		return
	for c in root.get_children():
		if c is Node3D:
			c.remove_from_group("item_hotspot")
