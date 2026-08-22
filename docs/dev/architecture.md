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

## 道具系統

### 架構分層

```
data/configs/items.json          ← 策劃配表：id / 名稱 / trigger / effects[]
        ↓ ConfigLoader
ItemConfig (ConfigTable)         ← get_item(id) → ItemDef
        ↓
ItemDef (RefCounted, 只讀)       ← id / display_name / trigger / effects[]
ItemEffect (RefCounted, 基類)    ← kind / target / duration / params
        ↓ ItemEffectRegistry.create(kind, data)
具體效果子類                      ← apply(ctx) / revert(ctx)
        ↓ ItemSystem.use_item()
ItemSystem (autoload)            ← 解析目標 → apply → 計時 revert
```

### 枚舉（ItemTypes）

| 枚舉 | 值 | 說明 |
|------|----|------|
| `EffectKind` | `TIMER_ADD` | 增減拍攝倒計時 |
| | `CAMERA_PUSH` | 推入相機行為 |
| | `PLAYER_STUN` | 眩暈目標玩家 |
| | `PLAYER_RAGDOLL` | 觸發目標布娃娃 |
| `Trigger` | `ON_PICKUP` | 拾取時立即生效 |
| | `ON_USE` | 玩家按使用鍵觸發 |
| | `ON_HIT` | 道具實體碰撞命中觸發 |
| `Target` | `SELF` | 使用者自身 |
| | `OTHERS` | 其他所有玩家 |
| | `ALL` | 所有玩家 |
| | `WORLD` | 全局（無玩家目標）|

### 道具持有（PlayerController）

- `held_item_id: String` — 當前持有道具 id，空字符串表示無道具
- **每次只能持有 1 個**，`pickup_item()` 覆盖式替換
- `pickup_item(id)` — 拾取；`ON_PICKUP` 觸發器立即使用
- `use_held_item()` — 手動使用（Y 鍵 / 手把 Y）
- `clear_item()` — 丟棄（不觸發效果）
- 信號：`item_picked_up(id)` / `item_used(id)` / `item_cleared()`

### 新增效果步驟

1. 在 `scripts/items/effects/` 新建 `xxx_effect.gd`，繼承 `ItemEffect`
2. 覆寫 `apply(ctx)` 和（有時長時）`revert(ctx)`
3. 在 `ItemTypes.EffectKind` 加枚舉值
4. 在 `ItemDef._parse_kind()` 加字符串映射
5. 在 `ItemSystem._register_effects()` 加一行 `register()`
6. 配表 `items.json` 中 `kind` 字段填對應字符串

### 目錄結構

```
scripts/items/
├── item_types.gd              # EffectKind / Trigger / Target enum
├── item_effect.gd             # 基類
├── item_effect_registry.gd    # 靜態注冊表
├── item_def.gd                # 只讀值對象
├── item_config.gd             # ConfigTable 子類
├── item_context.gd            # 運行時上下文
├── item_system.gd             # autoload 入口
└── effects/
    ├── timer_add_effect.gd    # 增減倒計時
    └── camera_push_effect.gd  # TBD
```

---

## 打分系統

- 攝影相機渲染到 `ViewportTexture`（RT）
- 打分算法 **TBD**（待策劃確認後補充）
- 接口預留：`ScoreSystem.calculate_scores(rt: ViewportTexture) -> Array[int]`

---

## 遊戲流程

### 階段枚舉（GameManager.GameStage）
| 值 | 含義 | 默認時長 |
|----|------|---------|
| `MAIN_MENU` | 主界面 | — |
| `THEME_ANNOUNCE` | 主題公布 | 0（跳過）|
| `GRAB_CLOTHES` | 搶衣服 | 0（跳過）|
| `BATTLE` | 倒計時混戰/搶鏡頭 | 15s |
| `SCORING` | 系統評分 | 0（等待玩家操作）|

### 推進規則
1. 主界面「開始遊戲」→ 場景切換到 `game.tscn` → `GameManager.start_game()`
2. 依序執行 `STAGE_ORDER`
3. **duration = 0 → 跳過**（SCORING 除外）
4. **SCORING 且 duration = 0 → 停留，等待 `GameManager.finish_scoring()` 呼叫**
5. SCORING 結束 → 切換回 `main_menu.tscn`

### 場景結構
```
scenes/
├── ui/main_menu.tscn      # 主界面（開始/退出）
└── game/game.tscn         # 遊戲場景
    ├── HUD                # 階段名稱 + 倒計時
    └── ResultsOverlay     # SCORING 階段顯示（返回主界面/退出遊戲）
```

### 信號流
```
GameManager._process()
    → EventBus.stage_timer_updated(seconds)   ← HUD 監聽更新倒計時
GameManager._transition_to(stage)
    → EventBus.stage_changed(stage)           ← HUD / ResultsOverlay 監聽
    → EventBus.battle_started()               ← 進入 BATTLE 時
    → EventBus.battle_ended()                 ← 離開 BATTLE 時
```

---

## 配置加載系統

### ConfigLoader（Autoload）
- 統一入口讀取 `data/configs/*.json`
- 結果快取在記憶體，開發期可用 `reload()` 熱重載
- 忽略 JSON 中的 `_comment` 保留鍵
- `has_config(name)` 區分「缺文件」與「合法空表」

### ConfigTable（基類）
- 所有配置表繼承此類，聲明 `TABLE_NAME` + `DEFAULTS`
- 提供類型化 getter（`get_float/get_int/get_string/get_bool/get_array/get_dict`）
- 缺失鍵自動回退 DEFAULTS 默認值，不需手寫映射
- 集合表支持 `get_records(key)` / `get_record_by_id(key, id)`

### GameConfig
- 繼承 `ConfigTable`，讀 `data/configs/game_flow.json`
- 缺失鍵使用 DEFAULTS 默認值，不拋出錯誤
- `GameManager._ready()` 中調用 `config.load()`

### 配置目錄
```
data/
└── configs/
    ├── game_flow.json    # 遊戲流程階段時長
    └── items.json        # 道具表（TBD）
```

---

## Autoload 列表
| 名稱 | 路徑 | 職責 |
|------|------|------|
| `ConfigLoader` | `scripts/autoload/config_loader.gd` | JSON 配置讀取 + 快取 |
| `EventBus` | `scripts/autoload/event_bus.gd` | 全局信號總線 |
| `GameManager` | `scripts/autoload/game_manager.gd` | 遊戲流程控制 |
| `CameraSystem` | `scripts/autoload/camera_system.gd` | 兩個相機管理入口 |

---

## TBD 項目
- 飛撲碰撞行為細節（撞到玩家的結果）
- 打分算法具體實現
- 具體道具設計
- 聯機支持（目前僅本地 4 人）
