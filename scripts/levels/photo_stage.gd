## 职责：拍照抢镜头关卡（PhotoStage）—— 第一个正式关卡
## 差异点：舞台布置、出生点、相机参数、特殊玩法
## 舞台布置由策划在 photo_stage.tscn 中手动摆放（不写代码）

class_name PhotoStage
extends LevelBase

## 真人数量（2-4，可由场景档 @export 或流程配置覆写）
@export var human_player_count: int = 4

## 决胜时刻倒计时变红（HUD 标签）
@onready var _timer_label: Label = get_node_or_null("HUD/CameraViewfinder/TimerLabel") as Label

func get_player_count() -> int:
	return clampi(human_player_count, 2, 4)

## 出生点：优先读 SpawnPoints 节点，否则用默认四角
func get_spawn_points() -> Array[Vector3]:
	if not _spawn_root:
		return [
			Vector3(-2.0, 0.55, 1.5),
			Vector3(2.4, 0.5, 1.6),
			Vector3(-2.6, 0.5, -1.0),
			Vector3(0.0, 0.5, -2.4),
		]
	return super.get_spawn_points()

## 将场景内 ItemHotspots 子节点注册到 "item_hotspot" 组
func _setup_level() -> void:
	var hotspot_root := get_node_or_null("ItemHotspots")
	if hotspot_root:
		for child in hotspot_root.get_children():
			if child is Node3D:
				child.add_to_group("item_hotspot")

## 决胜时刻：HUD 倒计时变红 + 屏幕边缘提示
func _on_level_decisive_moment() -> void:
	if _timer_label:
		_timer_label.modulate = Color(1.0, 0.25, 0.2)

func _on_level_ready() -> void:
	if _timer_label:
		_timer_label.modulate = Color.WHITE
