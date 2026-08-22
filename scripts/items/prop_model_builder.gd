## 職責：從配置路徑構建道具 3D 模型節點（載入 fbx/glb + 套貼圖 + 自適應縮放居中）
## ItemBox / TrapInstance 共用，避免重複的模型裝配邏輯

class_name PropModelBuilder
extends RefCounted

## 依模型路徑構建可視節點，貼合到 target_size 立方範圍內；
## 失敗（路徑空/載入失敗/無 mesh）回傳 null，由調用方回退占位方塊。
##   model_path:   res:// 模型路徑（fbx/glb 導入為 PackedScene）
##   texture_path: res:// 貼圖路徑，空 = 用模型自帶材質
##   target_size:  自適應後模型最長邊的目標尺寸（米）
##   scale_mult:   在自適應基礎上的額外縮放係數（配置 model_scale）
##   align_bottom: true = 模型底部貼到原點 y=0（放置物平鋪地面），false = 幾何中心居中
static func build(model_path: String, texture_path: String, target_size: float, scale_mult: float, align_bottom: bool = false) -> Node3D:
	if model_path.is_empty():
		return null
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_warning("PropModelBuilder: cannot load model '%s'" % model_path)
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		push_warning("PropModelBuilder: model is not Node3D '%s'" % model_path)
		return null

	var meshes := _collect_meshes(model)
	if meshes.is_empty():
		push_warning("PropModelBuilder: no MeshInstance3D in '%s'" % model_path)
		return null

	_apply_texture(meshes, texture_path)

	var root := Node3D.new()
	root.name = "ModelRoot"
	root.add_child(model)

	var aabb := _combined_aabb(model, meshes)
	if aabb.size.length() > 0.0001:
		var longest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		var fit: float = (target_size / longest) if longest > 0.0 else 1.0
		fit *= scale_mult
		model.scale = Vector3(fit, fit, fit)
		# 居中：把 AABB 中心移到原點；align_bottom 時再下移半高使底部貼地
		var center := aabb.get_center()
		model.position = -center * fit
		if align_bottom:
			model.position.y += (aabb.size.y * 0.5) * fit
	return root

static func _collect_meshes(node: Node) -> Array:
	var result: Array = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		result.append(child)
	return result

static func _apply_texture(meshes: Array, texture_path: String) -> void:
	if texture_path.is_empty():
		return
	var tex := load(texture_path) as Texture2D
	if tex == null:
		push_warning("PropModelBuilder: cannot load texture '%s'" % texture_path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	for m in meshes:
		(m as MeshInstance3D).material_override = mat

## 在 model 局部空間計算所有 mesh 的合併 AABB（節點未入樹，手動累加變換，不用 global_transform）
static func _combined_aabb(model: Node3D, meshes: Array) -> AABB:
	var result := AABB()
	var has_any := false
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := _transform_to_root(mi, model)
		var box := mi.get_aabb()
		for i in range(8):
			var corner := box.position + Vector3(
				box.size.x * float(i & 1),
				box.size.y * float((i >> 1) & 1),
				box.size.z * float((i >> 2) & 1))
			var p := local * corner
			if not has_any:
				result = AABB(p, Vector3.ZERO)
				has_any = true
			else:
				result = result.expand(p)
	return result

## node 相對 root 的累加變換（沿父鏈連乘 transform，適用於未入樹的實例）
static func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t
