## 职责：拍照抢镜头测试关卡（PhotoStageTest）
## 基于 LevelBase 框架，用 StageBuilder 代码生成舞台 + 假人补位，便于单人测试
## 测试流程：自动开局 → 混战 12 秒（加速）→ 快门 → 结算

class_name PhotoStageTest
extends LevelBase

const TEST_BATTLE_SECONDS := 12.0

## P1 真人，其余用假人补位
func get_player_count() -> int:
	return 1

func _setup_level() -> void:
	_build_stage()
	_spawn_dummies()

## 测试场景自动开局（正式流程由主界面/匹配触发）
func _on_level_ready() -> void:
	GameManager.start_game()

## 混战开始后缩短为测试时长
func _on_level_battle_started() -> void:
	call_deferred("_apply_test_duration")

func _apply_test_duration() -> void:
	GameManager.stage_time_remaining = TEST_BATTLE_SECONDS

func _build_stage() -> void:
	if not _stage_root:
		push_warning("PhotoStageTest: 缺少 Stage 节点")
		return
	var builder := StageBuilder.new()
	builder.name = "StageBuilder"
	add_child(builder)
	builder.build_show_stage(_stage_root)

## 3 名假人演员补位（测试评分与遮挡）
func _spawn_dummies() -> void:
	var spots := [
		Vector3(2.4, 0.5, 1.6),
		Vector3(-2.6, 0.5, -1.0),
		Vector3(0.0, 2.5, -2.4),
	]
	var root: Node3D = _actors_root if _actors_root else self
	for i in spots.size():
		var dummy := DummyActor.new()
		dummy.player_index = i + 1
		dummy.player_color = PLAYER_COLORS[i + 1]
		dummy.position = spots[i]
		root.add_child(dummy)
