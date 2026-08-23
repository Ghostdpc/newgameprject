extends SceneTree

## 生成贴合 human 头部前脸的弧面皮肤 mesh（不是头盔！只覆盖面部前侧一段弧）
## 头部实测范围（mesh 局部坐标）：x:[-0.101,0.070] y:[-0.116,0.111] z:[0.113,0.251]
## 球心约 (0.013, 0, 0.182)，面朝 +Z
func _init() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs_v := 12      # 纵向分段
	var segs_h := 24      # 横向分段
	var radius := 0.155   # 略大于头部
	var center := Vector3.ZERO  # head 骨局部原点
	# 只覆盖前脸：方位角 -75°~+75°(150° 弧)，仰角 -45°~+45°
	var az_min := deg_to_rad(-75.0)
	var az_max := deg_to_rad(75.0)
	var el_min := deg_to_rad(-45.0)
	var el_max := deg_to_rad(45.0)
	for yi in range(segs_v):
		for xi in range(segs_h):
			var a0: float = lerpf(az_min, az_max, float(xi) / segs_h)
			var a1: float = lerpf(az_min, az_max, float(xi + 1) / segs_h)
			var e0: float = lerpf(el_min, el_max, float(yi) / segs_v)
			var e1: float = lerpf(el_min, el_max, float(yi + 1) / segs_v)
			var p00 := center + _sphere(radius, a0, e0)
			var p01 := center + _sphere(radius, a0, e1)
			var p10 := center + _sphere(radius, a1, e0)
			var p11 := center + _sphere(radius, a1, e1)
			var u0 := float(xi) / segs_h; var u1 := float(xi + 1) / segs_h
			var v0 := float(yi) / segs_v; var v1 := float(yi + 1) / segs_v
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u0, v1)); st.add_vertex(p01)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u0, v0)); st.add_vertex(p00)
			st.set_uv(Vector2(u1, v1)); st.add_vertex(p11)
			st.set_uv(Vector2(u1, v0)); st.add_vertex(p10)
	var mesh: ArrayMesh = st.commit()
	var err := ResourceSaver.save(mesh, "res://assets/models/face_mask_hemisphere.mesh")
	print("save err=", err, " aabb=", mesh.get_aabb())
	quit()

func _sphere(r: float, azimuth: float, elev: float) -> Vector3:
	# 面朝 +Z（azimuth 绕 Y，elev 绕 X）
	return Vector3(r * cos(elev) * sin(azimuth), r * sin(elev), r * cos(elev) * cos(azimuth))
