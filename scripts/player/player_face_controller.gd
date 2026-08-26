## 职责：表情贴脸。用 Sprite3D billboard 贴在 head 骨骼前侧，跟随动画/布娃娃。
## - 附著点：BoneAttachment3D 挂到 Skeleton3D 的 head 骨
## - 表情图：res://assets/textures/faces 下所有 face_N.png，每张即单一表情
## - 懒加载：只解码当前显示的表情，避免 209 张大图全占显存

class_name PlayerFaceController
extends Node

const IMAGE_FOLDER := "res://assets/textures/faces"
## 半球面具 mesh（贴死在 head 骨曲面，任何角度不穿帮）—— use_face_mask 开启时替代 Sprite3D
const FACE_MASK_MESH := "res://assets/models/face_mask_hemisphere.mesh"

## 是否用半球面具贴肤替代平面 Sprite（贴死头部曲面）
## 面具绑 head 骨，飞扑/软倒时也紧贴头骨不穿帮。默认关闭，保留原平面方案。
@export var use_face_mask: bool = false

## 贴面距离：表情离骨心沿骨骼前向(-Z)的前方距离（世界单位）
const FACE_DISTANCE := 0.42
## 贴面高度：沿骨上轴(+Y)上移到脸部中央
const FACE_UP := 0.50
## Sprite 显示高度（世界单位）
const ICON_HEIGHT := 0.09
## face layer（不在拍照 RT，避免占分）——沿用 UI 标识层
const FACE_LAYER := 4

## 贴皮模式的表情局部偏移（相对头骨），顶层缩放/位移参数，方便外部微调
## 调试后默认值（2026-08-23）：(-0.16, -0.62, 0.04) + 旋转 (0, -90°, 0)
@export var bone_offset: Vector3 = Vector3(-0.16, -0.62, 0.04)
## 贴皮模式的 Sprite 局部旋转（弧度）
@export var bone_rotation: Vector3 = Vector3(0.0, deg_to_rad(-90.0), 0.0)
## 半球面具的局部旋转（弧度）—— 由 tools/calc_face_geom.gd 自动算得，让面具 +Z 对齐面部
@export var mask_rotation: Vector3 = Vector3(deg_to_rad(40.95), deg_to_rad(132.77), 0.0)

## 表情所挂的骨（预设 head；找不到时用 fallback_attach 节点）
## 支援多候选：依序尝试，命中第一个存在的骨（head → Human 的头骨 → 骨骼.004 等 Blender 预设名）
@export var bone_names: Array[String] = ["head", "骨骼.005_end_end_end_end", "骨骼.004"]
## 退路：attach 到指定节点上（挂骨失败时）。通常传角色根节点。
@export var fallback_attach: Node3D
## 退路偏移（相对 fallback_attach 局部坐标）
@export var fallback_offset: Vector3 = Vector3(0.0, 2.2, 0.0):
	set(value):
		fallback_offset = value
		if _sprite and _used_fallback:
			_sprite.position = value
## 退路模式是否面向相机（billboard）—— 预设 false，改为固定朝向贴脸
@export var fallback_billboard: bool = false
## 退路固定朝向：使纹理面(+Z)朝向此世界方向（billboard=false 时用）。未设定则朝 fallback_offset 反方向? 用此值。
@export var fallback_facing: Vector3 = Vector3(1, 0, 0)

signal expression_changed(id: String, total: int)

var skeleton: Skeleton3D
var _attachment: Node3D
var _sprite: Node3D
var _paths: Array[String] = []
var _cache: Dictionary = {}
var _current_index: int = -1
var _used_fallback: bool = false
## 服装贴图宿主（apply_garment_attach 时使用）
var _garment_host: MeshInstance3D = null
## 头部材质宿主（apply_head_texture 时使用）
var _head_mi: MeshInstance3D = null
var _head_surf: int = -1
## 脸片 UV 缩放/偏移（表情一张铺满用）
var _face_uv_scale: Vector3 = Vector3.ONE
var _face_uv_offset: Vector3 = Vector3.ZERO
## 贴头材前的原 material_override（还原用）
var _head_prev_override: Material = null

