## 職責：banana_slide 效果 —— 踩到香蕉皮時沿行進方向給一個滑行衝量並躺下
## params.speed: float  滑行速度（默認 8.0）

class_name BananaSlideEffect
extends ItemEffect

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	var player := ctx.source_player as PlayerController

	var speed: float = float(params.get("speed", 8.0))

	# 取水平速度方向；若靜止則用角色朝向（模型正面為 -Z）
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if horizontal.length_squared() < 0.01:
		horizontal = -player.global_basis.z

	var slide_dir := horizontal.normalized()
	player.velocity = Vector3(slide_dir.x * speed, player.velocity.y, slide_dir.z * speed)

	# 激活布娃娃並進入 Stunned（Stunned 計時結束後自動站起）
	player.set_ragdoll(true)
	player.state_machine.transition_to("Stunned")

func revert(_ctx: ItemContext) -> void:
	pass
