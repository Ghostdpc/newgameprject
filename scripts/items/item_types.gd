## 职责：道具系统所有枚举定义

class_name ItemTypes

enum EffectKind {
	NONE,
	TIMER_ADD,       # 加减拍摄倒计时
	TIMER_SCALE,     # 倒计时速率乘数，持续 N 秒后还原
	CAMERA_PUSH,     # 推入相机行为（旧接口，保留兼容）
	CAMERA_OFFSET,   # 相机机位偏移（预留，待实现）
	PLAYER_STUN,     # 眩晕目标玩家
	PLAYER_RAGDOLL,  # 触发目标玩家布娃娃
	PLAYER_SPEED,    # 移速乘数 buff
	SPAWN_TRAP,           # 在使用者位置生成放置物
	BANANA_SLIDE,         # 香蕉皮滑行冲量 + 躺下
	THROW_BOMB,           # 投掷炸弹：抛出物理体，引信后范围爆炸
	PLAYER_GRAY,          # 灰头土脸：角色身上叠脏污贴花，随时间褪去
	# 服装专属效果（on_wear 生效 / on_remove 还原，duration = 0 永久持续）
	GARMENT_HEAD_SCALE,   # 放大头部
	GARMENT_BODY_SCALE,   # 放大身躯 + 加宽
	GARMENT_SPRING_WOBBLE,# 弹簧骨骼 kowtow 软糯
	GARMENT_EMISSION_GLOW,# 全身自发光
}

enum Trigger {
	ON_PICKUP,  # 拾取时立即生效
	ON_USE,     # 玩家按使用键时生效
	ON_HIT,     # 道具实体碰撞命中时生效
	ON_STEP,    # 放置物被踩踏时生效（TrapInstance 专用）
}

enum Target {
	SELF,    # 使用者本身
	OTHERS,  # 其他所有玩家
	ALL,     # 所有玩家（含使用者）
	WORLD,   # 全局（无目标玩家）
}
