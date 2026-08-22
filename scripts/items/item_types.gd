## 職責：道具系統所有枚舉定義

class_name ItemTypes

enum EffectKind {
	NONE,
	TIMER_ADD,       # 加減拍攝倒計時
	CAMERA_PUSH,     # 推入相機行為
	PLAYER_STUN,     # 眩暈目標玩家
	PLAYER_RAGDOLL,  # 觸發目標玩家布娃娃
}

enum Trigger {
	ON_PICKUP,  # 拾取時立即生效
	ON_USE,     # 玩家按使用鍵時生效
	ON_HIT,     # 道具實體碰撞命中時生效
}

enum Target {
	SELF,    # 使用者本身
	OTHERS,  # 其他所有玩家
	ALL,     # 所有玩家（含使用者）
	WORLD,   # 全局（無目標玩家）
}
