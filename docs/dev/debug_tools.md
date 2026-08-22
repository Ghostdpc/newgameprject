# 調試工具文檔

> 所有調試功能僅在開發模式下啟用，正式發布前應移除或禁用 `DebugVisualizer` 節點。

---

## 熱鍵一覽

| 鍵 | 功能 | 狀態 |
|----|------|------|
| `F1` | 切換碰撞體線框（橙色，穿透模型）| ✅ |
| `F2` | 切換骨骼線（青色，穿透模型）| ✅ |
| `F3` | 切換角色數據面板（左上角 HUD）| ✅ |

---

## DebugVisualizer 節點

腳本路徑：`scripts/debug/debug_visualizer.gd`（`class_name DebugVisualizer`）

### 掛載方式

在需要調試的關卡場景根節點下添加 `DebugVisualizer` 子節點即可，無需額外配置。

```
LevelScene (Node3D)
└── DebugVisualizer   ← 添加此節點
```

### 工作原理

- `_process` 每幀按開關狀態重建 `ImmediateMesh`（線框）或刷新文字面板
- 碰撞體/骨骼線均開啟 `no_depth_test = true`，穿透模型可見
- F3 面板為 `CanvasLayer`（layer=128），浮在所有 UI 上方

---

## F1 — 碰撞體線框

- 遍歷 `players` 組下所有 `CollisionShape3D`
- 支持形狀：`CapsuleShape3D`（畫環+半球）、`BoxShape3D`（畫 12 條邊）
- 顏色：橙色 `(1.0, 0.6, 0.0)`

---

## F2 — 骨骼線

- 遍歷場景中所有 `Skeleton3D`，按父骨→子骨連線
- 顏色：青色 `(0.0, 1.0, 1.0)`

---

## F3 — 角色數據面板

左上角橫排顯示，每個玩家一個半透明黑底面板。

### 展示字段

| 字段 | 數據來源 | 說明 |
|------|---------|------|
| `P1 / P2 / P3 / P4` | `player_index + 1` | 玩家編號 |
| `pos` | `global_position` | 世界坐標（精度 0.1）|
| `vel` | `velocity` | CharacterBody3D 速度向量 |
| `floor` | `is_on_floor()` | 是否站在地面 |
| `state` | `state_machine.current_state_name` | 當前狀態機狀態 |
| `item` | `held_item_id`（空=none）| 持有道具 id |
| `ragdl` | `ragdoll_rig.is_ragdoll_enabled()` | 布娃娃是否激活 |

### 擴展方法

在 `_build_player_text()` 中追加 `lines.append(...)` 即可加入新字段，無需修改其他代碼。

---

## 擴展調試功能

如需新增 Fn 熱鍵：

1. 在 `DebugVisualizer` 中新增 `var _xxx_on: bool = false`
2. 在 `_input()` 的 `elif` 鏈中加 `KEY_Fn` 分支
3. 實現 `_toggle_xxx()` 和對應的渲染/刷新邏輯
4. 在 `_process()` 中按開關調用

---

## 測試覆蓋

測試文件：`tests/test_debug_visualizer.gd`

| 測試 | 驗證 |
|------|------|
| `test_toggle_collisions_flips_state` | F1 正確切換狀態 |
| `test_toggle_bones_flips_state` | F2 正確切換狀態及 mesh 可見性 |
| `test_toggle_data_panel_flips_state` | F3 正確切換狀態及 overlay 可見性 |
| `test_data_panel_overlay_exists` | overlay / panel_root 已在 _ready 中構建 |
