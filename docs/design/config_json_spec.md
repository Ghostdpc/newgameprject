# JSON 配置数据规范

> 本文件面向策划，说明如何填写和新增 JSON 配置文件。

---

## 目录位置

所有配置文件放在：
```
data/configs/
└── *.json
```

---

## 文件命名规范

- 全小写 `snake_case`，例如：`game_flow.json`、`items.json`
- 名称对应配置功能类别，不要缩写

---

## JSON 格式规则

| 规则 | 说明 |
|------|------|
| 编码 | UTF-8，无 BOM |
| 缩进 | 2 个空格 |
| 键名 | 全小写 `snake_case` |
| 布尔值 | `true` / `false`（小写，不用 0/1） |
| 注释 | 不支持 `//`，用 `"_comment": "..."` 代替 |
| 末尾逗号 | 不允许（标准 JSON） |

---

## 数值类型对照

| 用途 | JSON 类型 | 示例 |
|------|-----------|------|
| 时长（秒） | number（可带小数） | `15`、`1.5` |
| 计数 | number（整数） | `4` |
| 开关 | boolean | `true` |
| 名称 / ID | string | `"grab_hat"` |
| 列表 | array | `["a", "b"]` |
| 嵌套配置 | object | `{ "x": 1 }` |

---

## 通用语义约定

- **duration 类键（时长）**：
  - `0` = **跳过此阶段** 或 **等待玩家手动确认**（具体语义见各文件说明）
  - 正数 = 按秒计时自动推进
- **缺失的键** → 使用代码默认值，不会报错
- `_comment` 键仅作说明，程序加载时会自动忽略

---

## 现有配置文件

### `game_flow.json` — 游戏流程阶段时长

```json
{
  "_comment": "游戏流程各阶段时长（秒）。0 = 跳过；SCORING 的 0 = 等待玩家手动确认",
  "theme_announce_duration": 0,
  "grab_clothes_duration": 0,
  "battle_duration": 15,
  "scoring_duration": 0
}
```

| 键 | 说明 | 默认值 |
|----|------|--------|
| `theme_announce_duration` | 主题公布展示时长 | `0`（跳过）|
| `grab_clothes_duration` | 抢衣服阶段时长 | `0`（跳过）|
| `battle_duration` | 抢镜头核心玩法时长 | `15` |
| `scoring_duration` | 结算展示时长 | `0`（等待操作）|

---

### `items.json` — 道具表

道具表由两部分组成：**全局生成配置** 和 **道具定义列表**。

#### 全局生成配置

```json
{
  "spawn_config": {
    "max_active": 5,
    "respawn_interval": 8.0
  }
}
```

| 键 | 类型 | 说明 |
|----|------|------|
| `max_active` | number（整数） | 场上同时存在的道具箱上限；从 `items[]` 中随机选取类型生成 |
| `respawn_interval` | number（秒） | 每次补充一个道具箱的间隔时长 |

> 场上道具箱数量低于 `max_active` 时，每经过 `respawn_interval` 秒在空闲热点补充 1 个，新道具类型从 `items[]` 中均匀随机。

#### 道具根字段

| 键 | 类型 | 说明 |
|----|------|------|
| `id` | string | 唯一 ID，代码通过此查询 |
| `display_name` | string | 显示名称（UI 用）|
| `trigger` | string | 触发时机，见下方 **trigger 类型表** |
| `use_vfx` | string（可选） | 使用道具时播放的特效场景路径（`res://`）；缺省则不播放 |
| `use_vfx_mode` | string（可选） | 特效播放位置，见下方 **use_vfx_mode 说明**；缺省 `world` |
| `effects` | array | 效果列表（顺序执行）|

#### use_vfx_mode 说明

| 值 | 行为 | 适用场景 |
|----|------|---------|
| `world` | 在使用者当前世界坐标播放，不跟随 | 放置物类（香蕉皮扔出）、原地触发 |
| `attach_player` | 挂载到使用者节点，跟随玩家移动直到播完 | 自身增益类（能量饮料加速）|
| `attach_camera` | 挂载到当前相机节点，靠近镜头呈现全屏感 | 全局效果类（时间加减、相机遥控）|

#### trigger 类型表

| trigger | 触发时机 | 适用场景 |
|---------|---------|---------|
| `on_use` | 玩家主动按使用键时触发 | 大多数主动道具 |
| `on_pickup` | 拾取瞬间触发，不进入手持槽 | 即时效果道具 |
| `on_hit` | 被扑击命中时触发 | 被动反应道具 |
| `on_step` | **放置物**被玩家踩踏时触发 | 香蕉皮等陷阱型道具（见放置物系统）|

