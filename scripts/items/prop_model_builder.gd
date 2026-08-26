## 职责：从配置路径构建道具 3D 模型节点（载入 fbx/glb + 套贴图 + 自适应缩放居中）
## ItemBox / TrapInstance 共用，避免重复的模型装配逻辑

class_name PropModelBuilder
extends RefCounted

## 依模型路径构建可视节点，贴合到 target_size 立方范围内；
## 失败（路径空/载入失败/无 mesh）回传 null，由调用方回退占位方块。
##   model_path:   res:// 模型路径（fbx/glb 导入为 PackedScene）
##   texture_path: res:// 贴图路径，空 = 用模型自带材质
##   target_size:  自适应后模型最长边的目标尺寸（米）
##   scale_mult:   在自适应基础上的额外缩放系数（配置 model_scale）
##   align_bottom: true = 模型底部贴到原点 y=0（放置物平铺地面），false = 几何中心居中
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
		# 居中：把 AABB 中心移到原点；align_bottom 时再下移半高使底部贴地
		var center := aabb.get_center()
		model.position = -center * fit
		if align_bottom:
			model.position.y += (aabb.size.y * 0.5) * fit
	return root

## 手动递归收集 MeshInstance3D，用 is 替代 find_children 类名字符串
## （未入树的实例上 find_children 类型过滤在 Godot 4 有时失效）
static func _collect_meshes(node: Node) -> Array:
	var result: Array = []
	_collect_meshes_recursive(node, result)
	return result

static func _collect_meshes_recursive(node: Node, result: Array) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_meshes_recursive(child, result)

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

## 在 model 局部空间计算所有 mesh 的合并 AABB（节点未入树，手动累加变换，不用 global_transform）
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

## node 相对 root 的累加变换（沿父链连乘 transform，适用于未入树的实例）
static func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t
