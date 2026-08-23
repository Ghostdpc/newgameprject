## 職責：throw_bomb 效果 —— 從使用者手前拋出 BombInstance（拋物線），交由炸彈自身引爆。
## params: throw_speed / fuse / radius / gray_duration / score_penalty
## 炸彈模型複用道具 def 的 model/texture（占位球體回退見 BombInstance）

class_name ThrowBombEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	# WORLD target 時 source_player 為 null，從 extra["invoker"] 取原始使用者
	var thrower: PlayerController = ctx.source_player
	if thrower == null:
		thrower = ctx.extra.get("invoker") as PlayerController
	if thrower == null:
		push_warning("ThrowBombEffect: no valid thrower found")
		return

	var bomb := BombInstance.new()
	bomb.setup_bomb(params, thrower)

	# 複用道具定義的模型作為炸彈外觀
	var def := ItemSystem._item_config.get_item(ctx.item_id)
	var visual: Node3D = null
	if def and not def.model.is_empty():
		visual = PropModelBuilder.build(def.model, def.texture, 0.5, def.model_scale)
	if visual == null:
		visual = _placeholder_visual()
	bomb.add_child(visual)

	thrower.get_tree().current_scene.add_child(bomb)
	var forward := thrower.global_basis.z
	bomb.global_position = thrower.global_position + forward * 0.8 + Vector3.UP * 1.2
	var throw_speed: float = float(params.get("throw_speed", 4.0))
	bomb.release(forward * throw_speed + Vector3.UP * 1.5)

func _placeholder_visual() -> Node3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.15)
	mi.material_override = mat
	return mi
