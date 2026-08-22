## 职责：全屏边缘 UIMask 特效。
## 使用 SVG 边框蒙版 + CanvasItem Shader + Tween 动画；不使用满屏粒子或屏幕扭曲。

class_name FullscreenItemPost
extends CanvasLayer

const EDGE_MASK_SCRIPT := preload("res://scripts/vfx/screen_edge_mask.gd")
const EDGE_PARTICLE_STREAM_SCRIPT := preload("res://scripts/vfx/edge_particle_stream.gd")
const TIME_DIRECTION_BADGE_SCRIPT := preload("res://scripts/vfx/time_direction_badge.gd")

const COLORS := {
	"fast": Color(1.0, 0.50, 0.08, 1.0),
	"slow": Color(0.14, 0.66, 1.0, 1.0),
	"add": Color(0.20, 1.0, 0.38, 1.0),
	"sub": Color(1.0, 0.06, 0.04, 1.0),
	"camera": Color(1.0, 0.76, 0.16, 1.0),
}

var _mask_root: Control
var _edge_mask: Control
var _pulse_layer: ColorRect
var _shader_material: ShaderMaterial
var _particle_stream: Control
var _time_badge: Control
var _mode := ""
var _started_at := 0
var _expires_at := 0
var _entry_tween: Tween

func _ready() -> void:
	layer = 50
	_mask_root = Control.new()
	_mask_root.name = "UIMask"
	_mask_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mask_root)

	_pulse_layer = ColorRect.new()
	_pulse_layer.name = "AnimatedEdgeGlow"
	_pulse_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pulse_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _shader_code()
	_shader_material.shader = shader
	_pulse_layer.material = _shader_material
	_mask_root.add_child(_pulse_layer)

	_edge_mask = EDGE_MASK_SCRIPT.new() as Control
	_edge_mask.name = "EdgeMask"
	_mask_root.add_child(_edge_mask)
	_particle_stream = EDGE_PARTICLE_STREAM_SCRIPT.new() as Control
	_particle_stream.name = "EdgeParticleStream"
	_mask_root.add_child(_particle_stream)
	_time_badge = TIME_DIRECTION_BADGE_SCRIPT.new() as Control
	_time_badge.name = "TimeDirectionBadge"
	_time_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_badge.position = Vector2(-115.0, 34.0)
	_mask_root.add_child(_time_badge)
	_time_badge.hide()
	await get_tree().process_frame
	_edge_mask.pivot_offset = _edge_mask.size * 0.5
	hide()

func play(mode: String, duration: float) -> void:
	_mode = mode
	_started_at = Time.get_ticks_msec()
	_expires_at = _started_at + int(duration * 1000.0)
	var color: Color = COLORS.get(mode, Color.WHITE)
	_edge_mask.modulate = Color(color.r, color.g, color.b, 0.0)
	_edge_mask.scale = Vector2(0.91, 0.91)
	_mask_root.position = Vector2.ZERO
	_shader_material.set_shader_parameter("fx_color", color)
	_shader_material.set_shader_parameter("fx_mode", _mode_id(mode))
	_configure_time_direction(mode, color)
	show()
	_play_entry_animation(mode)

func clear_mode(mode: String) -> void:
	if _mode == mode:
		_finish()

func _process(_delta: float) -> void:
	if _mode.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now >= _expires_at:
		_finish()
		return
	var elapsed := float(now - _started_at) / 1000.0
	var remaining := float(_expires_at - now) / 1000.0
	var strength := minf(minf(elapsed / 0.14, remaining / 0.20), 1.0)
	_shader_material.set_shader_parameter("fx_time", elapsed)
	_shader_material.set_shader_parameter("fx_strength", clampf(strength, 0.0, 1.0))
	if _time_badge.visible:
		_time_badge.call("set_pulse", sin(elapsed * 10.0) * 0.5 + 0.5)
	if _mode == "sub":
		var shake := sin(elapsed * 46.0) * 8.0 * strength
		_mask_root.position = Vector2(shake, -shake * 0.35)

