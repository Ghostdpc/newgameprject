## 职责：地面高亮「拍照相机会拍到的区域」
## 把主相机视野里取景框(CameraViewfinder)覆盖的地面梯形算出，铺一层发光四边形。
## 与 photo_camera_rig 同源：拍照区 ≡ 主相机视野中取景框覆盖区域。
## 关键：放 layer3（layers=4），不进拍照 RT(cull_mask=1)，避免污染评分掩码。

class_name CaptureZoneHighlight
extends Node3D

const SHADER: Shader = preload("res://resources/shaders/capture_zone_highlight.gdshader")

## 地面高度（世界 y），发光片贴在此平面稍上方
@export var floor_y: float = 0.0
## 判定用的采样高度（世界 y）。按需只取地面高度：截地面平面求 (x,z) 落点绘制。
@export var sample_height: float = 0.0
## 抬高避免 z-fighting
@export var lift: float = 0.02

var _mesh_instance: MeshInstance3D
var _mesh: ArrayMesh
var _material: ShaderMaterial
var _main_camera: Camera3D
var _viewfinder: Control

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh = ArrayMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.material_override = _material
	_mesh_instance.layers = 4  # bit3：UI 标识层，不进拍照 RT
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 16384.0  # 顶点为全局坐标，禁用错误剔除
	_mesh_instance.top_level = true  # 忽略父变换，直接用全局坐标顶点
	add_child(_mesh_instance)
	_resolve_refs()

func _resolve_refs() -> void:
	var mains := get_tree().get_nodes_in_group("main_camera")
	if not mains.is_empty():
		_main_camera = mains[0] as Camera3D
	var vfs := get_tree().get_nodes_in_group("camera_viewfinder")
	if not vfs.is_empty():
		_viewfinder = vfs[0] as Control

func _process(_delta: float) -> void:
	if _main_camera == null or _viewfinder == null:
		_resolve_refs()
	_update_quad()

func _update_quad() -> void:
	if _main_camera == null or _viewfinder == null:
		return
	var rect := _viewfinder.get_global_rect()
	var corners := [
		rect.position,                                # TL
		Vector2(rect.end.x, rect.position.y),         # TR
		rect.end,                                     # BR
		Vector2(rect.position.x, rect.end.y),         # BL
	]
	var world: Array = []
	for c in corners:
		var hit = _project_to_footprint(c)
		if hit == null:
			_mesh_instance.visible = false
			return
		world.append(hit)
	_mesh_instance.visible = true
	_rebuild(world)

## 屏幕点 → 主相机射线 → 与角色中心高度平面求交，取其 (x,z) 作为脚下站位，
## 再压到地面高度绘制（无交返回 null）。
## 这样得到的是「玩家站在哪身体会进画面」的地面区域，且明显区别于取景框 UI。
func _project_to_footprint(screen_pt: Vector2):
	var origin := _main_camera.project_ray_origin(screen_pt)
	var dir := _main_camera.project_ray_normal(screen_pt)
	if absf(dir.y) < 0.0001:
		return null
	var t := (sample_height - origin.y) / dir.y
	if t <= 0.0:
		return null
	var p := origin + dir * t
	return Vector3(p.x, floor_y + lift, p.z)

func _rebuild(w: Array) -> void:
	var verts := PackedVector3Array([w[0], w[1], w[2], w[0], w[2], w[3]])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
		Vector2(0, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