## 是否把表情贴纸附著到头部服装（玩家穿上的"脸"服装）而非贴头骨。开启时优先挂服装。
## 验证用：假设美术做的"脸"是帽子槽服装，表情贴到它上面，随服装/头部移动。
@export var attach_to_garment: bool = false
## 是否直接把表情贴到模型头部材质（如 newhuman 有独立头部 mesh/UV 的模型）。开启时替换头部外表材质。
@export var use_head_texture: bool = false

## 直接把表情图贴到模型头部 mesh 的材质（利用独立头部 UV/surface）。
## 适用 newhuman 这类头部有独立 UV 岛/材质的模型。返回是否成功。
func apply_head_texture() -> bool:
	if use_head_texture == false:
		return false
	if _paths.is_empty():
		# 确保已扫描表情素材（打包版 pck 内 DirAccess 可能扫不到 → count 0 → 回退）
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
	# 找头部表面：优先「独立小面片」（多-surface mesh 中顶点最少的），即美术加的 mesh 脸。
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
	# 打包版 DirAccess 可能扫不到 pck 内表情素材 → count()==0, 此时不贴脸回退平面, 避免越界崩溃
	if count() <= 0:
		return false
	# 计算脸片 UV 范围 → 表情材质的 uv1_scale/offset（一张铺满，避免平铺/半张）
	_calc_face_uv_scale(head_mi, head_surf)
	if _sprite:
		_sprite.visible = false
	_head_mi = head_mi
	_head_surf = head_surf
	if _current_index < 0 and count() > 0:
		_current_index = 0
	_apply_head_texture(maxi(_current_index, 0))
	return true

## 统计脸片 UV 范围，得出让表情一张铺满的 uv1_scale/offset
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

## 把表情图设为头部 surface 材质 albedo
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
	# 经由 CharacterEffects 应用：玩家色 + 表情纹理，避免被每帧 tint 覆盖
	var player := get_parent() as PlayerController
	if player and player.character_effects:
		var tex := (mat as StandardMaterial3D).albedo_texture
		player.character_effects.mesh_uv_scale = _face_uv_scale
		player.character_effects.mesh_uv_offset = _face_uv_offset
		player.character_effects.set_face_texture(_head_mi, tex, _head_surf)
	else:
		if _head_surf >= 0 and _head_surf < _head_mi.mesh.get_surface_count():
			_head_mi.set_surface_override_material(_head_surf, mat)

## 还原头部材质（卸下头部贴图模式）
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

## 把表情图直接贴到玩家已穿服装的材质上（服装即"脸"）。返回是否成功。
## 不建 Sprite —— 表情变成服装的 albedo 贴图，长在 mesh 表面不穿帮。
## 需 face 是 PlayerController 直接子节点（Player/Face）
func apply_garment_attach() -> bool:
	if attach_to_garment == false:
		return false
	var player := get_parent() as PlayerController
	if player == null or player.outfit_manager == null:
		return false
	# 找服装节点下的 mesh（优先帽子槽，头部载体）
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
	# 隐藏旧 sprite（若存在）
	if _sprite:
		_sprite.visible = false
	# 附著后自动显示一个表情
	if _current_index < 0 and count() > 0:
		_current_index = 0
	_apply_garment_texture(maxi(_current_index, 0))
	return true

## 把表情图设为服装材质 albedo
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

## 卸下服装贴图模式：还原服装材质，恢复 sprite 贴骨
func detach_garment(new_skel: Skeleton3D) -> void:
	# 还原服装 override 材质
	if _garment_host:
		for i in _garment_host.mesh.get_surface_count():
			_garment_host.set_surface_override_material(i, null)
	_garment_host = null
	attach_to_garment = false
	# 重建 sprite 到头骨
	if _sprite:
		_sprite.queue_free()
	_sprite = null
	if new_skel:
		_used_fallback = false
		setup(new_skel)
	if _current_index >= 0:
		show_expression(_current_index)

