# 调试工具文档

> 所有调试功能仅在开发模式下启用，正式发布前应移除或禁用 `DebugVisualizer` 节点。

---

## 热键一览

| 键 | 功能 | 状态 |
|----|------|------|
| `F1` | 切换碰撞体线框（橙色，穿透模型）| ✅ |
| `F2` | 切换骨骼线（青色，穿透模型）| ✅ |
| `F3` | 切换角色数据面板（左上角 HUD）| ✅ |
| `F4` | 暂停 / 恢复倒计时结算 | ✅ |
| `F5` | 向 P1 注入下一个道具并立即使用 | ✅ |

---

## DebugVisualizer 节点

脚本路径：`scripts/debug/debug_visualizer.gd`（`class_name DebugVisualizer`）

### 挂载方式

在需要调试的关卡场景根节点下添加 `DebugVisualizer` 子节点即可，无需额外配置。

```
LevelScene (Node3D)
└── DebugVisualizer   ← 添加此节点
```

### 工作原理

- `_process` 每帧按开关状态重建 `ImmediateMesh`（线框）或刷新文字面板
- 碰撞体/骨骼线均开启 `no_depth_test = true`，穿透模型可见
- F3 面板为 `CanvasLayer`（layer=128），浮在所有 UI 上方

---

## F1 — 碰撞体线框

- 遍历 `players` 组下所有 `CollisionShape3D`
- 支持形状：`CapsuleShape3D`（画环+半球）、`BoxShape3D`（画 12 条边）
- 颜色：橙色 `(1.0, 0.6, 0.0)`

---

## F2 — 骨骼线

- 遍历场景中所有 `Skeleton3D`，按父骨→子骨连线
- 颜色：青色 `(0.0, 1.0, 1.0)`

---

## F3 — 角色数据面板

左上角横排显示，每个玩家一个半透明黑底面板。

### 展示字段

| 字段 | 数据来源 | 说明 |
|------|---------|------|
| `P1 / P2 / P3 / P4` | `player_index + 1` | 玩家编号 |
| `pos` | `global_position` | 世界坐标（精度 0.1）|
| `vel` | `velocity` | CharacterBody3D 速度向量 |
| `floor` | `is_on_floor()` | 是否站在地面 |
| `state` | `state_machine.current_state_name` | 当前状态机状态 |
| `item` | `held_item_id`（空=none）| 持有道具 id |
| `ragdl` | `ragdoll_rig.is_ragdoll_enabled()` | 布娃娃是否激活 |

### 扩展方法

在 `_build_player_text()` 中追加 `lines.append(...)` 即可加入新字段，无需修改其他代码。

---

## F4 — 暂停 / 恢复倒计时

- 切换 `GameManager.time_scale` 在 `0.0`（冻结）和 `1.0`（正常）之间
- 倒计时数值保持不变，结算不会触发，可用于截图 / 测试道具效果
- 再次按 F4 恢复正常流速

---

## F5 — 注入道具

- 每按一次，按以下顺序循环向 **P1** 注入一个道具并立即使用：

```
energy_drink → banana_peel → fast_forward_crank → slow_hourglass
→ time_battery → time_scissors → camera_remote → (循环)
```

- 直接调用 `p1.use_held_item()`，走完整的 `ItemSystem.use_item()` 链路
- `camera_remote` 当前为预留接口，会在 Console 打印 warning，不影响其他功能

---

## 扩展调试功能

如需新增 Fn 热键：

1. 在 `DebugVisualizer` 中新增 `var _xxx_on: bool = false`
2. 在 `_input()` 的 `elif` 链中加 `KEY_Fn` 分支
3. 实现 `_toggle_xxx()` 和对应的渲染/刷新逻辑
4. 在 `_process()` 中按开关调用

---

## 测试覆盖

测试文件：`tests/test_debug_visualizer.gd`

| 测试 | 验证 |
|------|------|
| `test_toggle_collisions_flips_state` | F1 正确切换状态 |
| `test_toggle_bones_flips_state` | F2 正确切换状态及 mesh 可见性 |
| `test_toggle_data_panel_flips_state` | F3 正确切换状态及 overlay 可见性 |
| `test_data_panel_overlay_exists` | overlay / panel_root 已在 _ready 中构建 |


---

## DebugVisualizer 节点

脚本路径：`scripts/debug/debug_visualizer.gd`（`class_name DebugVisualizer`）

### 挂载方式

在需要调试的关卡场景根节点下添加 `DebugVisualizer` 子节点即可，无需额外配置。

```
LevelScene (Node3D)
└── DebugVisualizer   ← 添加此节点
```

### 工作原理

- `_process` 每帧按开关状态重建 `ImmediateMesh`（线框）或刷新文字面板
- 碰撞体/骨骼线均开启 `no_depth_test = true`，穿透模型可见
- F3 面板为 `CanvasLayer`（layer=128），浮在所有 UI 上方

---

## F1 — 碰撞体线框

- 遍历 `players` 组下所有 `CollisionShape3D`
- 支持形状：`CapsuleShape3D`（画环+半球）、`BoxShape3D`（画 12 条边）
- 颜色：橙色 `(1.0, 0.6, 0.0)`

---

## F2 — 骨骼线

- 遍历场景中所有 `Skeleton3D`，按父骨→子骨连线
- 颜色：青色 `(0.0, 1.0, 1.0)`

---

## F3 — 角色数据面板

左上角横排显示，每个玩家一个半透明黑底面板。

### 展示字段

| 字段 | 数据来源 | 说明 |
|------|---------|------|
| `P1 / P2 / P3 / P4` | `player_index + 1` | 玩家编号 |
| `pos` | `global_position` | 世界坐标（精度 0.1）|
| `vel` | `velocity` | CharacterBody3D 速度向量 |
| `floor` | `is_on_floor()` | 是否站在地面 |
| `state` | `state_machine.current_state_name` | 当前状态机状态 |
| `item` | `held_item_id`（空=none）| 持有道具 id |
| `ragdl` | `ragdoll_rig.is_ragdoll_enabled()` | 布娃娃是否激活 |

### 扩展方法

在 `_build_player_text()` 中追加 `lines.append(...)` 即可加入新字段，无需修改其他代码。

---

## 扩展调试功能

如需新增 Fn 热键：

1. 在 `DebugVisualizer` 中新增 `var _xxx_on: bool = false`
2. 在 `_input()` 的 `elif` 链中加 `KEY_Fn` 分支
3. 实现 `_toggle_xxx()` 和对应的渲染/刷新逻辑
4. 在 `_process()` 中按开关调用

---

## 测试覆盖

测试文件：`tests/test_debug_visualizer.gd`

| 测试 | 验证 |
|------|------|
| `test_toggle_collisions_flips_state` | F1 正确切换状态 |
| `test_toggle_bones_flips_state` | F2 正确切换状态及 mesh 可见性 |
| `test_toggle_data_panel_flips_state` | F3 正确切换状态及 overlay 可见性 |
| `test_data_panel_overlay_exists` | overlay / panel_root 已在 _ready 中构建 |
