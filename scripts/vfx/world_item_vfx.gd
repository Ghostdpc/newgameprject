## 职责：精简的世界空间 3D 道具反馈。
## 保留可读性最强的脚底能量圈与头顶眩晕星星，不用粒子占据同屏空间。

class_name WorldItemVfx
extends Node3D

enum Kind { FEET_RING, BANANA_STUN }

## 眩晕星星整体缩放（星本体 + 环绕半径），越小越紧凑
const STUN_SCALE := 0.6

var kind: Kind = Kind.FEET_RING
var duration := 1.0
var follow_target: Node3D
var tint := Color(1.0, 0.72, 0.10, 1.0)
var _age := 0.0
var _rings: Array[MeshInstance3D] = []
var _stars: Array[Node3D] = []

func configure(next_kind: Kind, next_duration: float, target: Node3D, color: Color = Color(1.0, 0.72, 0.10, 1.0)) -> void:
	kind = next_kind
	duration = next_duration
	follow_target = target
	tint = color

func _ready() -> void:
	if follow_target:
		global_position = follow_target.global_position
	if kind == Kind.BANANA_STUN:
		_build_stun_stars()
	else:
		_build_feet_rings()

func _process(delta: float) -> void:
	_age += delta
	if not is_instance_valid(follow_target):
		queue_free()
		return
	global_position = follow_target.global_position
	if kind == Kind.BANANA_STUN:
		_update_stars()
	else:
		_update_rings()
	if _age >= duration:
		queue_free()

func _build_feet_rings() -> void:
	for index in 2:
		var ring := _ring(tint.lightened(0.12 * index), 0.54 + index * 0.20, 0.62 + index * 0.20)
		ring.position.y = 0.06 + index * 0.025
		ring.scale = Vector3.ONE * (0.38 + index * 0.10)
		add_child(ring)
		_rings.append(ring)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 2.1
	light.omni_range = 3.4
	light.position = Vector3(0, 0.55, 0)
	add_child(light)

func _update_rings() -> void:
	for index in _rings.size():
		var ring := _rings[index]
		var phase := _age * (3.0 + index * 0.8) + index
		var scale := 0.82 + sin(phase) * 0.14 + index * 0.18
		ring.scale = Vector3(scale, 1.0, scale)
		ring.rotation.y += 0.06 + index * 0.03

func _build_stun_stars() -> void:
	for index in 6:
		var star := Node3D.new()
		var horizontal := _box(Color(1.0, 0.84, 0.08, 1.0), Vector3(0.42, 0.09, 0.12))
		var vertical := _box(Color(1.0, 0.94, 0.38, 1.0), Vector3(0.12, 0.42, 0.09))
		star.add_child(horizontal)
		star.add_child(vertical)
		star.scale = Vector3.ONE * STUN_SCALE
		add_child(star)
		_stars.append(star)

func _update_stars() -> void:
	for index in _stars.size():
		var star := _stars[index]
		var angle := _age * 5.2 + float(index) * TAU / float(_stars.size())
		star.position = Vector3(cos(angle) * 0.70 * STUN_SCALE, 2.10 + sin(_age * 6.2 + index) * 0.13, sin(angle) * 0.70 * STUN_SCALE)
		star.rotation = Vector3(0.0, -angle, angle * 1.4)

func _ring(color: Color, inner_radius: float, outer_radius: float) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 32
	mesh.ring_segments = 12
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _glow_material(color)
	return instance

func _box(color: Color, box_size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _glow_material(color)
	return instance

func _glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 3.0
	return material
