## 職責：全局信號總線，系統間解耦通訊

extends Node

# 遊戲流程
signal game_state_changed(new_state: int)
signal game_started()
signal game_over()
signal photo_taken(viewport_texture: ViewportTexture)

# 計時
signal timer_updated(seconds_remaining: float)

# 玩家
signal player_entered_zone(player_index: int)
signal player_exited_zone(player_index: int)

# 道具
signal item_picked_up(player_index: int, item: Node)
signal item_used(player_index: int, item: Node)

# 相機
signal camera_behavior_push_requested(camera_target: String, behavior: Object)
signal camera_behavior_pop_requested(camera_target: String, behavior: Object)
