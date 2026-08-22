## 職責：表情貼臉。用 Sprite3D billboard 貼在 head 骨骼前側，跟隨動畫/布娃娃。
## - 附著點：BoneAttachment3D 掛到 Skeleton3D 的 head 骨
## - 表情圖：res://PNG/PNG 下所有「子沐创意素材 (N).png」，每張即單一表情
## - 懶加載：只解碼當前顯示的表情，避免 209 張大圖全佔顯存

class_name PlayerFaceController
extends Node

const IMAGE_FOLDER := "res://PNG/PNG"

## 貼面距離：表情離骨心沿骨骼前向(-Z)的前方距離（世界單位）
const FACE_DISTANCE := 0.42
## 貼面高度：沿骨上軸(+Y)上移到臉部中央
const FACE_UP := 0.50
## Sprite 顯示高度（世界單位）
const ICON_HEIGHT := 0.36
## face layer（不在拍照 RT，避免占分）——沿用 UI 標識層
const FACE_LAYER := 4

## 貼皮模式的表情局部偏移（相對頭骨），頂層縮放/位移參數，方便外部微調
@export var bone_offset: Vector3 = Vector3(0.0, FACE_UP, -FACE_DISTANCE)

## 表情所掛的骨（預設 head；找不到時用 fallback_attach 節點）
## 支援多候選：依序嘗試，命中第一個存在的骨（head → Human 的頭骨 → 骨骼.004 等 Blender 預設名）
@export var bone_names: Array[String] = ["head", "骨骼.005_end_end_end_end", "骨骼.004"]
## 退路：attach 到指定節點上（掛骨失敗時）。通常傳角色根節點。
@export var fallback_attach: Node3D
## 退路偏移（相對 fallback_attach 局部坐標）
@export var fallback_offset: Vector3 = Vector3(0.0, 2.2, 0.0):
	set(value):
		fallback_offset = value
		if _sprite and _used_fallback:
			_sprite.position = value
## 退路模式是否面向相機（billboard）—— 預設 false，改為固定朝向貼臉
@export var fallback_billboard: bool = false
## 退路固定朝向：使紋理面(+Z)朝向此世界方向（billboard=false 時用）。未設定則朝 fallback_offset 反方向? 用此值。
@export var fallback_facing: Vector3 = Vector3(1, 0, 0)

signal expression_changed(id: String, total: int)

var skeleton: Skeleton3D
var _attachment: Node3D
var _sprite: Sprite3D
var _paths: Array[String] = []
var _cache: Dictionary = {}
var _current_index: int = -1
var _used_fallback: bool = false

## 讓外部（如 PlayerController._setup_model）注入骨架
func setup(skel: Skeleton3D) -> void:
	skeleton = skel
	var bound_bone := _find_bone_name()
	if bound_bone != "":
		# 有具名頭骨：BoneAttachment 掛骨，表情隨頭轉（貼皮）
		var att := BoneAttachment3D.new()
		att.name = "FaceAttachment"
		att.bone_name = bound_bone
		skeleton.add_child(att)
		_sprite = _new_sprite(false)
		_sprite.rotation.y = PI
		_sprite.position = bone_offset
		att.add_child(_sprite)
	else:
		# 無具名頭骨（Human 等）：掛到 fallback_attach 節點用固定偏移
		var host: Node3D = fallback_attach if fallback_attach else skeleton.get_parent()
		if host == null:
			host = skeleton
		_used_fallback = true
		_sprite = _new_sprite(fallback_billboard)
		_sprite.position = fallback_offset
		host.add_child(_sprite)
		if not fallback_billboard:
			# 固定朝向：讓紋理面(+Z)朝 fallback_facing 方向（貼臉平面）；入树後 global 才可靠
			_sprite.look_at(_sprite.global_position + fallback_facing.normalized(), Vector3.UP)
	_index_files()

## 回傳第一個存在於骨架的候選骨名；全缺回傳空字串
func _find_bone_name() -> String:
	if skeleton:
		for n in bone_names:
			if skeleton.find_bone(n) != -1:
				return n
	return ""

func _new_sprite(billboard: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = "FaceSprite"
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	s.no_depth_test = false
	s.layers = FACE_LAYER
	s.visible = false
	return s

## 掃描表情資料夾：每張 png 即一個表情，捨棄 "(N)(1).png" 重複副本
func _index_files() -> void:
	_paths.clear()
	var dir := DirAccess.open(IMAGE_FOLDER)
	if dir == null:
		push_warning("PlayerFaceController: 無法開啟表情資料夾 " + IMAGE_FOLDER)
		return
	for f in dir.get_files():
		if not f.ends_with(".png"):
			continue
		if f.contains("(1).png"):
			continue
		_paths.append(f)
	_paths.sort()
	expression_changed.emit("", _paths.size())

func count() -> int:
	return _paths.size()

## 顯示第 index 個表情；index 超出範圍時繞回；-1 清除
func show_expression(index: int) -> void:
	if _paths.is_empty():
		return
	if index < -1:
		index = -1
	if index >= _paths.size():
		index %= _paths.size()
	_current_index = index
	if index == -1:
		clear()
		return
	if not _sprite:
		return
	_sprite.texture = _get_texture(index)
	_sprite.pixel_size = ICON_HEIGHT / float(maxi(_sprite.texture.get_height(), 1))
	_sprite.scale = Vector3.ONE
	_sprite.visible = true

## 懶加載單張表情圖（帶快取，原圖 2000px 縮到 512 以下省顯存）
const MAX_EDGE := 512

func _get_texture(index: int) -> Texture2D:
	var path := IMAGE_FOLDER + "/" + _paths[index]
	if _cache.has(path):
		return _cache[path]
	var tex := load(path) as Texture2D
	if tex:
		var img := tex.get_image()
		var max_edge := maxi(img.get_width(), img.get_height())
		if max_edge > MAX_EDGE:
			var f := float(MAX_EDGE) / float(max_edge)
			img.resize(clampi(int(img.get_width() * f), 1, MAX_EDGE),
				clampi(int(img.get_height() * f), 1, MAX_EDGE),
				Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex

func clear() -> void:
	if _sprite:
		_sprite.visible = false
	_current_index = -1

## 調試用：挪動表情位置（fallback 模式改 fallback_offset；貼皮模式改 bone_offset，兩者皆同步 sprite）
func nudge_offset(delta: Vector3) -> void:
	if not _sprite:
		return
	if _used_fallback:
		fallback_offset += delta
	else:
		bone_offset += delta
		_sprite.position = bone_offset

## 調試用：旋轉表情朝向（fallback 固定朝向模式 / 貼皮模式皆有效）
func nudge_facing(delta_deg: float) -> void:
	if not _sprite:
		return
	if fallback_billboard:
		return
	_sprite.rotate_y(deg_to_rad(delta_deg))

## 調試用：俯仰旋轉（繞局部 X 軸）
func nudge_pitch(delta_deg: float) -> void:
	if not _sprite:
		return
	_sprite.rotate_x(deg_to_rad(delta_deg))

## 調試用：回讀當前偏移與旋轉，供外部顯示微調數值
func debug_info() -> String:
	if not _sprite:
		return "無 sprite"
	var off := fallback_offset if _used_fallback else bone_offset
	var rot := _sprite.rotation_degrees
	var mode := "fallback" if _used_fallback else "貼皮"
	return "%s off=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f)" % [
		mode, off.x, off.y, off.z, rot.x, rot.y, rot.z]
