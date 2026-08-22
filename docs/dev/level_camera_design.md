# 场景·相机·关卡·结算 设计文档

> 依据：`docs/别抢我镜头-完整策划方案.docx`（V1.2 修订版）
> 版本：v1.0 · 编制：2026-08-22

---

## 1. 需求要点（V1.2 相比旧案的变化）

| 变化 | 影响 |
|------|------|
| 转场并入倒计时混战 | 抢衣服一结束，倒计时立刻启动，镜头由"服装区俯拍"切为"舞台正面固定机位" |
| 删除玩家互赞 | 流程只剩：主题公布 → 抢衣服 → 混战(含转场) → 快门 → 评分 → 冠军结算 |
| 删除 Pose 系统 | 评分从六维改为**五维**，Pose 不再存在 |
| 舞台是普通舞台 | 无特殊机制；摄像范围仅由屏幕上的 **UI 取景贴花** 标示 |
| 新增时间道具 | 倒计时加速/减速/加时/减时，是核心主题道具（P0） |
| 服装效果组件化 | 3 套服装 9 件部件，单件装备即生效 |

---

## 2. 场景体系

### 2.1 场景清单

| 场景 | 路径 | 职责 |
|------|------|------|
| 主菜单 | `scenes/ui/main_menu.tscn` | 组入 2-4 人、展示主题、开始游戏 |
| 服装区（抢衣服） | `scenes/stages/grab_zone.tscn`（待建） | 抢衣服阶段场景 |
| 拍照舞台（抢镜头） | `scenes/levels/photo_stage.tscn` | 混战+快门+结算场景（本框架核心） |
| 结算面板 | `scenes/ui/results_panel.tscn` | 合照+五维分数+冠军 |

### 2.2 两个子场景的关系

策划案 V1.2 明确：**抢衣服区和拍照舞台是两个独立物理空间**，转场时玩家从服装区跑向舞台。当前代码只有一个场景。建议：

- **方案 A（推荐）**：单场景双区域 —— 同一场景内放"服装区"和"舞台"，转场时镜头+玩家一起移动过去，无需切换场景。优点：玩家状态（已穿服装、道具）不丢，转场自然；实现成本低。
- **方案 B**：双场景 switch —— 服装区场景结束时传玩家数据到舞台场景。需序列化服装/道具数据，多一层复杂度。

**建议先按方案 A**（单场景双区域），符合"转场与倒计时同步、不打断"的设计意图。

---

## 3. 场景主相机（MainCamera）

### 3.1 各阶段机位（策划案 09）

| 阶段 | 机位 | 说明 |
|------|------|------|
| 抢衣服 | 俯视角 45° 全景 | 覆盖整个服装区，争抢一目了然 |
| 混战（含转场） | 跟随式 → 舞台正面固定 | 转场即启动倒计时，镜头先跟随玩家奔跑，再锁定舞台 |
| 相机遥控器道具 | 目标点偏移插值 | 向使用者偏移 2.5 秒后平滑回正，无硬切 |

### 3.2 现有行为堆叠架构（复用）

```
CameraController（每个相机一个）
├── behavior_stack: Array[CameraBehavior]
├── push_behavior(behavior, duration)   # 道具/流程推入，带时长自动弹出
├── pop_behavior(behavior)
└── _process(): 执行栈顶行为

CameraBehavior（基类）
├── FixedShotBehavior     # 固定位置+朝向（默认机位）
├── GroupFollowBehavior   # 跟随多目标（转场跟随阶段复用）
└── [道具行为]            # 相机遥控器偏移等
```

**结论：现有架构已满足需求**。需补充的行为：

| 新行为 | 用途 |
|--------|------|
| `OffsetLeanBehavior` | 相机遥控器：镜头看向点向使用者偏移，2.5s 回正 |
| `FollowThenLockBehavior` | 转场：先跟随玩家群，到位后锁定舞台正面 |

### 3.3 主相机默认参数（舞台正面固定机位·略俯拍）

```
position  ≈ (0, 2.5~3, 12)   # 舞台正面，略俯
look_at   ≈ (0, 1.2, 0)      # 舞台中心偏上
fov       ≈ 45°
```

> 注：当前的 `(16,13,15)` 是旧 test 的斜向俯拍，正式版需改为舞台正面（+Z 侧朝 -Z 拍）。

---

## 4. 拍照相机（PhotoCamera）

### 4.1 职责

持续渲染舞台正面固定画面到 SubViewport（RT），该画面同时用于：
1. **实时叠显**：屏幕中上的取景框贴花展示（让玩家知道画面范围）
2. **快门截图**：`battle_ended` 瞬间定格，作为结算合照

### 4.2 实现结构（沿用现有）

```
PhotoStage (Node3D)
├── PhotoViewport (SubViewport, 640x360, UPDATE_ALWAYS)
│   └── PhotoCamera (Camera3D, current=true)
│       └── CameraController
└── HUD (CanvasLayer)
    └── PhotoPanel (TextureRect)   # texture = PhotoViewport.get_texture()
```

### 4.3 快门拍照流程

```
battle_ended 信号
  → LevelBase._on_battle_ended()
  → EventBus.photo_taken.emit(null)          # null = 拍照请求
  → CameraSystem._on_photo_taken(null)
      → 取 PhotoCamera 所在 viewport 的 texture
      → EventBus.photo_taken.emit(texture)   # 回传实拍
  → SettlementSystem._on_photo_taken(texture)  # 遮罩分析+五维评分
  → LevelBase._on_photo_taken(texture)         # 白闪演出
```

