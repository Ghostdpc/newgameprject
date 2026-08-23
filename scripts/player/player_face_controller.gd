## 職責：表情貼臉。用 Sprite3D billboard 貼在 head 骨骼前側，跟隨動畫/布娃娃。
## - 附著點：BoneAttachment3D 掛到 Skeleton3D 的 head 骨
## - 表情圖：res://assets/textures/faces 下所有 face_N.png，每張即單一表情
## - 懶加載：只解碼當前顯示的表情，避免 209 張大圖全佔顯存

class_name PlayerFaceController
extends Node

const IMAGE_FOLDER := "res://assets/textures/faces"
## 半球面具 mesh（貼死在 head 骨曲面，任何角度不穿幫）—— use_face_mask 開啟時替代 Sprite3D
const FACE_MASK_MESH := "res://assets/models/face_mask_hemisphere.mesh"

## 是否用半球面具貼膚替代平面 Sprite（貼死頭部曲面）
## 面具綁 head 骨，飛撲/軟倒時也緊貼頭骨不穿幫。默認關閉，保留原平面方案。
@export var use_face_mask: bool = false

## 貼面距離：表情離骨心沿骨骼前向(-Z)的前方距離（世界單位）
const FACE_DISTANCE := 0.42
## 貼面高度：沿骨上軸(+Y)上移到臉部中央
const FACE_UP := 0.50
## Sprite 顯示高度（世界單位）
const ICON_HEIGHT := 0.09
## face layer（不在拍照 RT，避免占分）——沿用 UI 標識層
const FACE_LAYER := 4

## 貼皮模式的表情局部偏移（相對頭骨），頂層縮放/位移參數，方便外部微調
## 調試後默認值（2026-08-23）：(-0.16, -0.62, 0.04) + 旋轉 (0, -90°, 0)
@export var bone_offset: Vector3 = Vector3(-0.16, -0.62, 0.04)
## 貼皮模式的 Sprite 局部旋轉（弧度）
@export var bone_rotation: Vector3 = Vector3(0.0, deg_to_rad(-90.0), 0.0)
## 半球面具的局部旋轉（弧度）—— 由 tools/calc_face_geom.gd 自動算得，讓面具 +Z 對齊面部
@export var mask_rotation: Vector3 = Vector3(deg_to_rad(40.95), deg_to_rad(132.77), 0.0)

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
var _sprite: Node3D
var _paths: Array[String] = []
var _cache: Dictionary = {}
var _current_index: int = -1
var _used_fallback: bool = false
## 服裝貼圖宿主（apply_garment_attach 時使用）
var _garment_host: MeshInstance3D = null
## 頭部材質宿主（apply_head_texture 時使用）
var _head_mi: MeshInstance3D = null
var _head_surf: int = -1
## 臉片 UV 縮放/偏移（表情一張鋪滿用）
var _face_uv_scale: Vector3 = Vector3.ONE
var _face_uv_offset: Vector3 = Vector3.ZERO
## 貼頭材前的原 material_override（還原用）
var _head_prev_override: Material = null

## 是否把表情貼紙附著到頭部服裝（玩家穿上的"臉"服裝）而非貼頭骨。開啟時優先掛服裝。
## 驗證用：假設美術做的"臉"是帽子槽服裝，表情貼到它上面，隨服裝/頭部移動。
@export var attach_to_garment: bool = false
## 是否直接把表情貼到模型頭部材質（如 newhuman 有獨立頭部 mesh/UV 的模型）。開啟時替換頭部外表材質。
@export var use_head_texture: bool = false

## 直接把表情圖貼到模型頭部 mesh 的材質（利用独立头部 UV/surface）。
## 適用 newhuman 這類頭部有獨立 UV 島/材質的模型。返回是否成功。
func apply_head_texture() -> bool:
	if use_head_texture == false:
		return false
	if _paths.is_empty():
		# 確保已掃描表情素材（打包版 pck 內 DirAccess 可能掃不到 → count 0 → 回退）
		_index_files()
		if _paths.is_empty():
			return false
	var player := get_parent() as PlayerController
	if player == null:
		return false
	var root := player.get_node_or_null("Model") as Node
	if root == null:
		root = get_parent().get_node_or_null("Model") as Node
	if root == null:
		return false
	# 找頭部表面：優先「獨立小面片」（多-surface mesh 中頂點最少的），即美術加的 mesh 臉。
	var head_mi: MeshInstance3D = null
	var head_surf := -1
	var best_verts := 9e9
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		if m.mesh.get_surface_count() < 2:
			continue
		for i in m.mesh.get_surface_count():
			var a := m.mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if verts.size() < best_verts:
				best_verts = verts.size()
				head_mi = m
				head_surf = i
	if head_mi == null or head_surf < 0:
		return false
	# 打包版 DirAccess 可能掃不到 pck 內表情素材 → count()==0, 此時不貼臉回退平面, 避免越界崩潰
	if count() <= 0:
		return false
	# 計算臉片 UV 範圍 → 表情材質的 uv1_scale/offset（一張鋪滿，避免平鋪/半張）
	_calc_face_uv_scale(head_mi, head_surf)
	if _sprite:
		_sprite.visible = false
	_head_mi = head_mi
	_head_surf = head_surf
	if _current_index < 0 and count() > 0:
		_current_index = 0
	_apply_head_texture(maxi(_current_index, 0))
	return true

