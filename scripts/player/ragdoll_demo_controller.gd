## 職責：布娃娃技術驗證 Demo，測試模型骨架物理 / 動畫↔物理切換

class_name RagdollDemoController
extends Node3D

const IMPULSE_FORCE: float = 6.0

@onready var _rig: RagdollRig = $RagdollRig
@onready var _hint: Label = $UILayer/Hint
@onready var _model: Node3D = $RigModel

func _ready() -> void:
	var skeleton := _find_skeleton(_model)
	var anim := _find_animation_player(_model)
	if not skeleton or not anim:
		push_error("RagdollDemo: 模型缺少 Skeleton3D 或 AnimationPlayer")
		return
	_rig.setup(skeleton, anim)
	anim.play("Walking_A")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_toggle_ragdoll()
			KEY_R:
				_rig.reset()
				var anim := _find_animation_player(_model)
				if anim:
					anim.play("Walking_A")
				_update_hint("重置！")
			KEY_F:
				_shoot()

func _toggle_ragdoll() -> void:
	var enabled := not _rig._ragdoll_enabled
	_rig.set_ragdoll_enabled(enabled)
	if not enabled:
		var anim := _find_animation_player(_model)
		if anim:
			anim.play("Walking_A")
	_update_hint("Ragdoll: %s" % ("ON" if enabled else "OFF"))

func _shoot() -> void:
	_rig.set_ragdoll_enabled(true)
	_rig.apply_impulse(Vector3(0.0, IMPULSE_FORCE, -1.0))
	_update_hint("衝擊施加！")

func _update_hint(text: String) -> void:
	if _hint:
		_hint.text = text

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null