### 4.4 已知问题与修正

| 问题 | 状态 |
|------|------|
| 截图上下颠倒 | 已修（删除多余的 flip_y） |
| CameraProp 模型挡住相机 | 已修（相机与道具坐标分离） |

---

## 5. 关卡框架

### 5.1 分层

```
LevelBase (scripts/levels/level_base.gd)   # 玩法骨架，通用
└── PhotoStage (scripts/levels/photo_stage.gd)  # 关卡子类，只填差异
```

### 5.2 LevelBase 职责（骨架）

| 模块 | 内容 |
|------|------|
| 相机初始化 | MainCamera / PhotoCamera 各自挂默认 FixedShotBehavior + 注册到 CameraSystem |
| 玩家生成 | 按 `get_player_count()` + `get_spawn_points()` 实例化 PlayerController，只赋值 index/color |
| 信号连接 | battle_started / battle_ended / stage_timer_updated / photo_taken / settlement_completed |
| 快门演出 | battle_ended → 发拍照请求；photo_taken → 白闪 |

### 5.3 子类扩展点（策划/程序员填差异）

```gdscript
_setup_level()              # 舞台布置、道具、特殊玩法
_get_player_count()         # 真人数量 2-4
_get_spawn_points()         # 出生点
_on_level_decisive_moment() # 最后 3 秒（屏幕红灯等）
_on_level_battle_started()  # 混战开始
_on_level_photo_taken(tex)  # 收到照片
_on_level_settlement(res)   # 结算结果
```

### 5.4 一个关卡的构成（策划配置视角）

```
scenes/levels/photo_stage.tscn（策划编辑器内直接摆放）
├── Stage（Node3D）          # 舞台摆件：地板/背景板/灯光/遮挡物
├── Actors（Node3D）         # 玩家容器（自动填入）
├── SpawnPoints（Node3D）    # 出生点 Marker（默认四角）
├── MainCamera + CameraController
├── PhotoViewport/PhotoCamera + CameraController
├── HUD（含 PhotoPanel 取景框贴花）
├── ResultsPanel + SettlementSystem
└── 灯光/环境
```

**遮挡物**：需参与清晰度判定（花篮/音响等）加入 `photo_occluder` 分组；玩家加入 `settlement_actor` 分组。

---

## 6. 结算系统

### 6.1 五维评分（策划案 10，V1.2）

| 维度 | 权重 | 计分规则 |
|------|------|----------|
| 入镜程度 | 25% | 全身在取景框内满分，裁切扣分，出镜 0 分 |
| 站位优势 | 25% | 越靠画面中央越高 |
| 镜头朝向 | 15% | 正脸高分，侧/背脸扣分 |
| 清晰度遮挡 | 15% | 被遮挡越多扣分越多 |
| 服装表现 | 20% | 已装备部件数量+品质+组件效果 |

（主题加成：+5~+8 或权重调整，可选模块 P1）

### 6.2 现有实现状态

`SettlementSystem` 已实现**遮罩像素统计**：
- 入镜程度：bbox 投影裁切比 ✓
- 站位优势：质心距画面中心 ✓
- 清晰度遮挡：可见像素/预期像素 ✓
- 镜头朝向：占位 0 分（TBD，需角色朝向数据）
- 服装表现：占位 0 分（TBD，需服装数据）
- Pose：**应删除**（V1.2 已移除 Pose 系统）

### 6.3 需补的工作

1. **删 Pose 维度**，六维改五维（权重 25/25/15/15/20）
2. **镜头朝向**：从角色 forward 与相机方向点积计算（读 PlayerController 朝向，需与角色控制同事约定接口）
3. **服装表现**：需服装系统同事提供"已装备部件+品质"数据接口
4. **冠军结算**：总分排序 → 冠军高亮 + 称号（当前 ResultsPanel 只显示明细分，无冠军强调）

### 6.4 结算流程（策划案 10）

```
快门 → 慢放回放合照（0.5x+推近）→ 白闪定格 → 照片缩入相框（白边+标题栏）
→ 五维逐项亮分 → 总分排序 → 冠军高亮（皇冠+彩带+称号）
```

---

## 7. 关键待决事项（需与同事对齐）

| 事项 | 负责方 | 状态 |
|------|--------|------|
| 玩家名单（2-4 人）从匹配流程注入接口 | 流程同事 | 待定 |
| 镜头朝向数据的角色侧接口 | 角色控制同事 | 待定 |
| 服装装备数据的接口 | 服装系统同事 | 待定 |
| 单场景双区域 vs 双场景切换 | 需决策 | 建议方案 A |
| 时间道具接入 GameManager 倒计时 | 流程同事 | 待定 |

---

## 8. 目录约定（建议）

```
scripts/
├── levels/          # 关卡（LevelBase + 各关卡子类）
├── camera/          # 相机（behavior 堆叠）
│   └── behaviors/
├── systems/         # 结算/区域/计分等系统
├── player/          # 角色控制（同事负责，不在此域）
├── autoload/        # EventBus/GameManager/CameraSystem/ConfigLoader
└── ui/              # HUD/结算面板/主菜单

scenes/
├── levels/          # 各关卡场景
├── stages/          # 服装区等子舞台（若按双区域拆分）
├── ui/              # 菜单/结算面板
├── player/          # 玩家场景
└── tech_demos/      # 纯测试场（不参与正式流程）
```
