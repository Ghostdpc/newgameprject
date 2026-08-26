## 职责：角色视觉状态效果——绘画著色（paint）与灰化（stun gray）。
## 支持按部位施加（受击处局部变色），部位以 MeshInstance3D 名字匹配。
## 效果叠加在角色 mesh 上，恢复时还原原始材质。

class_name CharacterEffects
extends Node

signal effect_started(effect: String)
signal effect_finished(effect: String)

const GRAY_COLOR := Color(0.4, 0.4, 0.45, 1.0)
const PLAYER_TOON_MATERIAL: ShaderMaterial = preload("res://resources/materials/player_toon_preview.tres")
const PLAYER_TOON_OUTLINE_MATERIAL: ShaderMaterial = preload("res://resources/materials/player_toon_outline_preview.tres")

## 隐形「模板写入」通道：让玩家真实网格在 main 视口写 stencil=1，
## 供地面取景光圈(CaptureZoneHighlight)读取 → 实现「只有玩家遮挡光圈」。
## 作为每个玩家材质的 next_pass，轮廓精确贴合模型且不改变外观。
static var _stencil_writer_material: ShaderMaterial
static var _toon_outline_material: ShaderMaterial

static func _get_stencil_writer() -> ShaderMaterial:
	if _stencil_writer_material == null:
		var m := ShaderMaterial.new()
		m.shader = load("res://resources/shaders/capture_stencil_writer.gdshader")
		m.render_priority = -8  # 早于光圈(=8)绘制，保证光圈读到 stencil
		_stencil_writer_material = m
	return _stencil_writer_material

static func _get_toon_outline_material() -> ShaderMaterial:
	if _toon_outline_material == null:
		var material := PLAYER_TOON_OUTLINE_MATERIAL.duplicate() as ShaderMaterial
		material.next_pass = _get_stencil_writer()
		_toon_outline_material = material
	return _toon_outline_material

## 脏污贴花（灰头土脸）：手绘烟熏纹理，全场静态缓存复用
static var _dirt_texture: Texture2D

## 部位名 -> MeshInstance3D 名字子串匹配（Mannequin 命名）
const PART_PATTERNS: Dictionary = {
	"head": ["head"],
	"arm_r": ["armright"],
	"arm_l": ["armleft"],
	"leg_r": ["legright"],
	"leg_l": ["legleft"],
	"body": ["body"],
}

@export var character_root: Node3D

## 角色基础色（玩家色），paint/gray 在此之上叠加
var base_color: Color = Color.WHITE:
	set(value):
		base_color = value
		_dirty = true

var _meshes: Array[MeshInstance3D] = []
var _toon_materials: Dictionary = {} # "mesh_instance_id:surface" -> ShaderMaterial

## 表情贴图覆盖：mesh instance_id -> { tex, surf }（表情只贴到指定 surface，不动其它）
var face_textures: Dictionary = {}   # instance_id -> {tex, surf}
## 脸片 UV 缩放（表情刚好一张铺满脸片，避免平铺/错位）；由 face 控制器设置
var mesh_uv_scale: Vector3 = Vector3.ONE
## 脸片 UV 偏移（表情居中）
var mesh_uv_offset: Vector3 = Vector3.ZERO

func set_face_texture(mesh: MeshInstance3D, tex: Texture2D, surf: int = -1) -> void:
	if not is_instance_valid(mesh):
		return
	if tex == null:
		# 清除表情：还原所有 surface override（恢复由 _apply_all else 分支用整 mesh tint）
		if face_textures.has(mesh.get_instance_id()):
			for si in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(si, null)
			face_textures.erase(mesh.get_instance_id())
	else:
		face_textures[mesh.get_instance_id()] = { "tex": tex, "surf": surf }
	_dirty = true

func face_texture_info(mesh: MeshInstance3D) -> Dictionary:
	return face_textures.get(mesh.get_instance_id(), {})

func clear_face_textures() -> void:
	face_textures.clear()
	_dirty = true

var _paints: Dictionary = {}   # instance_id -> {color, amount, tween}
var _grays: Dictionary = {}    # instance_id -> {amount, tween}

## 脏标记：仅在颜色/贴图实际变化时才重建材质，避免每帧无意义 set_* 开销
var _dirty := false

func _ready() -> void:
	if not character_root:
		character_root = get_parent() as Node3D
	_collect_meshes()
	_dirty = true

func _process(_delta: float) -> void:
	# 有绘画/灰化 tween 在跑时，amount 每帧都在变，需要持续刷新
	if _paints.size() > 0 or _grays.size() > 0:
		_dirty = true
	if _dirty:
		_dirty = false
		_apply_all()

## 被涂上颜色，随时间褪去。parts 空 = 全身
func paint(color: Color, duration: float = 5.0, parts: Array[String] = []) -> void:
	for mesh in _filter(parts):
		var id := mesh.get_instance_id()
		var entry: Dictionary = _paints.get(id, {})
		if entry.has("tween") and entry["tween"]:
			(entry["tween"] as Tween).kill()
		entry["color"] = color
		entry["amount"] = 1.0
		var tw := create_tween()
		tw.tween_method(func(v: float): entry["amount"] = v, 1.0, 0.0, duration)
		tw.tween_callback(func() -> void: _paints.erase(id); _dirty = true)
		entry["tween"] = tw
		_paints[id] = entry
	_dirty = true
	effect_started.emit("paint")

