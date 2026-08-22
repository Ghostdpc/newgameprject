## 職責：角色視覺狀態效果——繪畫著色（paint）與灰化（stun gray）。
## 支持按部位施加（受擊處局部變色），部位以 MeshInstance3D 名字匹配。
## 效果疊加在角色 mesh 上，恢復時還原原始材質。

class_name CharacterEffects
extends Node

signal effect_started(effect: String)
signal effect_finished(effect: String)

const GRAY_COLOR := Color(0.4, 0.4, 0.45, 1.0)

## 臟污貼花（灰頭土臉）：程序噪聲紋理，全場靜態緩存複用
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

var _base_materials: Dictionary = {}  # instance_id -> 初始材質
var _meshes: Array[MeshInstance3D] = []

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
## 用程序生成的噪聲紋理（無需美術資源），Decal 自頂向下投影覆蓋角色。
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

## 程序生成臟污噪聲紋理（cellular 斑塊 + alpha 漸變），靜態緩存一次
static func _get_dirt_texture() -> Texture2D:
	if _dirt_texture:
		return _dirt_texture
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.08
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.2, 0.19, 0.17, 0.0))
	ramp.set_color(1, Color(0.2, 0.19, 0.17, 0.9))
	ramp.add_point(0.5, Color(0.25, 0.23, 0.2, 0.5))
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.noise = noise
	nt.color_ramp = ramp
	_dirt_texture = nt
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
		mesh.material_override = _make_tinted_material(mesh, col)

func _initial_material(mesh: MeshInstance3D) -> Material:
	var id := mesh.get_instance_id()
	if not _base_materials.has(id):
		_base_materials[id] = mesh.get_active_material(0)
	return _base_materials[id]

func _make_tinted_material(mesh: MeshInstance3D, color: Color) -> Material:
	var src: Material = _initial_material(mesh)
	if src:
		var mat: Material = src.duplicate()
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).albedo_color = color
		return mat
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = color
	return mat2
