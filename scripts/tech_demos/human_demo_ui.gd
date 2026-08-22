## 職責：Human 測試場景 UI 驅動 —— 提供換裝/表情/布娃娃/離地測試快捷鍵
## 掛在 HumanDemo 根。操作 $Player（player.tscn 的 PlayerController 實例）。

extends Node

@onready var _hint: Label = $UILayer/Hint

const HAT_SCENE := preload("res://scenes/tech_demos/outfit_items/hat.tscn")
const SHIRT_SCENE := preload("res://scenes/tech_demos/outfit_items/shirt.tscn")
const BACKPACK_SCENE := preload("res://scenes/tech_demos/outfit_items/backpack.tscn")

var _spring_kowtow_on: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	var player := get_node_or_null("Player")
	match k:
		# 換裝
		KEY_1: _equip(player, "hat_slot", HAT_SCENE)
		KEY_2: _unequip(player, "hat_slot")
		KEY_3: _equip(player, "shirt_slot", SHIRT_SCENE)
		KEY_4: _unequip(player, "shirt_slot")
		KEY_5: _equip(player, "accessory_slot", BACKPACK_SCENE)
		KEY_6: _unequip(player, "accessory_slot")
		# 表情
		KEY_Q: _face(player, 1)
		KEY_E: _face(player, -1)
		KEY_R: _face(player, -1, true)
		# 布娃娃
		KEY_B: _ragdoll(player)
		# 磕頭：N = 彈簧軟糯磕頭(preset)  M = ragdoll頭骨衝量磕頭
		KEY_N: _spring_kowtow(player)
		KEY_M: _ragdoll_kowtow(player)

func _spring_kowtow(player: Node) -> void:
	if not player:
		return
	var spring = player.get("spring_rig")
	if spring:
		_spring_kowtow_on = not _spring_kowtow_on
		spring.call("apply_preset", "kowtow" if _spring_kowtow_on else "normal")
		_hint_append(" 彈簧磕頭 %s" % ("開(kowtow)" if _spring_kowtow_on else "關(normal)"))
	else:
		_hint_append(" 無 spring_rig")

func _ragdoll_kowtow(player: Node) -> void:
	if not player:
		return
	if player.has_method("play_kowtow_ragdoll"):
		player.call("play_kowtow_ragdoll", 6.0, 1.2)
		_hint_append(" ragdoll磕頭")
	else:
		_hint_append(" 無 play_kowtow_ragdoll")

func _equip(player: Node, slot: String, scene: PackedScene) -> void:
	if not player:
		return
	var om = player.get("outfit_manager")
	if om:
		om.equip(slot, scene)
		_hint_append(" 已穿戴: " + slot)

func _unequip(player: Node, slot: String) -> void:
	if not player:
		return
	var om = player.get("outfit_manager")
	if om:
		om.unequip(slot)
		_hint_append(" 已卸下: " + slot)

## 表情切換。dir>0 下一個，<0 上一個；clear=true 清除
func _face(player: Node, dir: int, clear: bool = false) -> void:
	if not player:
		return
	var fc = player.get("face")
	if not fc:
		return
	if clear:
		fc.call("clear")
		_hint_append(" 表情清除")
		return
	var total: int = fc.call("count")
	var cur: int = fc.get("_current_index")
	var nxt: int
	if total <= 0:
		return
	if cur < 0:
		nxt = 0
	elif dir > 0:
		nxt = cur + 1 if cur < total - 1 else -1
	else:
		nxt = cur - 1 if cur > 0 else -1
	fc.call("show_expression", nxt)
	_hint_append(" 表情 #%d" % (nxt + 1))

func _ragdoll(player: Node) -> void:
	if not player:
		return
	var rr = player.get("ragdoll_rig")
	if rr:
		if rr.is_ragdoll_enabled():
			# 先同步 body 再關閉（避免起身瞬移）
			if player.has_method("set_ragdoll"):
				player.call("set_ragdoll", false)
			else:
				rr.reset()
			_hint_append(" 布娃娃關")
		else:
			if player.has_method("set_ragdoll"):
				player.call("set_ragdoll", true)
			else:
				rr.set_ragdoll_enabled(true)
			_hint_append(" 布娃娃開")

func _hint_append(t: String) -> void:
	if _hint:
		_hint.text = "Human (WASD移動/空格跳/F飛撲 E拾取)  [1帽3衣5背包]  [Q/E表情 R清除]  [B布娃娃]  [N彈簧磕頭 M磕頭]\n> " + t
	else:
		_hint = $UILayer/Hint
		if _hint:
			_hint_append(t)
