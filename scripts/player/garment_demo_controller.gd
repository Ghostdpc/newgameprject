## 職責：服裝系統測試場景控制
## - 開場延遲觸發 battle_started，讓 GarmentSpawner 自動刷新全部服裝（從天而降）
## - P1 WASD 移動 + 長按 F（0.8s）拾取服裝；同槽替換；Esc 觸發 battle_ended 清場
## - 熒幕即時顯示已裝備件數與各效果開關

extends Node3D

@onready var _hint: Label = $UILayer/Hint
@onready var _feedback: Label = $UILayer/Feedback

var _battle_active: bool = false
var _spring_on: bool = true

func _ready() -> void:
	# 等一幀讓 GarmentSpawner ready 完成連線，再觸發混戰開始刷服裝
	await get_tree().process_frame
	EventBus.battle_started.emit()
	_battle_active = true
	_feedback.text = "混戰開始：服裝已從天而降！長按 E 拾取"
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
		# 調參：用 [ ] / I J K L 微調當前裝備的帽子大小與位置（避免與 p2 方向鍵衝突）
		KEY_BRACKETRIGHT: _tune_scale(0.05)
		KEY_BRACKETLEFT: _tune_scale(-0.05)
		KEY_I: _tune_pos(Vector3(0, 0.05, 0))
		KEY_K: _tune_pos(Vector3(0, -0.05, 0))
		KEY_J: _tune_pos(Vector3(0, 0, -0.05))
		KEY_L: _tune_pos(Vector3(0, 0, 0.05))
		# T：暫停/恢復彈簧軟糯（調參時停晃方便看）
		KEY_T: _toggle_spring()

## 微調：改當前帽子 item 的整體縮放（[ 增 / ] 減）→ 設 user_hat_scale_mult（受 head 補償相乘）
func _tune_scale(delta: float) -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return
	p1.user_hat_scale_mult = maxf(0.1, p1.user_hat_scale_mult + delta)
	_feedback.text = "帽子 scaleMult=" + str(p1.user_hat_scale_mult)
	_refresh_hint()

## 微調：改當前帽子 item 的掛點位置（方向鍵）
func _tune_pos(delta: Vector3) -> void:
	var item := _current_hat_item()
	if item == null:
		_feedback.text = "無帽子可調（先穿一件）"
		return
	item.position += delta
	_feedback.text = "帽子 pos=" + str(item.position)
	_refresh_hint()

func _current_hat_item() -> Node3D:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null or p1.outfit_manager == null:
		return null
	return p1.outfit_manager.get_item("hat_slot")

## T：暫停/恢復彈簧骨骼軟糯（調參/看位置時停晃）
func _toggle_spring() -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null or p1.spring_rig == null:
		return
	_spring_on = not _spring_on
	p1.spring_rig.set_active(_spring_on)
	_feedback.text = "彈簧軟糯 " + ("開" if _spring_on else "關（已暫停，調參方便）")
	_refresh_hint()

## 打印當前微調值供寫回 garments.json
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
	# 重新触发混戰刷新服装
	call_deferred("_restart_battle")
	_feedback.text = "已重置：服装清空、重新刷新、玩家回出生点"
	_refresh_hint()

func _restart_battle() -> void:
	if _battle_active:
		return
	EventBus.battle_started.emit()
	_battle_active = true

## 玩家長按拾取服裝後即時反饋（每幀偵測）
func _process(_delta: float) -> void:
	if not _battle_active:
		return
	_refresh_hint()

## 結束混戰：清場所有服裝效果（測試 revert）
func _end_battle() -> void:
	if not _battle_active:
		return
	_battle_active = false
	EventBus.battle_ended.emit()
	_feedback.text = "混戰結束：所有服裝效果已還原（Esc 可切換）"

func _refresh_hint() -> void:
	var p1 := get_node_or_null("Player") as PlayerController
	if p1 == null:
		return
	# 讀取已裝備槽位
	var eq: Dictionary = p1.equipped_garments
	var score := 0.0
	if _battle_active:
		score = GarmentSystem.get_equipped_score(p1)
	var hat: String = str(eq.get("hat_slot", ""))
	var shirt: String = str(eq.get("shirt_slot", ""))
	var acc: String = str(eq.get("accessory_slot", ""))
	_hint.text = (
		"[P1] WASD移動 + E長按(0.8s)拾取    Esc=結束混戰清場\n"
		+ "穿戴: [1]蘑菇 [2]光環 [3]閃電T [4]蝸牛 [5]氣球 [6]吉他  [0]清空  [R]重置\n"
		+ "微調帽子: [ ]大小  I↑ K↓ J← L→  [T]停晃\n"
		+ "已裝備  頭:%s  上衣:%s  配飾:%s\n"
		+ "outfit分: %.2f"
	) % [hat if not hat.is_empty() else "無", shirt if not shirt.is_empty() else "無", acc if not acc.is_empty() else "無", score]
