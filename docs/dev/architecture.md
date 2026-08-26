# 架构文档 v1

## 游戏概览
- 3D 俯视角多人派对游戏（参考猛兽派对）
- 4 人本地共享相机
- 倒计时结束前占据结算区域，根据摄影相机 RT 截图打分排名

---

## 相机系统

### 两个相机分工
| 相机 | 用途 | 默认行为 |
|------|------|----------|
| `MainCamera` | 渲染玩家画面 | 固定定点（`FixedShotBehavior`），道具可临时覆写 |
| `PhotoCamera` | 拍摄 RT 用于打分 | 定点俯拍结算区域 |

### 相机控制架构
两个相机都使用**行为堆叠**设计，支援道具临时覆写：

```
CameraController (基类)
├── behavior_stack: Array[CameraBehavior]  # 优先级 + 时效
├── push_behavior(behavior, duration)      # 道具调用
├── pop_behavior(behavior)
└── _process(): 执行栈顶行为

CameraBehavior (基类)
├── GroupFollowBehavior    # 跟随多个目标，自动缩放（备用，当前未启用）
├── SingleFollowBehavior   # 跟随单一玩家（道具触发，TBD）
└── FixedShotBehavior      # 固定位置+朝向（MainCamera 默认）
```

道具只调用 `CameraSystem.push_behavior()`，不直接操作相机节点。

---

## 角色系统

### 状态机
```
CharacterStateMachine
├── IdleState
├── MoveState
├── JumpState
├── DiveState        # 飞扑，产生物理碰撞（细节 TBD）
├── RagdollState     # 主动布娃娃激活
└── StunnedState     # 被扑倒后恢复中
```

### 主动布娃娃
- 使用 `PhysicalBoneSimulator3D` + `PhysicalBone3D`
- 关节加 PID 控制器追踪动画骨骼姿势
- 状态切换：`AnimationBlend ↔ PhysicsSimulate`
- **技术风险项**：需先做独立验证场景 `scenes/tech_demos/ragdoll_demo.tscn`

### 换装系统
骨架上预留 attachment 槽位，每个部件是独立 `Node3D` 子节点：
```
CharacterRig
└── Skeleton3D
    ├── BoneAttachment3D "hat_slot"
    ├── BoneAttachment3D "shirt_slot"
    └── BoneAttachment3D "accessory_slot"

OutfitManager
├── equip(slot: String, item_mesh: PackedScene)
└── unequip(slot: String)
```

---

## 道具系统

### 架构分层

```
data/configs/items.json          ← 策划配表：id / 名称 / trigger / effects[]
        ↓ ConfigLoader
ItemConfig (ConfigTable)         ← get_item(id) → ItemDef
        ↓
ItemDef (RefCounted, 只读)       ← id / display_name / trigger / effects[]
ItemEffect (RefCounted, 基类)    ← kind / target / duration / params
        ↓ ItemEffectRegistry.create(kind, data)
具体效果子类                      ← apply(ctx) / revert(ctx)
        ↓ ItemSystem.use_item()
ItemSystem (autoload)            ← 解析目标 → apply → 计时 revert
```

### 枚举（ItemTypes）

| 枚举 | 值 | 说明 |
|------|----|------|
| `EffectKind` | `TIMER_ADD` | 增减拍摄倒计时 |
| | `CAMERA_PUSH` | 推入相机行为 |
| | `PLAYER_STUN` | 眩晕目标玩家 |
| | `PLAYER_RAGDOLL` | 触发目标布娃娃 |
| `Trigger` | `ON_PICKUP` | 拾取时立即生效 |
| | `ON_USE` | 玩家按使用键触发 |
| | `ON_HIT` | 道具实体碰撞命中触发 |
| `Target` | `SELF` | 使用者自身 |
| | `OTHERS` | 其他所有玩家 |
| | `ALL` | 所有玩家 |
| | `WORLD` | 全局（无玩家目标）|

### 道具持有（PlayerController）

- `held_item_id: String` — 当前持有道具 id，空字符串表示无道具
- **每次只能持有 1 个**，`pickup_item()` 覆盖式替换
- `pickup_item(id)` — 拾取；`ON_PICKUP` 触发器立即使用
- `use_held_item()` — 手动使用（Y 键 / 手把 Y）
- `clear_item()` — 丢弃（不触发效果）
- 信号：`item_picked_up(id)` / `item_used(id)` / `item_cleared()`

### 新增效果步骤

