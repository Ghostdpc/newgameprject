@tool
extends Node3D

const TOON_SHADER: Shader = preload("res://resources/shaders/toon_room_material.gdshader")
const WOOD_FLOOR_MATERIAL: ShaderMaterial = preload("res://resources/materials/room_wood_floor.tres")

var _fill_light := 0.08
var _color_saturation := 0.9

@export_range(0.0, 0.35, 0.01) var fill_light: float:
    get:
        return _fill_light
    set(value):
        _fill_light = value
        _refresh_cartoon_materials()

@export_range(0.0, 1.5, 0.01) var color_saturation: float:
    get:
        return _color_saturation
    set(value):
        _color_saturation = value
        _refresh_cartoon_materials()

func _ready() -> void:
    call_deferred("_apply_cartoon_materials")
    if not Engine.is_editor_hint():
        var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
        RenderCompat.apply_environment(world_env)

func _refresh_cartoon_materials() -> void:
    if is_inside_tree():
        call_deferred("_apply_cartoon_materials")

func _apply_cartoon_materials() -> void:
    for mesh_instance in _find_mesh_instances(self):
        _apply_materials_to_mesh(mesh_instance)

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
    var mesh_instances: Array[MeshInstance3D] = []
    for child in node.get_children():
        if child is MeshInstance3D:
            mesh_instances.append(child)
        mesh_instances.append_array(_find_mesh_instances(child))
    return mesh_instances

func _apply_materials_to_mesh(mesh_instance: MeshInstance3D) -> void:
    if mesh_instance.mesh == null:
        return

    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    if mesh_instance.name.begins_with("SM_Fort_Floors_"):
        for surface_index in mesh_instance.mesh.get_surface_count():
            mesh_instance.set_surface_override_material(surface_index, WOOD_FLOOR_MATERIAL)
        return
    for surface_index in mesh_instance.mesh.get_surface_count():
        var material_override := mesh_instance.get_surface_override_material(surface_index)
        if material_override is ShaderMaterial and material_override.shader == TOON_SHADER:
            _update_cartoon_parameters(material_override)
            continue

        var source_material: Material = material_override
        if source_material == null:
            source_material = mesh_instance.mesh.surface_get_material(surface_index)

        var albedo_texture: Texture2D
        var albedo_tint := Color.WHITE
        if source_material is BaseMaterial3D:
            albedo_texture = source_material.albedo_texture
            albedo_tint = source_material.albedo_color

        var toon_material := ShaderMaterial.new()
        toon_material.shader = TOON_SHADER
        toon_material.set_shader_parameter(&"albedo_texture", albedo_texture)
        toon_material.set_shader_parameter(&"albedo_tint", albedo_tint)
        _update_cartoon_parameters(toon_material)
        mesh_instance.set_surface_override_material(surface_index, toon_material)

func _update_cartoon_parameters(toon_material: ShaderMaterial) -> void:
    toon_material.set_shader_parameter(&"fill_light", _fill_light)
    toon_material.set_shader_parameter(&"color_saturation", _color_saturation)
