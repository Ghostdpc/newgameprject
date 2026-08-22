## 职责：拍照抢镜头测试关卡（PhotoStageTest）
## 基于 LevelBase 框架，用 StageBuilder 代码生成舞台
## 生成 4 个真实 PlayerController（P1 键盘，P2-P4 手柄），支持完整交互
## 测试流程：自动开局 → 混战 12 秒（加速）→ 快门 → 结算

class_name PhotoStageTest
extends LevelBase

const TEST_BATTLE_SECONDS := 12.0

## 测试场景固定 4 人
func get_player_count() -> int:
	return 4

## 出生点：舞台四角，Y 值略高于地面避免卡地
func get_spawn_points() -> Array[Vector3]:
	return [
		Vector3(-2.0, 1.0,  2.0),
		Vector3( 2.0, 1.0,  2.0),
		Vector3(-2.0, 1.0, -2.0),
		Vector3( 2.0, 1.0, -2.0),
	]

func _setup_level() -> void:
	_build_stage()

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