## 統計臉片 UV 範圍，得出讓表情一張鋪滿的 uv1_scale/offset
func _calc_face_uv_scale(mi: MeshInstance3D, surf: int) -> void:
	_face_uv_scale = Vector3.ONE
	_face_uv_offset = Vector3.ZERO
	if mi == null or mi.mesh == null:
		return
	if surf < 0 or surf >= mi.mesh.get_surface_count():
		return
	var a := mi.mesh.surface_get_arrays(surf)
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	if uvs.size() == 0:
		return
	var minu := 9e9; var maxu := -9e9; var minv := 9e9; var maxv := -9e9
	for uv in uvs:
		minu = min(minu, uv.x); maxu = max(maxu, uv.x)
		minv = min(minv, uv.y); maxv = max(maxv, uv.y)
	var rangeu := maxf(maxu - minu, 1e-4)
	var rangev := maxf(maxv - minv, 1e-4)
	_face_uv_scale = Vector3(1.0 / rangeu, 1.0 / rangev, 1.0)
	_face_uv_offset = Vector3(-minu / rangeu, -minv / rangev, 0.0)

## 把表情圖設為頭部 surface 材質 albedo
func _apply_head_texture(index: int) -> void:
	if _head_mi == null:
		return
	var tex := _get_texture(index)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_apply_head_material(mat)

func _apply_head_material(mat: Material) -> void:
	if _head_mi == null:
		return
	# 經由 CharacterEffects 應用：玩家色 + 表情紋理，避免被每幀 tint 覆蓋
	var player := get_parent() as PlayerController
	if player and player.character_effects:
		var tex := (mat as StandardMaterial3D).albedo_texture
		player.character_effects.mesh_uv_scale = _face_uv_scale
		player.character_effects.mesh_uv_offset = _face_uv_offset
		player.character_effects.set_face_texture(_head_mi, tex, _head_surf)
	else:
		if _head_surf >= 0 and _head_surf < _head_mi.mesh.get_surface_count():
			_head_mi.set_surface_override_material(_head_surf, mat)

## 還原頭部材質（卸下頭部貼圖模式）
func revert_head_texture() -> void:
	var player := get_parent() as PlayerController
	if player and player.character_effects and _head_mi:
		player.character_effects.set_face_texture(_head_mi, null)
	else:
		if _head_mi != null and _head_surf >= 0 and _head_surf < _head_mi.mesh.get_surface_count():
			_head_mi.set_surface_override_material(_head_surf, null)
	_head_mi = null
	_head_surf = -1
	use_head_texture = false

## 把表情圖直接貼到玩家已穿服裝的材質上（服裝即"臉"）。返回是否成功。
## 不建 Sprite —— 表情變成服裝的 albedo 貼圖，長在 mesh 表面不穿幫。
## 需 face 是 PlayerController 直接子節點（Player/Face）
func apply_garment_attach() -> bool:
	if attach_to_garment == false:
		return false
	var player := get_parent() as PlayerController
	if player == null or player.outfit_manager == null:
		return false
	# 找服裝節點下的 mesh（優先帽子槽，頭部載體）
	var host: Node3D = null
	for slot in ["hat_slot", "shirt_slot", "accessory_slot"]:
		var item := player.outfit_manager.get_item(slot)
		if item is Node3D:
			host = item as Node3D
			break
	if host == null:
		return false
	var garment_mesh: MeshInstance3D = null
	for child in host.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh and mi.mesh.get_surface_count() > 0:
			garment_mesh = mi
			break
	if garment_mesh == null:
		return false
	_garment_host = garment_mesh
	# 隱藏舊 sprite（若存在）
	if _sprite:
		_sprite.visible = false
	# 附著後自動顯示一個表情
	if _current_index < 0 and count() > 0:
		_current_index = 0
	_apply_garment_texture(maxi(_current_index, 0))
	return true

