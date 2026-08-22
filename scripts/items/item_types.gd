## 職責：道具系統所有枚舉定義

class_name ItemTypes

enum EffectKind {
	NONE,
	TIMER_ADD,       # 加減拍攝倒計時
	TIMER_SCALE,     # 倒計時速率乘數，持續 N 秒後還原
	CAMERA_PUSH,     # 推入相機行為（舊接口，保留兼容）
	CAMERA_OFFSET,   # 相機機位偏移（預留，待實現）
	PLAYER_STUN,     # 眩暈目標玩家
	PLAYER_RAGDOLL,  # 觸發目標玩家布娃娃
	PLAYER_SPEED,    # 移速乘數 buff
	SPAWN_TRAP,      # 在使用者位置生成放置物
	BANANA_SLIDE,    # 香蕉皮滑行衝量 + 躺下
}

enum Trigger {
	ON_PICKUP,  # 拾取時立即生效
	ON_USE,     # 玩家按使用鍵時生效
	ON_HIT,     # 道具實體碰撞命中時生效
	ON_STEP,    # 放置物被踩踏時生效（TrapInstance 專用）
}

enum Target {
	SELF,    # 使用者本身
	OTHERS,  # 其他所有玩家
	ALL,     # 所有玩家（含使用者）
	WORLD,   # 全局（無目標玩家）
}
