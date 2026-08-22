## 職責：服裝效果測試 Demo（双角色）
## P1（蓝）：WASD 移動，數字鍵效果：
##   1 頭放大 / 2 身軀變寬 / 3 移速減 / 4 移速加 / 5 磕頭軟糯
## P2（橙）：方向鍵移動，F1-F5 同效果（避開 P2 數字鍵 1-4 跳/撲）：
##   F1 頭放大 / F2 身軀變寬 / F3 移速減 / F4 移速加 / F5 磕頭軟糯
## R 重置 P1；F 切換 P1 布娃娃；0 重置 P2
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
				_hint("P1 切換布娃娃（對比用）")
			KEY_F1: _toggle_head(_player2, "P2")
			KEY_F2: _toggle_width(_player2, "P2")
			KEY_F3: _toggle_speed(_player2, "P2", 0.6)
			KEY_F4: _toggle_speed(_player2, "P2", 1.4)
			KEY_F5: _toggle_kowtow(_player2, "P2")
			KEY_0: _reset(_player2, "P2")

func _toggle_head(p: PlayerController, who: String) -> void:
	p.head_scale = 1.0 if p.head_scale != 1.0 else 1.8
	_hint("%s 頭放大 x1.8" % who if p.head_scale != 1.0 else "%s 頭還原" % who)

func _toggle_width(p: PlayerController, who: String) -> void:
	var on := p.body_width == 1.0
	p.body_width = 2.0 if on else 1.0
	p.body_scale = 1.3 if on else 1.0
	_hint("%s 身軀變寬 x2" % who if on else "%s 身軀還原" % who)

func _toggle_speed(p: PlayerController, who: String, val: float) -> void:
	p.speed_multiplier = 1.0 if p.speed_multiplier != 1.0 else val
	_hint("%s 移速 x%.1f" % [who, val] if p.speed_multiplier != 1.0 else "%s 移速還原" % who)

func _toggle_kowtow(p: PlayerController, who: String) -> void:
	if p.spring_rig:
		p.spring_rig.apply_preset("kowtow")
		p.spring_rig.set_active(true)
		_hint("%s 磕頭軟糯！" % who)
	else:
		_hint("%s 無 spring_rig" % who)

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
