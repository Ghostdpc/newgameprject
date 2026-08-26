## 职责：服装系统测试场景控制
## - 开场延迟触发 battle_started，让 GarmentSpawner 自动刷新全部服装（从天而降）
## - P1 WASD 移动 + 长按 F（0.8s）拾取服装；同槽替换；Esc 触发 battle_ended 清场
## - 荧幕即时显示已装备件数与各效果开关

extends Node3D

@onready var _hint: Label = $UILayer/Hint
@onready var _feedback: Label = $UILayer/Feedback

var _battle_active: bool = false
var _spring_on: bool = true

func _ready() -> void:
	# 等一帧让 GarmentSpawner ready 完成连线，再触发混战开始刷服装
	await get_tree().process_frame
	EventBus.battle_started.emit()
	_battle_active = true
	_feedback.text = "混战开始：服装已从天而降！长按 E 拾取"
	_refresh_hint()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	if k == 0:
		k = (event as InputEventKey).physical_keycode
	match k:
		KEY_ESCAPE:
			_end_battle()
		# 直接装备/卸下各类服装（快速看效果，slot 冲突自动同槽替换）
		KEY_1: _wear("mushroom_hat")
		KEY_2: _wear("halo")
		KEY_3: _wear("lightning_shirt")
		KEY_4: _wear("snail_hoodie")
		KEY_5: _wear("inflate_shirt")
		KEY_6: _wear("guitar")
		KEY_0: _clear_p1()
		KEY_R: _reset_demo()
		# 调参：用 [ ] / I J K L 微调当前装备的帽子大小与位置（避免与 p2 方向键冲突）
		KEY_BRACKETRIGHT: _tune_scale(0.05)
		KEY_BRACKETLEFT: _tune_scale(-0.05)
		KEY_I: _tune_pos(Vector3(0, 0.05, 0))
		KEY_K: _tune_pos(Vector3(0, -0.05, 0))
		KEY_J: _tune_pos(Vector3(0, 0, -0.05))
		KEY_L: _tune_pos(Vector3(0, 0, 0.05))
		# T：暂停/恢复弹簧软糯（调参时停晃方便看）
		KEY_T: _toggle_spring()

## 微调：改当前帽子 item 的整体缩放（[ 增 / ] 减）→ 设 user_hat_scale_mult（受 head 补偿相乘）
func _tune_scale(delta: float) -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return
	p1.user_hat_scale_mult = maxf(0.1, p1.user_hat_scale_mult + delta)
	_feedback.text = "帽子 scaleMult=" + str(p1.user_hat_scale_mult)
	_refresh_hint()

## 微调：改当前帽子 item 的挂点位置（方向键）
func _tune_pos(delta: Vector3) -> void:
	var item := _current_hat_item()
	if item == null:
		_feedback.text = "无帽子可调（先穿一件）"
		return
	item.position += delta
	_feedback.text = "帽子 pos=" + str(item.position)
	_refresh_hint()

func _current_hat_item() -> Node3D:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null or p1.outfit_manager == null:
		return null
	return p1.outfit_manager.get_item("hat_slot")

## T：暂停/恢复弹簧骨骼软糯（调参/看位置时停晃）
func _toggle_spring() -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null or p1.spring_rig == null:
		return
	_spring_on = not _spring_on
	p1.spring_rig.set_active(_spring_on)
	_feedback.text = "弹簧软糯 " + ("开" if _spring_on else "关（已暂停，调参方便）")
	_refresh_hint()

## 打印当前微调值供写回 garments.json
func _hint_tune_values() -> String:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return ""
	return "scaleMult=%.2f" % p1.user_hat_scale_mult

func _wear(garment_id: String) -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return
	# 已在穿则卸下，否则穿上（快速对比）
	var already: bool = false
	for slot in p1.equipped_garments.values():
		if slot == garment_id:
			already = true
			break
	if already:
		GarmentSystem._unequip_slot(p1, _slot_of(garment_id))
		_feedback.text = "卸下 " + garment_id
	else:
		GarmentSystem.equip_garment(p1, garment_id)
		_feedback.text = "穿上 " + garment_id + "（score " + str(GarmentSystem.get_equipped_score(p1)) + "）"
	_refresh_hint()

func _slot_of(garment_id: String) -> String:
	var def := GarmentSystem._garment_config.get_garment(garment_id)
	return def.slot if def else ""

func _clear_p1() -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return
	for slot in p1.equipped_garments.keys():
		GarmentSystem._unequip_slot(p1, slot)
	_feedback.text = "清空 P1 服装"
	_refresh_hint()

## R：重置测试（清空服装效果 + 重生掉落 + 玩家回出生点）
func _reset_demo() -> void:
	_end_battle()
	var p1 := get_node_or_null("Player") as PlayerController
	if p1:
		p1.global_position = Vector3(-4, 1, 0)
		p1.velocity = Vector3.ZERO
	# 重新触发混战刷新服装
	call_deferred("_restart_battle")
	_feedback.text = "已重置：服装清空、重新刷新、玩家回出生点"
	_refresh_hint()

func _restart_battle() -> void:
	if _battle_active:
		return
	EventBus.battle_started.emit()
	_battle_active = true

## 玩家长按拾取服装后即时反馈（每帧侦测）
func _process(_delta: float) -> void:
	if not _battle_active:
		return
	_refresh_hint()

## 结束混战：清场所有服装效果（测试 revert）
func _end_battle() -> void:
	if not _battle_active:
		return
	_battle_active = false
	EventBus.battle_ended.emit()
	_feedback.text = "混战结束：所有服装效果已还原（Esc 可切换）"

func _refresh_hint() -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return
	# 读取已装备槽位
	var eq: Dictionary = p1.equipped_garments
	var score := 0.0
	if _battle_active:
		score = GarmentSystem.get_equipped_score(p1)
	var hat: String = str(eq.get("hat_slot", ""))
	var shirt: String = str(eq.get("shirt_slot", ""))
	var acc: String = str(eq.get("accessory_slot", ""))
	_hint.text = (
		"[P1] WASD移动 + E长按(0.8s)拾取    Esc=结束混战清场\n"
		+ "穿戴: [1]蘑菇 [2]光环 [3]闪电T [4]蜗牛 [5]气球 [6]吉他  [0]清空  [R]重置\n"
		+ "微调帽子: [ ]大小  I↑ K↓ J← L→  [T]停晃\n"
		+ "已装备  头:%s  上衣:%s  配饰:%s\n"
		+ "outfit分: %.2f"
	) % [hat if not hat.is_empty() else "无", shirt if not shirt.is_empty() else "无", acc if not acc.is_empty() else "无", score]