func _configure_time_direction(mode: String, color: Color) -> void:
	if mode == "fast":
		_time_badge.call("configure", 1, "2.0x", color)
		_time_badge.show()
		_particle_stream.call("configure", color, 1.32)
	elif mode == "slow":
		_time_badge.call("configure", -1, "0.5x", color)
		_time_badge.show()
		_particle_stream.call("configure", color, 0.58)
	else:
		_time_badge.hide()
		_particle_stream.call("stop")

func _play_entry_animation(mode: String) -> void:
	if _entry_tween:
		_entry_tween.kill()
	_entry_tween = create_tween().set_parallel(true)
	_entry_tween.tween_property(_edge_mask, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_edge_mask, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if mode == "fast":
		_entry_tween.tween_property(_edge_mask, "rotation", 0.025, 0.10)
		_entry_tween.chain().tween_property(_edge_mask, "rotation", 0.0, 0.12)
	elif mode == "slow":
		_entry_tween.tween_property(_edge_mask, "scale", Vector2(1.035, 1.035), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif mode == "add":
		_entry_tween.tween_property(_edge_mask, "scale", Vector2(1.08, 1.08), 0.20).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	elif mode == "camera":
		_entry_tween.tween_property(_edge_mask, "modulate:a", 0.82, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _finish() -> void:
	if _mode.is_empty():
		return
	_mode = ""
	_mask_root.position = Vector2.ZERO
	_particle_stream.call("stop")
	_time_badge.hide()
	if _entry_tween:
		_entry_tween.kill()
	_entry_tween = create_tween()
	_entry_tween.tween_property(_edge_mask, "modulate:a", 0.0, 0.16)
	_entry_tween.tween_callback(hide)

func _mode_id(mode: String) -> int:
	match mode:
		"fast": return 1
		"slow": return 2
		"add": return 3
		"sub": return 4
		"camera": return 5
	return 0

func _shader_code() -> String:
	return """
shader_type canvas_item;

uniform vec4 fx_color : source_color = vec4(1.0);
uniform float fx_time = 0.0;
uniform float fx_strength = 0.0;
uniform int fx_mode = 0;

float edge_band(vec2 uv, float thickness) {
    vec2 from_center = abs(uv - vec2(0.5)) * 2.0;
    float edge = max(from_center.x, from_center.y);
    return smoothstep(1.0 - thickness, 1.0, edge);
}

void fragment() {
    vec2 uv = UV;
    float edge = edge_band(uv, 0.105);
    float outer = edge_band(uv, 0.035);
    float pulse = 0.55 + 0.45 * sin(fx_time * (fx_mode == 1 ? 18.0 : 7.0));
    float stripe = 0.0;
    if (fx_mode == 1) {
        stripe = smoothstep(0.76, 0.98, sin((uv.x - uv.y) * 56.0 - fx_time * 22.0));
    } else if (fx_mode == 2) {
        stripe = smoothstep(0.78, 0.98, sin((uv.x + uv.y) * 38.0 + fx_time * 2.0));
    } else if (fx_mode == 4) {
        stripe = smoothstep(0.66, 0.98, sin((uv.x * 48.0) + fx_time * 16.0));
    }
    float alpha = edge * (0.14 + pulse * 0.12) + outer * 0.44;
    alpha += stripe * edge * 0.32;
    if (fx_mode == 3) {
        alpha += edge * (0.16 + sin(fx_time * 15.0) * 0.10);
    } else if (fx_mode == 5) {
        vec2 from_center = abs(uv - vec2(0.5)) * 2.0;
        float corner = smoothstep(0.58, 0.92, max(from_center.x, from_center.y));
        alpha += corner * 0.18;
    }
    COLOR = vec4(fx_color.rgb * (0.74 + pulse * 0.42), clamp(alpha * fx_strength, 0.0, 0.88));
}
"""
