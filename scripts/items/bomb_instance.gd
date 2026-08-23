## 職責：炸彈實例 —— 繼承 PhysicalProp 拋出物理體，引信秒數後範圍爆炸。
## 爆炸對半徑內所有玩家施加：灰頭土臉貼花 + 積分懲罰（累加到 PlayerController.score_penalty）。
## 與 trap 系統無關：AOE 用球形距離檢測，非踩踏觸發。

class_name BombInstance
extends PhysicalProp

var _fuse: float = 1.2
var _radius: float = 3.0
var _gray_duration: float = 6.0
var _score_penalty: int = 15
## 爆炸擊飛力度倍率（相對飛撲 hit_force/hit_upward），可調
var _blast_force_mult: float = 1.4
var _blast_up_mult: float = 1.3
var _thrower: PlayerController
var _exploded: bool = false

## 由 ThrowBombEffect 調用：配置參數並拋出
func setup_bomb(p: Dictionary, thrower: PlayerController) -> void:
	_fuse          = float(p.get("fuse", 1.2))
	_radius        = float(p.get("radius", 3.0))
	_gray_duration = float(p.get("gray_duration", 6.0))
	_score_penalty = int(p.get("score_penalty", 15))
	_thrower       = thrower
	prop_mass      = 2.0
	prop_bounce    = 0.3
	prop_linear_damp = 0.4

func _ready() -> void:
	super._ready()
	# 引信計時後引爆
	var timer := get_tree().create_timer(_fuse)
	timer.timeout.connect(_explode)

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	SoundMgr.play("explode")
	_spawn_flash()
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as PlayerController
		if player == null:
			continue
		var d := global_position.distance_to(player.global_position)
		if d > _radius:
			continue
		if player.character_effects:
			player.character_effects.apply_dirt_decal(_gray_duration)
		player.score_penalty += _score_penalty
		# 爆炸物理擊飛（類似被飛撲）：按離爆心距離衰減力度，水平向外炸飛 + 上拋
		_knockback_player(player, d)
	queue_free()

## 被炸飛：進入 Fly 飛行狀態並拋出（復用飛撲對目標的擊飛機制）
func _knockback_player(player: PlayerController, dist: float) -> void:
	if player == null or player.state_machine == null:
		return
	# 爆炸方向（水平），從爆心指向玩家；靠爆心越近力度越大
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dir := to_player.normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.1, 0.0, 0.1).normalized()
	# 半徑內衰減：中心 1.0 → 邊緣 0.4
	var falloff := clampf(1.0 - dist / maxf(_radius, 0.01), 0.4, 1.0)
	var blast := TuneConfig.hit_force * _blast_force_mult * falloff
	var up := TuneConfig.hit_upward * _blast_up_mult * falloff
	player.state_machine.transition_to("Fly")
	var fly := player.state_machine.get_current_state() as FlyState
	if fly:
		fly.launch(dir * blast + Vector3.UP * up)

## 爆炸視覺：GPUParticles3D 火光+煙（代碼生成，無需美術資源）+ 橙色膨脹球占位
func _spawn_flash() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_spawn_fire_particles(scene)
	_spawn_smoke_particles(scene)
	_spawn_expand_ball(scene)

## 火光粒子：短壽命高速向外爆開，重力回落，疊加碰撞地面爆散
func _spawn_fire_particles(scene: Node) -> void:
	var fire := GPUParticles3D.new()
	fire.name = "FireBurst"
	fire.global_position = global_position
	scene.add_child(fire)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, -9.0, 0)
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 9.0
	mat.scale_min = 0.25
	mat.scale_max = 0.6
	mat.scale_curve = _make_curve_tex([Vector2(0, 0.4), Vector2(1, 1.4)])
	mat.color = Color(1.0, 0.62, 0.2)
	mat.color_ramp = _make_gradient_tex([
		Color(1.0, 0.95, 0.6), Color(1.0, 0.55, 0.15), Color(0.7, 0.15, 0.05),
	])
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	fire.process_material = mat
	fire.amount = 80
	fire.lifetime = 0.6
	fire.one_shot = true
	fire.explosiveness = 1.0
	fire.local_coords = true
	fire.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	# GPUParticles3D 須有 mesh 才渲染；用 3D 球體 + 橘黃基色（火花）
	_set_particle_mesh(fire, Color(1.0, 0.62, 0.2))
	fire.finished.connect(fire.queue_free)

## 煙粒子：慢速擴散上浮，壽命較長
func _spawn_smoke_particles(scene: Node) -> void:
	var smoke := GPUParticles3D.new()
	smoke.name = "SmokePuff"
	smoke.global_position = global_position
	scene.add_child(smoke)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.2
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.gravity = Vector3(0, -1.2, 0)
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.0
	mat.scale_min = 0.6
	mat.scale_max = 1.6
	mat.scale_curve = _make_curve_tex([Vector2(0, 0.5), Vector2(1, 2.2)])
	mat.color = Color(0.25, 0.22, 0.2)
	mat.color_ramp = _make_gradient_tex([
		Color(0.35, 0.3, 0.28, 0.85), Color(0.2, 0.18, 0.16, 0.4),
	])
	mat.damping_min = 0.5
	mat.damping_max = 1.5
	smoke.process_material = mat
	smoke.amount = 35
	smoke.lifetime = 1.6
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	smoke.local_coords = true
	smoke.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_set_particle_mesh(smoke, Color(0.45, 0.42, 0.4))
	smoke.finished.connect(smoke.queue_free)

## 給 GPUParticles3D 設 3D 球體粒子（SphereMesh），立體體積感，非 billboard 面片。
## 附 unshaded 材質讓 color_ramp 的顏色直接可見（火光/煙）。tint 固定粒子基色。
func _set_particle_mesh(particles: GPUParticles3D, tint: Color = Color.WHITE) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.albedo_color = tint
	sphere.material = mat
	particles.draw_pass_1 = sphere

## 原有橙色膨脹球（簡易衝擊波視覺）
func _spawn_expand_ball(scene: Node) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	scene.add_child(flash)
	flash.global_position = global_position
	var tw := flash.create_tween()
	tw.parallel().tween_property(flash, "scale", Vector3.ONE * (_radius * 2.0), 0.25)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(flash.queue_free)

func _make_curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	for i in points.size():
		c.add_point(Vector2(points[i].x, points[i].y))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct

func _make_gradient_tex(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var cols := PackedColorArray()
	for s in stops:
		cols.append(s)
	if cols.size() >= 3:
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	else:
		g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt
