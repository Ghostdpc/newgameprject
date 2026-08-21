# 架構文檔 v1

## 遊戲概覽
- 3D 俯視角多人派對遊戲（參考猛獸派對）
- 4 人本地共享相機
- 倒計時結束前占據結算區域，根據攝影相機 RT 截圖打分排名

---

## 相機系統

### 兩個相機分工
| 相機 | 用途 | 默認行為 |
|------|------|----------|
| `MainCamera` | 渲染玩家畫面 | 固定定點（`FixedShotBehavior`），道具可臨時覆寫 |
| `PhotoCamera` | 拍攝 RT 用於打分 | 定點俯拍結算區域 |

### 相機控制架構
兩個相機都使用**行為堆疊**設計，支援道具臨時覆寫：

```
CameraController (基類)
├── behavior_stack: Array[CameraBehavior]  # 優先級 + 時效
├── push_behavior(behavior, duration)      # 道具調用
├── pop_behavior(behavior)
└── _process(): 執行棧頂行為

CameraBehavior (基類)
├── GroupFollowBehavior    # 跟隨多個目標，自動縮放（備用，當前未啟用）
├── SingleFollowBehavior   # 跟隨單一玩家（道具觸發，TBD）
└── FixedShotBehavior      # 固定位置+朝向（MainCamera 默認）
```

道具只調用 `CameraSystem.push_behavior()`，不直接操作相機節點。

---

## 角色系統

### 狀態機
```
CharacterStateMachine
├── IdleState
├── MoveState
├── JumpState
├── DiveState        # 飛撲，產生物理碰撞（細節 TBD）
├── RagdollState     # 主動布娃娃激活
└── StunnedState     # 被撲倒後恢復中
```

### 主動布娃娃
- 使用 `PhysicalBoneSimulator3D` + `PhysicalBone3D`
- 關節加 PID 控制器追蹤動畫骨骼姿勢
- 狀態切換：`AnimationBlend ↔ PhysicsSimulate`
- **技術風險項**：需先做獨立驗證場景 `scenes/tech_demos/ragdoll_demo.tscn`

### 換裝系統
骨架上預留 attachment 槽位，每個部件是獨立 `Node3D` 子節點：
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

## 道具系統（框架）

```
ItemBase (Node3D)
├── item_id: String
├── PickupComponent       # 簡化版：範圍碰撞 → 觸發拾取
└── UseComponent (基類)   # 具體道具繼承實作 use()
```

道具 `use()` 可操作：
- `CameraSystem.push_behavior()` — 影響主相機或攝影相機
- `EventBus` 信號 — 影響其他系統

---

## 打分系統

- 攝影相機渲染到 `ViewportTexture`（RT）
- 打分算法 **TBD**（待策劃確認後補充）
- 接口預留：`ScoreSystem.calculate_scores(rt: ViewportTexture) -> Array[int]`

---

## 遊戲流程

```
GameManager (Autoload)
├── 狀態: Lobby → Countdown → Playing → PhotoShot → Results
├── 信號: game_started / timer_ended / photo_taken / game_over
└── 調用: ScoreSystem / ZoneSystem / CameraSystem
```

---

## Autoload 列表
| 名稱 | 路徑 | 職責 |
|------|------|------|
| `EventBus` | `scripts/autoload/event_bus.gd` | 全局信號總線 |
| `GameManager` | `scripts/autoload/game_manager.gd` | 遊戲流程控制 |
| `CameraSystem` | `scripts/autoload/camera_system.gd` | 兩個相機管理入口 |

---

## TBD 項目
- 飛撲碰撞行為細節（撞到玩家的結果）
- 打分算法具體實現
- 具體道具設計
- 聯機支持（目前僅本地 4 人）
