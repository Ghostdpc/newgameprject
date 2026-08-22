extends Node3D

@export var output_path := "res://.godot/room_preview.png"

func _ready() -> void:
    _hide_preview_roof(get_node("RoomTest"))
    _frame_camera_on_room()
    call_deferred("_capture_preview")

func _frame_camera_on_room() -> void:
    var bounds := _get_room_bounds(get_node("RoomTest"))
    if bounds.size == Vector3.ZERO:
        return

    var center := bounds.get_center()
    var size := bounds.size
    print("ROOM_PREVIEW_BOUNDS=%s" % bounds)
    print("ROOM_PREVIEW_CENTER=%s" % center)
    var camera := Camera3D.new()
    add_child(camera)
    camera.fov = 48.0
    camera.near = 0.01
    camera.far = 1000.0
    camera.global_position = center + Vector3(size.x * 0.10, -size.y * 0.15, size.z * 0.25)
    camera.look_at(center + Vector3(0.0, -size.y * 0.35, 0.0), Vector3.UP)
    camera.current = true

func _get_room_bounds(room: Node) -> AABB:
    var has_bounds := false
    var result := AABB()
    var mesh_instances: Array[MeshInstance3D] = []
    _find_mesh_instances(room, mesh_instances)
    for mesh_instance in mesh_instances:
        if mesh_instance.mesh == null:
            continue
        var mesh_aabb := mesh_instance.get_aabb()
        for x in [mesh_aabb.position.x, mesh_aabb.end.x]:
            for y in [mesh_aabb.position.y, mesh_aabb.end.y]:
                for z in [mesh_aabb.position.z, mesh_aabb.end.z]:
                    var point := mesh_instance.global_transform * Vector3(x, y, z)
                    if has_bounds:
                        result = result.expand(point)
                    else:
                        result = AABB(point, Vector3.ZERO)
                        has_bounds = true
    return result

func _find_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
    for child in node.get_children():
        if child is MeshInstance3D:
            result.append(child)
        _find_mesh_instances(child, result)

func _capture_preview() -> void:
    await get_tree().process_frame
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    var result := image.save_png(output_path)
    print("ROOM_PREVIEW_PATH=%s" % ProjectSettings.globalize_path(output_path))
    print("ROOM_PREVIEW_SAVE_RESULT=%d" % result)
    get_tree().quit()

func _hide_preview_roof(node: Node) -> void:
    for child in node.get_children():
        if child is VisualInstance3D and ("SkyLight" in child.name or "Top_B" in child.name):
            child.visible = false
        _hide_preview_roof(child)
