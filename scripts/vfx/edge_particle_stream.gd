## 职责：由左右屏幕边缘向中心喷洒的轻量 UI 粒子流。
## 只用于快进/慢放时间效果，避免覆盖中间角色与 HUD。

class_name EdgeParticleStream
extends Control

var color := Color(1.0, 0.50, 0.08, 1.0)
var active := false
var speed := 1.0
var _elapsed := 0.0
var _particles: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seed_particles()

func configure(next_color: Color, next_speed: float) -> void:
	color = next_color
	speed = next_speed
	active = true
	_elapsed = 0.0
	_seed_particles()
	show()

func stop() -> void:
	active = false
	hide()

func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	for particle in _particles:
		particle["x"] += particle["velocity"] * delta * speed
		particle["wave"] += delta * particle["frequency"]
		if (particle["side"] < 0 and particle["x"] > size.x * 0.46) or (particle["side"] > 0 and particle["x"] < size.x * 0.54):
			_reset_particle(particle)
	queue_redraw()

func _draw() -> void:
	for particle in _particles:
		var y: float = float(particle["y"]) + sin(float(particle["wave"])) * float(particle["amplitude"])
		var position := Vector2(particle["x"], y)
		var direction := Vector2(float(particle["side"]), 0.0)
		var length: float = float(particle["length"])
		var alpha: float = float(particle["alpha"]) * (0.58 + sin(_elapsed * 12.0 + float(particle["wave"])) * 0.24)
		draw_line(position - direction * length, position, Color(color.r, color.g, color.b, alpha), float(particle["width"]))
		draw_circle(position, float(particle["width"]) * 0.88, Color(1.0, 0.96, 0.82, alpha))

func _seed_particles() -> void:
	_particles.clear()
	for index in 52:
		var particle := {}
		particle["side"] = -1 if index % 2 == 0 else 1
		_particles.append(particle)
		_reset_particle(particle, index)

func _reset_particle(particle: Dictionary, seed := -1) -> void:
	var value := float(seed if seed >= 0 else randi_range(0, 1000))
	var side := int(particle.get("side", -1))
	particle["side"] = side
	particle["x"] = -30.0 - fposmod(value * 37.0, size.x * 0.15 + 160.0) if side < 0 else size.x + 30.0 + fposmod(value * 29.0, size.x * 0.15 + 160.0)
	particle["y"] = fposmod(value * 71.0, maxf(size.y, 1.0))
	particle["velocity"] = (260.0 + fposmod(value * 19.0, 370.0)) * -side
	particle["length"] = 20.0 + fposmod(value * 7.0, 82.0)
	particle["width"] = 1.3 + fposmod(value * 0.17, 2.8)
	particle["alpha"] = 0.24 + fposmod(value * 0.013, 0.46)
	particle["wave"] = value * 0.09
	particle["frequency"] = 1.8 + fposmod(value * 0.07, 3.4)
	particle["amplitude"] = 4.0 + fposmod(value * 0.11, 18.0)