#### effects[] 字段

| 键 | 类型 | 说明 |
|----|------|------|
| `kind` | string | 效果类型（见下表）|
| `target` | string | 目标：`self` / `others` / `all` / `world` |
| `duration` | number | 持续时长（秒），`0` = 瞬发 |
| `params` | object | 效果参数，依 kind 不同而异 |

#### 已支持的 kind

| kind | 目标语义 | params 字段 | 说明 |
|------|---------|-------------|------|
| `timer_add` | `world` | `delta: float`<br>`min_clamp: float`（可选） | 增减当前倒计时（负数=减）；`min_clamp` 设置倒计时下限，缺省不限 |
| `timer_scale` | `world` | `scale: float`<br>`seconds: float` | 将倒计时速率乘以 `scale`，持续 `seconds` 秒后恢复；`<1` = 慢，`>1` = 快 |
| `player_speed` | `self` / `others` / `all` | `multiplier: float` | 将目标移速乘以 `multiplier`，持续 effect `duration` 秒；`<1` = 减速，`>1` = 加速 |
| `camera_offset` | `self` | `duration: float` | 将镜头机位平滑偏移至使用者方向，持续 `duration` 秒后回正；**⚠️ 接口已预留，待实现** |
| `spawn_trap` | `world` | `trap_id: string` | 在使用者当前位置生成一个放置物（陷阱），trap_id 对应 `traps[]` 中的定义；见放置物系统 |
| `player_stun` | `self` / `others` / `all` | `seconds: float` | 眩晕玩家（待实现）|
| `player_ragdoll` | `self` / `others` / `all` | — | 触发布娃娃（待实现）|
| `throw_bomb` | `world` | `throw_speed: float`<br>`fuse: float`<br>`radius: float`<br>`gray_duration: float`<br>`score_penalty: int` | 从使用者手前抛出炸弹（物理抛物线），`fuse` 秒后引爆；爆炸对半径 `radius` 内所有玩家施加灰头土脸贴花（持续 `gray_duration` 秒）并累计 `score_penalty` 积分惩罚 |
| `player_gray` | `self` / `others` / `all` | `duration: float` | 灰头土脸：在目标玩家身上叠程序生成的脏污贴花，`duration` 秒后淡出 |

---

### 放置物系统（traps）

`items.json` 内新增顶级键 `traps[]`，定义可被 `spawn_trap` effect 生成的放置物。

```json
{
  "traps": [
    {
      "id": "banana_peel",
      "display_name": "香蕉皮",
      "lifetime": 15.0,
      "trigger": "on_step",
      "effects": [
        {
          "kind": "player_ragdoll",
          "target": "self",
          "duration": 1.5,
          "params": {}
        }
      ]
    }
  ]
}
```

#### traps[] 根字段

| 键 | 类型 | 说明 |
|----|------|------|
| `id` | string | 唯一 ID，与 `spawn_trap.params.trap_id` 对应 |
| `display_name` | string | 显示名称（UI 用）|
| `lifetime` | number（秒） | 放置物在场上存活时长，到期自动消失；`0` = 永久存在直到触发 |
| `trigger` | string | 放置物触发时机，当前仅支持 `on_step` |
| `use_vfx` | string（可选） | 放置物被触发时播放的特效场景路径（`res://`）；缺省则不播放 |
| `use_vfx_mode` | string（可选） | 特效播放位置，同道具 `use_vfx_mode`；放置物通常固定为 `world`（触发点） |
| `effects` | array | 触发后对踩踏者执行的效果列表，字段同 effects[] |

> **规则补充：**
> - 放置物归属于放置者；踩踏者可以是任意玩家（含放置者自身）。
> - 放置物被触发后立即消失（单次触发）。
> - 被道具效果（如 `player_speed` 使移速过快）踩踏同样触发。

---

### 完整 `items.json` 示例结构

```json
{
  "_comment": "道具表。spawn_config 控制场上生成；items[] 为道具定义；traps[] 为放置物定义",
  "spawn_config": {
    "max_active": 5,
    "respawn_interval": 8.0
  },
  "items": [ ... ],
  "traps": [ ... ]
}
```

---

## 新增配置文件流程

1. 在 `data/configs/` 新建 `your_config.json`
2. 顶部加 `"_comment"` 说明用途
3. 通知程序端在对应脚本中读取（`ConfigLoader.load_config("your_config")`）
4. 在本文件补充对应表格说明

---

## 示例：完整规范文件

```json
{
  "_comment": "示例配置，用于说明格式",
  "some_duration": 5,
  "max_players": 4,
  "enable_feature": true,
  "item_ids": ["hat_01", "shirt_01"]
}
```