1. 在 `scripts/items/effects/` 新建 `xxx_effect.gd`，继承 `ItemEffect`
2. 覆写 `apply(ctx)` 和（有时长时）`revert(ctx)`
3. 在 `ItemTypes.EffectKind` 加枚举值
4. 在 `ItemDef._parse_kind()` 加字符串映射
5. 在 `ItemSystem._register_effects()` 加一行 `register()`
6. 配表 `items.json` 中 `kind` 字段填对应字符串

### 目录结构

```
scripts/items/
├── item_types.gd              # EffectKind / Trigger / Target enum
├── item_effect.gd             # 基类
├── item_effect_registry.gd    # 静态注册表
├── item_def.gd                # 只读值对象
├── item_config.gd             # ConfigTable 子类
├── item_context.gd            # 运行时上下文
├── item_system.gd             # autoload 入口
└── effects/
    ├── timer_add_effect.gd    # 增减倒计时
    └── camera_push_effect.gd  # TBD
```

---

## 打分系统

- 摄影相机渲染到 `ViewportTexture`（RT）
- 打分算法 **TBD**（待策划确认后补充）
- 接口预留：`ScoreSystem.calculate_scores(rt: ViewportTexture) -> Array[int]`

---

## 游戏流程

### 阶段枚举（GameManager.GameStage）
| 值 | 含义 | 默认时长 |
|----|------|---------|
| `MAIN_MENU` | 主界面 | — |
| `THEME_ANNOUNCE` | 主题公布 | 0（跳过）|
| `GRAB_CLOTHES` | 抢衣服 | 0（跳过）|
| `BATTLE` | 倒计时混战/抢镜头 | 15s |
| `SCORING` | 系统评分 | 0（等待玩家操作）|

### 推进规则
1. 主界面「开始游戏」→ 场景切换到 `game.tscn` → `GameManager.start_game()`
2. 依序执行 `STAGE_ORDER`
3. **duration = 0 → 跳过**（SCORING 除外）
4. **SCORING 且 duration = 0 → 停留，等待 `GameManager.finish_scoring()` 呼叫**
5. SCORING 结束 → 切换回 `main_menu.tscn`

### 场景结构
```
scenes/
├── ui/main_menu.tscn      # 主界面（开始/退出）
└── game/game.tscn         # 游戏场景
    ├── HUD                # 阶段名称 + 倒计时
    └── ResultsOverlay     # SCORING 阶段显示（返回主界面/退出游戏）
```

### 信号流
```
GameManager._process()
    → EventBus.stage_timer_updated(seconds)   ← HUD 监听更新倒计时
GameManager._transition_to(stage)
    → EventBus.stage_changed(stage)           ← HUD / ResultsOverlay 监听
    → EventBus.battle_started()               ← 进入 BATTLE 时
    → EventBus.battle_ended()                 ← 离开 BATTLE 时
```

---

## 配置加载系统

### ConfigLoader（Autoload）
- 统一入口读取 `data/configs/*.json`
- 结果快取在记忆体，开发期可用 `reload()` 热重载
- 忽略 JSON 中的 `_comment` 保留键
- `has_config(name)` 区分「缺文件」与「合法空表」

### ConfigTable（基类）
- 所有配置表继承此类，声明 `TABLE_NAME` + `DEFAULTS`
- 提供类型化 getter（`get_float/get_int/get_string/get_bool/get_array/get_dict`）
- 缺失键自动回退 DEFAULTS 默认值，不需手写映射
- 集合表支持 `get_records(key)` / `get_record_by_id(key, id)`

### GameConfig
- 继承 `ConfigTable`，读 `data/configs/game_flow.json`
- 缺失键使用 DEFAULTS 默认值，不抛出错误
- `GameManager._ready()` 中调用 `config.load()`

### 配置目录
```
data/
└── configs/
    ├── game_flow.json    # 游戏流程阶段时长
    └── items.json        # 道具表（TBD）
```

---

## Autoload 列表
| 名称 | 路径 | 职责 |
|------|------|------|
| `ConfigLoader` | `scripts/autoload/config_loader.gd` | JSON 配置读取 + 快取 |
| `EventBus` | `scripts/autoload/event_bus.gd` | 全局信号总线 |
| `GameManager` | `scripts/autoload/game_manager.gd` | 游戏流程控制 |
| `CameraSystem` | `scripts/autoload/camera_system.gd` | 两个相机管理入口 |

---

## TBD 项目
- 飞扑碰撞行为细节（撞到玩家的结果）
- 打分算法具体实现
- 具体道具设计
- 联机支持（目前仅本地 4 人）
