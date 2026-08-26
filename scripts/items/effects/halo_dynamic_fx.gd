## 职责：光环炫酷光效 —— 彩虹流光 + 脉冲闪烁 + 粒子光晕
## 挂在光环（halo）装备物节点上，_process 每帧驱动：
##  - 材质 emission 颜色 Hue 循环（彩虹流）
##  - emission 强度正弦脉冲（呼吸闪烁）
##  - 粒子光晕（GPUParticles3D 光尘绕环）
class_name HaloDynamicFx
extends Node

var _meshes: Array[MeshInstance3D] = []
var _particles: GPUParticles3D
var _aura: GPUParticles3D
var _time: float = 0.0

func setup(host: Node3D) -> void:
	# 收集光环模型内的 mesh，保留原材质（金色 tint），只动态控制 emission
	for c in host.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat == null:
			var src: Material = mi.get_active_material(0)
			if src is StandardMaterial3D:
				mat = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
			mi.material_override = mat
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_meshes.append(mi)
	# 粒子光晕
	_particles = GPUParticles3D.new()
	_particles.name = "HaloFxParticles"
	host.add_child(_particles)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = 0.32
	pm.emission_ring_inner_radius = 0.26
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 45.0
	pm.gravity = Vector3(0, -0.3, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.7
	pm.scale_min = 0.03
	pm.scale_max = 0.09
	pm.color = Color(1.0, 1.0, 1.0)
	pm.color_ramp = _make_gradient_tex([
		Color(1.0, 0.9, 0.6, 0.9), Color(0.4, 0.6, 1.0, 0.7), Color(0.9, 0.4, 1.0, 0.6),
	])
	_particles.process_material = pm
	_particles.amount = 90
	_particles.lifetime = 1.8
	_particles.local_coords = true
	_particles.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	_particles.draw_pass_1 = quad

## 在角色根节点建立环绕身体的光尘粒子（角色周围的炫彩粒子效果）
func setup_aura(player: Node3D) -> void:
	_aura = GPUParticles3D.new()
	_aura.name = "HaloBodyAura"
	player.add_child(_aura)
	_aura.position = Vector3(0, 0.9, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.85
	pm.spread = 180.0
	pm.gravity = Vector3(0, -0.35, 0)
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.scale_min = 0.06
	pm.scale_max = 0.2
	pm.color = Color(1.0, 1.0, 1.0)
	pm.color_ramp = _make_gradient_tex([
		Color(1.0, 0.85, 0.4, 0.95), Color(0.45, 0.7, 1.0, 0.7), Color(1.0, 0.45, 0.9, 0.55),
	])
	_aura.process_material = pm
	_aura.amount = 200
	_aura.lifetime = 2.4
	_aura.local_coords = true
	_aura.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	_aura.draw_pass_1 = quad

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	_time += delta
	var hue := fmod(_time * 0.18, 1.0)         # 彩虹流：hue 循环
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)  # 脉冲：0~1 正弦
	var col := Color.from_hsv(hue, 0.75, 1.0)
	for mi in _meshes:
		if not is_instance_valid(mi):
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = RenderCompat.emission_energy(2.0 + pulse * 3.0)
	# 光环粒子颜色跟随彩虹（新发射粒子生效；不 restart 以保持粒子自然循环）
	var pm := _particles.process_material as ParticleProcessMaterial
	if pm and is_instance_valid(_particles):
		pm.color = col
	# 角色周围光尘粒子也跟随彩虹
	if _aura and is_instance_valid(_aura):
		var apm := _aura.process_material as ParticleProcessMaterial
		if apm:
			apm.color = col.lerp(Color(1, 1, 1), 0.4)

func _make_gradient_tex(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var cols := PackedColorArray()
	for s in stops:
		cols.append(s)
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt
