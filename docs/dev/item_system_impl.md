# 道具系统实现设计文档

> 版本：v1.0 · 2026-08-22  
> 范围：新增 effect kind、道具生成系统（ItemSpawner）、放置物系统（TrapSystem）

---

## 一、本次新增内容概览

| 模块 | 新增/修改 | 说明 |
|------|----------|------|
| `item_types.gd` | 修改 | 新增 `TIMER_SCALE`、`PLAYER_SPEED`、`CAMERA_OFFSET`、`SPAWN_TRAP`；新增 `ON_STEP` trigger |
| `item_def.gd` | 修改 | `_parse_kind` / `_parse_trigger` 新增对应映射 |
| `item_system.gd` | 修改 | `_register_effects` 注册新 effect 类；新增 `spawn_config` 读取接口 |
| `item_config.gd` | 修改 | 新增 `get_spawn_config()` / `all_trap_defs()` / `get_trap(id)` |
| `effects/timer_add_effect.gd` | 修改 | 支持 `min_clamp` 参数 |
| `effects/timer_scale_effect.gd` | 新增 | 倒计时倍速，apply 改速率，revert 还原 |
| `effects/player_speed_effect.gd` | 新增 | 移速乘数 buff，apply 设倍率，revert 清除 |
| `effects/camera_offset_effect.gd` | 新增 | 预留接口，apply 打 warning，revert 空实现 |
| `effects/spawn_trap_effect.gd` | 新增 | 在使用者位置生成 TrapInstance 节点 |
| `items/trap_def.gd` | 新增 | 放置物只读定义，结构同 ItemDef（id/lifetime/trigger/effects） |
| `items/trap_instance.gd` | 新增 | 场景节点，Area3D，检测踩踏，触发 effects |
| `items/item_spawner.gd` | 新增 | Autoload，读 spawn_config，管理场上道具箱刷新 |

---

## 二、枚举变更（item_types.gd）

### EffectKind 新增

| 枚举值 | JSON 字符串 | 说明 |
|--------|------------|------|
| `TIMER_SCALE` | `"timer_scale"` | 倒计时速率乘数，持续 N 秒后还原 |
| `PLAYER_SPEED` | `"player_speed"` | 移速乘数 buff，持续 effect.duration 秒 |
| `CAMERA_OFFSET` | `"camera_offset"` | 相机偏移（接口预留，待 CameraSystem 实现）|
| `SPAWN_TRAP` | `"spawn_trap"` | 在使用者位置生成放置物 |

### Trigger 新增

| 枚举值 | JSON 字符串 | 说明 |
|--------|------------|------|
| `ON_STEP` | `"on_step"` | 放置物被踩踏时触发（TrapInstance 专用）|

---

## 三、effect 实现规范

### timer_add_effect（修改）
- `params.min_clamp: float`（可选，缺省 `0.0`）
- `apply`：`stage_time_remaining = clampf(remaining + delta, min_clamp, INF)`

### timer_scale_effect（新增）
- `params.scale: float`，`params.seconds: float`
- `apply`：向 `GameManager` 写入 `time_scale`（新增字段），并启动内部计时
- `revert`：还原 `time_scale = 1.0`
- **`GameManager` 侧**：`_process` 中 `stage_time_remaining -= delta * time_scale`

### player_speed_effect（新增）
- `params.multiplier: float`
- `apply`：调用 `PlayerController.set_speed_multiplier(multiplier)`
- `revert`：调用 `PlayerController.set_speed_multiplier(1.0)`
- **`PlayerController` 侧**：新增 `speed_multiplier: float = 1.0`，`apply_move` 中乘以该值

### camera_offset_effect（新增，预留接口）
- `apply`：`push_warning("camera_offset: not yet implemented")`
- `revert`：空

### spawn_trap_effect（新增）
- `params.trap_id: String`
- `apply`：从 `ItemSystem._item_config.get_trap(trap_id)` 取 `TrapDef`，实例化 `TrapInstance` 并添加到场景树，位置 = `ctx.source_player.global_position`

---

## 四、放置物系统

### TrapDef（trap_def.gd）
```
class_name TrapDef extends RefCounted
  id: String
  display_name: String
  lifetime: float        # 0 = 永久存在直到触发
  trigger: ItemTypes.Trigger   # 固定 ON_STEP
  effects: Array[ItemEffect]

  static func from_dict(d: Dictionary) -> TrapDef
```

### TrapInstance（trap_instance.gd）
```
class_name TrapInstance extends Area3D
  var trap_def: TrapDef
  var owner_player: PlayerController   # 放置者（可踩中自己）
  var _lifetime_timer: float

  func setup(def: TrapDef, placer: PlayerController) -> void
  func _process(delta):
      # lifetime > 0 时计时，超时 queue_free
  func _on_body_entered(body):
      # body is PlayerController → 触发 effects，queue_free
```

- `_on_body_entered` 循环 `trap_def.effects`，为踩踏者构建 `ItemContext`（`source_player = body`），调用 `effect.apply(ctx)`
- 触发后立即 `queue_free()`（单次触发）
- 放置物加入 `"traps"` group，方便调试/清场

### ItemConfig 新增接口
```gdscript
func get_spawn_config() -> Dictionary   # 返回 spawn_config 字典
func all_trap_defs() -> Array[TrapDef]  # 返回所有 traps[] 定义
func get_trap(id: String) -> TrapDef    # 按 id 查找，不存在返回 null
```

---

## 五、道具生成系统（ItemSpawner）

### 职责
- 读 `spawn_config`（`max_active` / `respawn_interval`）
- 在关卡热点（`"item_hotspot"` group）随机空闲位置生成道具箱
- 追踪场上箱子数量，低于 `max_active` 时每 `respawn_interval` 秒补 1 个
- 道具类型从 `items[]` 所有 id 中均匀随机

### 节点结构
```
ItemSpawner（Autoload / Node）
  _active_boxes: Array[Node]       # 场上存活箱子
  _hotspots: Array[Node3D]         # 从 "item_hotspot" group 获取
  _respawn_timer: float
  _spawn_config: Dictionary
  _item_ids: Array[String]

  func setup() -> void             # 关卡加载后调用（battle_started 信号触发）
  func _process(delta) -> void
  func _try_spawn() -> void        # 选空闲热点 → 生成箱子场景
  func _on_box_collected(box) -> void
```

### 道具箱场景（待创建）
- `scenes/items/item_box.tscn`：`Area3D` + `MeshInstance3D`
- 碰撞进入时调用 `player.pickup_item(item_id)` 并 `queue_free()`
- 暴露 `item_id: String` 属性，由 `ItemSpawner` 在生成后赋值

---

## 六、文件目录变更

```
scripts/items/
├── item_types.gd               ← 修改（新增枚举）
├── item_def.gd                 ← 修改（新增 kind/trigger 映射）
├── item_config.gd              ← 修改（新增 get_spawn_config/get_trap）
├── item_system.gd              ← 修改（注册新 effect；读 spawn_config）
├── item_effect.gd              ← 不变
├── item_effect_registry.gd     ← 不变
├── item_context.gd             ← 不变
├── trap_def.gd                 ← 新增
├── trap_instance.gd            ← 新增
├── item_spawner.gd             ← 新增（Autoload）
└── effects/
    ├── timer_add_effect.gd     ← 修改（min_clamp）
    ├── timer_scale_effect.gd   ← 新增
    ← player_speed_effect.gd   ← 新增
    ├── camera_offset_effect.gd ← 新增（预留接口）
    └── spawn_trap_effect.gd    ← 新增

scripts/autoload/
└── game_manager.gd             ← 修改（time_scale 字段；_process 乘以 time_scale）

scripts/player/
└── player_controller.gd        ← 修改（speed_multiplier 字段；apply_move 乘以该值）

scenes/items/
└── item_box.tscn               ← 新增（道具箱场景）

data/configs/
└── items.json                  ← 已更新（策划 7 道具 + traps[]）
```

---

## 七、Autoload 变更

| 名称 | 路径 | 变更 |
|------|------|------|
| `ItemSpawner` | `scripts/items/item_spawner.gd` | **新增** |

`ItemSpawner` 监听 `EventBus.battle_started` 信号后执行 `setup()`，监听 `EventBus.battle_ended` 后清空场上所有箱子和放置物。

---

## 八、信号变更（event_bus.gd）

新增：
```gdscript
signal item_spawned(item_id: String, position: Vector3)   # 道具箱生成
signal trap_triggered(trap_id: String, player_index: int) # 放置物触发
```

---

## 九、实现顺序

1. `item_types.gd` — 枚举扩展
2. `item_def.gd` — 字符串映射
3. `game_manager.gd` — 新增 `time_scale`
4. `player_controller.gd` — 新增 `speed_multiplier`
5. effects 五个文件（timer_add 修改 + 4 个新增）
6. `item_system.gd` — 注册新 effect
7. `trap_def.gd` + `trap_instance.gd`
8. `item_config.gd` — 新增接口
9. `item_spawner.gd` + `item_box.tscn`
10. `event_bus.gd` — 新增信号
