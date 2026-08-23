## 職責：角色視覺狀態效果——繪畫著色（paint）與灰化（stun gray）。
## 支持按部位施加（受擊處局部變色），部位以 MeshInstance3D 名字匹配。
## 效果疊加在角色 mesh 上，恢復時還原原始材質。

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

## 臟污貼花（灰頭土臉）：手繪煙熏紋理，全場靜態緩存複用
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

## 角色基礎色（玩家色），paint/gray 在此之上疊加
var base_color: Color = Color.WHITE:
	set(value):
		base_color = value
		_apply_all()

var _meshes: Array[MeshInstance3D] = []
var _toon_materials: Dictionary = {} # "mesh_instance_id:surface" -> ShaderMaterial

## 表情貼圖覆蓋：mesh instance_id -> { tex, surf }（表情只貼到指定 surface，不動其它）
var face_textures: Dictionary = {}   # instance_id -> {tex, surf}
## 臉片 UV 縮放（表情剛好一張鋪滿臉片，避免平鋪/錯位）；由 face 控制器設置
var mesh_uv_scale: Vector3 = Vector3.ONE
## 臉片 UV 偏移（表情居中）
var mesh_uv_offset: Vector3 = Vector3.ZERO

func set_face_texture(mesh: MeshInstance3D, tex: Texture2D, surf: int = -1) -> void:
	if not is_instance_valid(mesh):
		return
	if tex == null:
		# 清除表情：還原所有 surface override（恢復由 _apply_all else 分支用整 mesh tint）
		if face_textures.has(mesh.get_instance_id()):
			for si in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(si, null)
			face_textures.erase(mesh.get_instance_id())
	else:
		face_textures[mesh.get_instance_id()] = { "tex": tex, "surf": surf }
	_apply_all()

func face_texture_info(mesh: MeshInstance3D) -> Dictionary:
	return face_textures.get(mesh.get_instance_id(), {})

func clear_face_textures() -> void:
	face_textures.clear()
	_apply_all()

var _paints: Dictionary = {}   # instance_id -> {color, amount, tween}
var _grays: Dictionary = {}    # instance_id -> {amount, tween}

func _ready() -> void:
	if not character_root:
		character_root = get_parent() as Node3D
	_collect_meshes()

func _process(_delta: float) -> void:
	_apply_all()

## 被塗上顏色，隨時間褪去。parts 空 = 全身
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
		entry["tween"] = tw
		_paints[id] = entry
	effect_started.emit("paint")

## 石化/眩暈灰化，隨時間恢復。parts 空 = 全身
func apply_gray(duration: float = 3.0, parts: Array[String] = []) -> void:
	for mesh in _filter(parts):
		var id := mesh.get_instance_id()
		var entry: Dictionary = _grays.get(id, {})
		if entry.has("tween") and entry["tween"]:
			(entry["tween"] as Tween).kill()
		entry["amount"] = 1.0
		var tw := create_tween()
		tw.tween_method(func(v: float): entry["amount"] = v, 1.0, 0.0, duration)
		entry["tween"] = tw
		_grays[id] = entry
	effect_started.emit("gray")

## 灰頭土臉：在角色身上投影一層臟污貼花，duration 秒後淡出並移除。
## Decal 自頂向下投影覆蓋角色，使用手繪煙熏貼花紋理。
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

## 手繪煙熏臟污紋理，靜態緩存一次
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
			_paints[id]["amount"] = 0.0
		if _grays.has(id):
			if _grays[id].has("tween") and _grays[id]["tween"]:
				(_grays[id]["tween"] as Tween).kill()
			_grays[id]["amount"] = 0.0
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
		# 表情貼圖：對每個 surface 單獨設 override，臉片用表情、其它用玩家色
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