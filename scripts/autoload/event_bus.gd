## 職責：全局信號總線，系統間解耦通訊

extends Node

# 遊戲階段
signal stage_changed(stage: int)
signal stage_timer_updated(seconds_remaining: float)
signal battle_started()
signal battle_ended()

# 拍照
signal photo_taken(viewport_texture: ViewportTexture)
# 实拍照片已完成（capture_high_res 拍摄完成，服装等演出道具可安全清空）
signal photo_captured()

# 玩家
signal player_entered_zone(player_index: int)
signal player_exited_zone(player_index: int)

# 道具
signal item_picked_up(player_index: int, item_id: String)
signal item_used(player_index: int, item_id: String)
signal item_spawned(item_id: String, position: Vector3)
signal trap_triggered(trap_id: String, player_index: int)

# 服装（槽位：0 头部 / 1 身体 / 2 手持）
signal outfit_changed(player_index: int, slot: int, item_id: String)

# 时间道具（交互文档 §6）：effect_type 0=快进2.0x / 1=慢放0.5x / 2=加时 / 3=减时
# value：倍率类为倍率值（0 表示效果结束），加减时类为秒数
signal time_effect_applied(effect_type: int, value: float)

# 暂停开关（Esc / 房主触发）
signal game_paused_changed(paused: bool)

# 联机结算结果送达（client 由 NetManager 转发；关卡就绪后连接并展示）
signal settlement_received(results: Dictionary)
# 结算照片预览先到（分数未出），用于 client 提前显示最终照片
signal settlement_preview_received(image: Image, round: int)
# 联机表情同步（host 广播每轮各角色表情索引，client 应用）
signal faces_received(faces: Array)
# 联机单个角色表情变化（host 动作触发，如二段跳换表情；client 应用到对应 puppet）
signal face_changed(player_index: int, face_index: int)

# 相機
signal camera_behavior_push_requested(camera_target: String, behavior: Object)
signal camera_behavior_pop_requested(camera_target: String, behavior: Object)
