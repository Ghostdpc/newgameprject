## 職責：服裝系統測試場景控制
## - 開場延遲觸發 battle_started，讓 GarmentSpawner 自動刷新全部服裝（從天而降）
## - P1 WASD 移動 + 長按 F（0.8s）拾取服裝；同槽替換；Esc 觸發 battle_ended 清場
## - 熒幕即時顯示已裝備件數與各效果開關

extends Node3D

@onready var _hint: Label = $UILayer/Hint
@onready var _feedback: Label = $UILayer/Feedback

var _battle_active: bool = false

func _ready() -> void:
	# 等一幀讓 GarmentSpawner ready 完成連線，再觸發混戰開始刷服裝
	await get_tree().process_frame
	EventBus.battle_started.emit()
	_battle_active = true
	_feedback.text = "混戰開始：服裝已從天而降！長按 F 拾取"
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
		"[P1] WASD移動 + F長按(0.8s)拾取    Esc=結束混戰清場\n"
		+ "已裝備  頭:%s  上衣:%s  配飾:%s\n"
		+ "outfit分: %.2f"
	) % [hat if not hat.is_empty() else "無", shirt if not shirt.is_empty() else "無", acc if not acc.is_empty() else "無", score]
