## 职责：Demo 关卡 —— 组装《别抢我镜头》交互文档 S0~S7 完整体验
## 流程：大厅进入 → S3 主题公布(3s) → S4 混战(45s, HUD 全量反馈)
##       → S5 快门(0.5x 慢放+白闪) → S6 五维刷分 → S7 冠军结算(重开/返回房间)
## 舞台布置由 StageBuilder 代码生成；玩家数取大厅确认人数。

class_name DemoStage
extends LevelBase

## S5 快门慢放时长（真实毫秒）
const SHUTTER_SLOWMO_MS := 550

@onready var _hud: HUD = $HUD/MainLayer as HUD

var _slowmo_end_msec: int = 0

func get_player_count() -> int:
	return clampi(GameManager.lobby_player_count, 2, 4)

## 按大厅已加入的槽位生成玩家（P1/P3 加入则只出 P1、P3）
func get_player_slots() -> Array[int]:
	var slots := GameManager.get_joined_slots()
	if slots.is_empty():
		return super.get_player_slots()
	return slots

## 出生点：舞台四角
func get_spawn_points() -> Array[Vector3]:
	return [
		Vector3(-2.0, 1.0,  2.0),
		Vector3( 2.0, 1.0,  2.0),
		Vector3(-2.0, 1.0, -2.0),
		Vector3( 2.0, 1.0, -2.0),
	]

func _setup_level() -> void:
	if _stage_root:
		var builder := StageBuilder.new()
		builder.name = "StageBuilder"
		add_child(builder)
		builder.build_show_stage(_stage_root)
	_apply_doc_player_colors()

## 3D 角色颜色对齐三重辨识规格（与四角面板一致，结算遮罩按此色匹配）
func _apply_doc_player_colors() -> void:
	var actors := _actors_root if _actors_root else self
	for child in actors.get_children():
		var player := child as PlayerController
		if player == null:
			continue
		var c: Color = PlayerConfig.get_color(player.player_index)
		player.player_color = c
		player.apply_player_color(c)

## 关卡加载完成 → 自动进入流程（主题公布 3s 由 GameManager 驱动）
func _on_level_ready() -> void:
	GameManager.start_game()

## S5 快门：最后帧定格前 0.5x 慢放（白闪由基类处理）
func _on_level_battle_ended() -> void:
	Engine.time_scale = 0.5
	_slowmo_end_msec = Time.get_ticks_msec() + SHUTTER_SLOWMO_MS

func _process(_delta: float) -> void:
	if _slowmo_end_msec > 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_slowmo_end_msec = 0
		Engine.time_scale = 1.0

## S6/S7：结算完成 → 隐藏战斗 HUD 顶部/取景框（show_results 由 level_base 统一调用）
func _on_level_settlement(_results: Dictionary) -> void:
	if _hud:
		_hud.enter_scoring_mode()

func _on_flow_finished(action: String) -> void:
	Engine.time_scale = 1.0
	GameManager.time_rate = 1.0
	if action == "restart":
		# 重开：直接进入下一轮主题展示，保留当前玩家（大厅人数不变）
		get_tree().change_scene_to_file("res://scenes/levels/demo_stage.tscn")
	else:
		# 返回房间：回到加入状态，保留设备识别
		GameManager.enter_lobby()