## 石化/眩晕灰化，随时间恢复。parts 空 = 全身
func apply_gray(duration: float = 3.0, parts: Array[String] = []) -> void:
	for mesh in _filter(parts):
		var id := mesh.get_instance_id()
		var entry: Dictionary = _grays.get(id, {})
		if entry.has("tween") and entry["tween"]:
			(entry["tween"] as Tween).kill()
		entry["amount"] = 1.0
		var tw := create_tween()
		tw.tween_method(func(v: float): entry["amount"] = v, 1.0, 0.0, duration)
		tw.tween_callback(func() -> void: _grays.erase(id); _dirty = true)
		entry["tween"] = tw
		_grays[id] = entry
	_dirty = true
	effect_started.emit("gray")

## 灰头土脸：在角色身上投影一层脏污贴花，duration 秒后淡出并移除。
## Decal 自顶向下投影覆盖角色，使用手绘烟熏贴花纹理。
func apply_dirt_decal(duration: float = 6.0) -> void:
	if not character_root:
		return
	var decal := Decal.new()
	decal.texture_albedo = _get_dirt_texture()
	decal.size = Vector3(1.6, 2.4, 1.6)
	decal.modulate = Color(0.32, 0.30, 0.27)
	decal.albedo_mix = 1.0
	decal.cull_mask = 0xFFFFF
	character_root.add_child(decal)
	decal.position = Vector3(0.0, 1.1, 0.0)
	var tw := create_tween()
	tw.tween_property(decal, "modulate:a", 1.0, 0.0)
	tw.tween_interval(maxf(duration - 1.0, 0.0))
	tw.tween_property(decal, "modulate:a", 0.0, 1.0)
	tw.tween_callback(decal.queue_free)
	effect_started.emit("dirt")

## 手绘烟熏脏污纹理，静态缓存一次
static func _get_dirt_texture() -> Texture2D:
	if _dirt_texture == null:
		_dirt_texture = preload("res://assets/textures/fx/dirt_soot.png")
	return _dirt_texture

## 清除指定部位效果（空 = 全身）
func clear_effects(parts: Array[String] = []) -> void:
	var targets := _all_meshes() if parts.is_empty() else _filter(parts)
	for mesh in targets:
		var id := mesh.get_instance_id()
		if _paints.has(id):
			if _paints[id].has("tween") and _paints[id]["tween"]:
				(_paints[id]["tween"] as Tween).kill()
			_paints.erase(id)
		if _grays.has(id):
			if _grays[id].has("tween") and _grays[id]["tween"]:
				(_grays[id]["tween"] as Tween).kill()
			_grays.erase(id)
	_apply_all()

func clear_all() -> void:
	for entry in _paints.values():
		if entry.has("tween") and entry["tween"]:
			(entry["tween"] as Tween).kill()
	for entry in _grays.values():
		if entry.has("tween") and entry["tween"]:
			(entry["tween"] as Tween).kill()
	_paints.clear()
	_grays.clear()
	_apply_all()

func get_mesh_for_part(part: String) -> MeshInstance3D:
	var list := _filter([part])
	return list[0] if not list.is_empty() else null

func _collect_meshes() -> void:
	_meshes.clear()
	if character_root:
		for child in character_root.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh:
				_meshes.append(mi)

func _all_meshes() -> Array[MeshInstance3D]:
	return _meshes

func _filter(parts: Array[String]) -> Array[MeshInstance3D]:
	if parts.is_empty():
		return _meshes
	var result: Array[MeshInstance3D] = []
	for part in parts:
		var patterns: Array = PART_PATTERNS.get(part.to_lower(), [])
		for mesh in _meshes:
			var n := mesh.name.to_lower()
			var matched := false
			for p in patterns:
				if n.contains(String(p)):
					matched = true
					break
			if matched:
				if not result.has(mesh):
					result.append(mesh)
	return result

func _apply_all() -> void:
	for mesh in _meshes:
		var id := mesh.get_instance_id()
		var paint_amt: float = 0.0
		var paint_col := Color.WHITE
		if _paints.has(id):
			paint_amt = float(_paints[id].get("amount", 0.0))
			paint_col = _paints[id].get("color", Color.WHITE)
		var gray_amt: float = 0.0
		if _grays.has(id):
			gray_amt = float(_grays[id].get("amount", 0.0))
		var col := base_color
		if paint_amt > 0.0:
			col = col.lerp(paint_col, paint_amt)
		if gray_amt > 0.0:
			col = col.lerp(GRAY_COLOR, gray_amt)
		# 表情贴图：对每个 surface 单独设 override，脸片用表情、其它用玩家色
		for surface in mesh.mesh.get_surface_count():
			var texture: Texture2D = null
			if face_textures.has(id):
				var info: Dictionary = face_textures[id]
				if surface == int(info.get("surf", -1)):
					texture = info.get("tex")
			mesh.set_surface_override_material(surface, _toon_material(mesh, surface, col, texture))
		mesh.material_override = null

func _toon_material(mesh: MeshInstance3D, surface: int, color: Color, texture: Texture2D = null) -> ShaderMaterial:
	var key := "%s:%s" % [mesh.get_instance_id(), surface]
	var material := _toon_materials.get(key) as ShaderMaterial
	if material == null:
		material = PLAYER_TOON_MATERIAL.duplicate() as ShaderMaterial
		material.next_pass = _get_toon_outline_material()
		_toon_materials[key] = material
	material.set_shader_parameter(&"tint_color", color)
	material.set_shader_parameter(&"albedo_texture", texture)
	if texture:
		var uv_scale: Vector3 = mesh_uv_scale if mesh_uv_scale != Vector3.ZERO else Vector3.ONE
		material.set_shader_parameter(&"texture_uv_scale", Vector2(uv_scale.x, uv_scale.y))
		material.set_shader_parameter(&"texture_uv_offset", Vector2(mesh_uv_offset.x, mesh_uv_offset.y))
	else:
		material.set_shader_parameter(&"texture_uv_scale", Vector2.ONE)
		material.set_shader_parameter(&"texture_uv_offset", Vector2.ZERO)
	return material