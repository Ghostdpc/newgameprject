## 职责：死亡阶段（出界初死）——清道具、隐藏模型、停物理
## 立即过渡到 RespawnWaiting 读秒

class_name DeathState
extends BaseState

func enter() -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	controller.clear_item()
	controller.set_ragdoll(false)
	controller.velocity = Vector3.ZERO
	controller.visible = false

func physics_update(_delta: float) -> void:
	var controller := _player as PlayerController
	if not controller:
		return
	controller.state_machine.transition_to("RespawnWaiting")