## 把表情圖設為服裝材質 albedo
func _apply_garment_texture(index: int) -> void:
	if _garment_host == null:
		return
	var tex := _get_texture(index)
	for i in _garment_host.mesh.get_surface_count():
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = Color.WHITE
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_garment_host.set_surface_override_material(i, mat)

## 卸下服裝貼圖模式：還原服裝材質，恢復 sprite 貼骨
func detach_garment(new_skel: Skeleton3D) -> void:
	# 還原服裝 override 材質
	if _garment_host:
		for i in _garment_host.mesh.get_surface_count():
			_garment_host.set_surface_override_material(i, null)
	_garment_host = null
	attach_to_garment = false
	# 重建 sprite 到頭骨
	if _sprite:
		_sprite.queue_free()
	_sprite = null
	if new_skel:
		_used_fallback = false
		setup(new_skel)
	if _current_index >= 0:
		show_expression(_current_index)

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
		_sprite = _new_display(false)
		_sprite.rotation = mask_rotation if use_face_mask else bone_rotation
		_sprite.position = bone_offset
		att.add_child(_sprite)
	else:
		# 無具名頭骨（Human 等）：掛到 fallback_attach 節點用固定偏移
		var host: Node3D = fallback_attach if fallback_attach else skeleton.get_parent()
		if host == null:
			host = skeleton
		_used_fallback = true
		_sprite = _new_display(fallback_billboard)
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

func _new_display(billboard: bool) -> Node3D:
	if use_face_mask:
		var m := MeshInstance3D.new()
		m.name = "FaceMask"
		m.mesh = load(FACE_MASK_MESH) as ArrayMesh
		m.layers = FACE_LAYER
		m.visible = false
		return m
	var s := Sprite3D.new()
	s.name = "FaceSprite"
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	s.no_depth_test = false
	s.layers = FACE_LAYER
	s.visible = false
	return s

## 掃描表情資料夾：每張 png 即一個表情。
## 打包版 PCK 內 DirAccess 無法遍歷目錄(get_files 空)，改用顯式探測 face_N.png（N=1..MAX）
func _index_files() -> void:
	_paths.clear()
	var dir := DirAccess.open(IMAGE_FOLDER)
	if dir:
		for f in dir.get_files():
			if not f.ends_with(".png"):
				continue
			if f.contains("_dup.png") or f.contains("(1).png"):
				continue
			if f not in _paths:
				_paths.append(f)
	# 打包版 DirAccess 遍歷可能為空 → 顯式探測已知序列 face_1..face_N
	if _paths.is_empty():
		for i in range(1, 300):
			var fn := "face_%d.png" % i
			if ResourceLoader.exists(IMAGE_FOLDER + "/" + fn):
				_paths.append(fn)
			elif i > 2:  # 連續缺失即停止
				break
	_paths.sort()
	expression_changed.emit("", _paths.size())

func count() -> int:
	return _paths.size()

## 顯示第 index 個表情；index 超出範圍時繞回；-1 清除
func show_expression(index: int) -> void:
	SoundMgr.play("emote", true)
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
	# 服裝貼圖模式：直接換服裝材質，不走 sprite
	if attach_to_garment and _garment_host != null:
		_apply_garment_texture(index)
		return
	# 頭部材質模式：直接換頭部 surface 材質
	if use_head_texture and _head_mi != null:
		_apply_head_texture(index)
		return
	if not _sprite:
		return
	if _sprite is MeshInstance3D:
		var tex := _get_texture(index)
		var m := _sprite as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = Color.WHITE
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, mat)
	else:
		var sp := _sprite as Sprite3D
		sp.texture = _get_texture(index)
		sp.pixel_size = ICON_HEIGHT / float(maxi(sp.texture.get_height(), 1))
		sp.scale = Vector3.ONE
	_sprite.visible = true

## 懶加載單張表情圖（帶快取，原圖 2000px 縮到 512 以下省顯存）
const MAX_EDGE := 512

func _get_texture(index: int) -> Texture2D:
	if _paths.is_empty():
		return null
	index = clampi(index, 0, _paths.size() - 1)
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

## 調試用：滾動旋轉（繞局部 Z 軸）
func nudge_roll(delta_deg: float) -> void:
	if not _sprite:
		return
	_sprite.rotate_z(deg_to_rad(delta_deg))

## 調試用：回讀當前偏移與旋轉，供外部顯示微調數值
func debug_info() -> String:
	if not _sprite:
		return "無 sprite"
	var off := fallback_offset if _used_fallback else bone_offset
	var rot := _sprite.rotation_degrees
	var mode := "fallback" if _used_fallback else "貼皮"
	return "%s off=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f)" % [
		mode, off.x, off.y, off.z, rot.x, rot.y, rot.z]
