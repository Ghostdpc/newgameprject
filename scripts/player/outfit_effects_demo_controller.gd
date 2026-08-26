## 职责：服装效果测试 Demo（双角色）
## P1（蓝）：WASD 移动，数字键效果：
##   1 头放大 / 2 身躯变宽 / 3 移速减 / 4 移速加 / 5 磕头软糯
## P2（橙）：方向键移动，F1-F5 同效果（避开 P2 数字键 1-4 跳/扑）：
##   F1 头放大 / F2 身躯变宽 / F3 移速减 / F4 移速加 / F5 磕头软糯
## R 重置 P1；F 切换 P1 布娃娃；0 重置 P2
class_name OutfitEffectsDemoController
extends Node3D

@onready var _player: PlayerController = $Player
@onready var _player2: PlayerController = $Player2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _toggle_head(_player, "P1")
			KEY_2: _toggle_width(_player, "P1")
			KEY_3: _toggle_speed(_player, "P1", 0.6)
			KEY_4: _toggle_speed(_player, "P1", 1.4)
			KEY_5: _toggle_kowtow(_player, "P1")
			KEY_R: _reset(_player, "P1")
			KEY_F:
				if _player.ragdoll_rig:
					_player.ragdoll_rig.set_ragdoll_enabled(not _player.ragdoll_rig.is_ragdoll_enabled())
				_hint("P1 切换布娃娃（对比用）")
			KEY_F1: _toggle_head(_player2, "P2")
			KEY_F2: _toggle_width(_player2, "P2")
			KEY_F3: _toggle_speed(_player2, "P2", 0.6)
			KEY_F4: _toggle_speed(_player2, "P2", 1.4)
			KEY_F5: _toggle_kowtow(_player2, "P2")
			KEY_0: _reset(_player2, "P2")

func _toggle_head(p: PlayerController, who: String) -> void:
	p.head_scale = 1.0 if p.head_scale != 1.0 else 1.8
	_hint("%s 头放大 x1.8" % who if p.head_scale != 1.0 else "%s 头还原" % who)

func _toggle_width(p: PlayerController, who: String) -> void:
	var on := p.body_width == 1.0
	p.body_width = 2.0 if on else 1.0
	p.body_scale = 1.3 if on else 1.0
	_hint("%s 身躯变宽 x2" % who if on else "%s 身躯还原" % who)

func _toggle_speed(p: PlayerController, who: String, val: float) -> void:
	p.speed_multiplier = 1.0 if p.speed_multiplier != 1.0 else val
	_hint("%s 移速 x%.1f" % [who, val] if p.speed_multiplier != 1.0 else "%s 移速还原" % who)

func _toggle_kowtow(p: PlayerController, who: String) -> void:
	if p.spring_rig:
		p.spring_rig.apply_preset("kowtow")
		p.spring_rig.set_active(true)
		_hint("%s 磕头软糯！" % who)
	else:
		_hint("%s 无 spring_rig" % who)

func _reset(p: PlayerController, who: String) -> void:
	p.head_scale = 1.0
	p.body_scale = 1.0
	p.body_width = 1.0
	p.speed_multiplier = 1.0
	if p.spring_rig:
		p.spring_rig.apply_preset("normal")
		p.spring_rig.set_active(true)
	_hint("%s 重置" % who)

func _hint(text: String) -> void:
	var l := get_node_or_null("UILayer/Feedback") as Label
	if l:
		l.text = text
