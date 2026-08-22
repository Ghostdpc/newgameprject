## 職責：全局信號總線，系統間解耦通訊

extends Node

# 遊戲階段
signal stage_changed(stage: int)
signal stage_timer_updated(seconds_remaining: float)
signal battle_started()
signal battle_ended()

# 拍照
signal photo_taken(viewport_texture: ViewportTexture)

# 玩家
signal player_entered_zone(player_index: int)
signal player_exited_zone(player_index: int)

# 道具
signal item_picked_up(player_index: int, item_id: String)
signal item_used(player_index: int, item_id: String)

# 服装（槽位：0 头部 / 1 身体 / 2 手持）
signal outfit_changed(player_index: int, slot: int, item_id: String)

# 相機
signal camera_behavior_push_requested(camera_target: String, behavior: Object)
signal camera_behavior_pop_requested(camera_target: String, behavior: Object)