## 让外部（如 PlayerController._setup_model）注入骨架
func setup(skel: Skeleton3D) -> void:
	skeleton = skel
	var bound_bone := _find_bone_name()
	if bound_bone != "":
		# 有具名头骨：BoneAttachment 挂骨，表情随头转（贴皮）
		var att := BoneAttachment3D.new()
		att.name = "FaceAttachment"
		att.bone_name = bound_bone
		skeleton.add_child(att)
		_sprite = _new_display(false)
		_sprite.rotation = mask_rotation if use_face_mask else bone_rotation
		_sprite.position = bone_offset
		att.add_child(_sprite)
	else:
		# 无具名头骨（Human 等）：挂到 fallback_attach 节点用固定偏移
		var host: Node3D = fallback_attach if fallback_attach else skeleton.get_parent()
		if host == null:
			host = skeleton
		_used_fallback = true
		_sprite = _new_display(fallback_billboard)
		_sprite.position = fallback_offset
		host.add_child(_sprite)
		if not fallback_billboard:
			# 固定朝向：让纹理面(+Z)朝 fallback_facing 方向（贴脸平面）；入树后 global 才可靠
			_sprite.look_at(_sprite.global_position + fallback_facing.normalized(), Vector3.UP)
	_index_files()

## 回传第一个存在于骨架的候选骨名；全缺回传空字串
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

## 扫描表情资料夹：每张 png 即一个表情。
## 打包版 PCK 内 DirAccess 无法遍历目录(get_files 空)，改用显式探测 face_N.png（N=1..MAX）
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
	# 打包版 DirAccess 遍历可能为空 → 显式探测已知序列 face_1..face_N
	if _paths.is_empty():
		for i in range(1, 300):
			var fn := "face_%d.png" % i
			if ResourceLoader.exists(IMAGE_FOLDER + "/" + fn):
				_paths.append(fn)
			elif i > 2:  # 连续缺失即停止
				break
	_paths.sort()
	expression_changed.emit("", _paths.size())

func count() -> int:
	return _paths.size()

## 显示第 index 个表情；index 超出范围时绕回；-1 清除
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
	# 服装贴图模式：直接换服装材质，不走 sprite
	if attach_to_garment and _garment_host != null:
		_apply_garment_texture(index)
		return
	# 头部材质模式：直接换头部 surface 材质
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

## 懒加载单张表情图（带快取，原图 2000px 缩到 512 以下省显存）
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

## 调试用：挪动表情位置（fallback 模式改 fallback_offset；贴皮模式改 bone_offset，两者皆同步 sprite）
func nudge_offset(delta: Vector3) -> void:
	if not _sprite:
		return
	if _used_fallback:
		fallback_offset += delta
	else:
		bone_offset += delta
		_sprite.position = bone_offset

## 调试用：旋转表情朝向（fallback 固定朝向模式 / 贴皮模式皆有效）
func nudge_facing(delta_deg: float) -> void:
	if not _sprite:
		return
	if fallback_billboard:
		return
	_sprite.rotate_y(deg_to_rad(delta_deg))

## 调试用：俯仰旋转（绕局部 X 轴）
func nudge_pitch(delta_deg: float) -> void:
	if not _sprite:
		return
	_sprite.rotate_x(deg_to_rad(delta_deg))

## 调试用：滚动旋转（绕局部 Z 轴）
func nudge_roll(delta_deg: float) -> void:
	if not _sprite:
		return
	_sprite.rotate_z(deg_to_rad(delta_deg))

## 调试用：回读当前偏移与旋转，供外部显示微调数值
func debug_info() -> String:
	if not _sprite:
		return "无 sprite"
	var off := fallback_offset if _used_fallback else bone_offset
	var rot := _sprite.rotation_degrees
	var mode := "fallback" if _used_fallback else "贴皮"
	return "%s off=(%.3f, %.3f, %.3f) rot=(%.1f, %.1f, %.1f)" % [
		mode, off.x, off.y, off.z, rot.x, rot.y, rot.z]
