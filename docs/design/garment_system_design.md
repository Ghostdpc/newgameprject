# 服装系统设计文档 v1.0

> 编制日期：2026-08-22
> 范围：服装在场景刷新 + 长按拾取装备 + 效果触发 + 落地动画 + 评分接入

---

## 一、系统目标

| 目标 | 说明 |
|------|------|
| 服装可刷新 | 战斗开始时散布在热点，与道具共用 ItemSpawner 预算 |
| 长按装备 | 同道具拾取：长按 0.8s，可被打断；同槽顶替旧装备 |
| 不重复刷新 | 同一 id 的服装全场同时最多存在 1 件（未被拾取 = 不重刷） |
| 从天而降 | 服装落地时有下落动画（高处落下 → 弹跳落定），增加视觉爆炸感 |
| 效果生效 | 装备后立即触发对应效果（移速/身形/弹簧等），卸下时还原 |
| 评分接入 | 快门帧将已装备件数 + 单件加成折算为 outfit 绝对分（0~1）传给 ScoreAnalyzer |

---

## 二、数据结构

### 2.1 garments.json（新增，独立于 items.json）

```jsonc
{
  "garments": [
    {
      "id": "mushroom_hat",
      "display_name": "🍄 蘑菇帽",
      "icon": "mushroom_hat",
      "slot": "hat_slot",          // hat_slot / shirt_slot / accessory_slot
      "model": "",                  // 模型路径，空=占位方块
      "model_scale": 1.0,
      "score_bonus": 0.08,          // 单件对 outfit 分的最大贡献（0~1 加权后 ÷ 总件数）
      "effects": [
        {
          "kind": "head_scale",     // 服装专属 EffectKind
          "target": "self",
          "params": { "scale": 1.8 }
        }
      ]
    },
    {
      "id": "lightning_shirt",
      "display_name": "⚡ 闪电T恤",
      "icon": "lightning_shirt",
      "slot": "shirt_slot",
      "model": "",
      "score_bonus": 0.08,
      "effects": [
        {
          "kind": "player_speed",
          "target": "self",
          "params": { "multiplier": 1.5 }
        }
      ]
    },
    {
      "id": "snail_hoodie",
      "display_name": "🐌 蜗牛连帽衫",
      "icon": "snail_hoodie",
      "slot": "shirt_slot",
      "model": "",
      "score_bonus": 0.06,
      "effects": [
        {
          "kind": "player_speed",
          "target": "self",
          "params": { "multiplier": 0.6 }
        }
      ]
    },
    {
      "id": "inflate_shirt",
      "display_name": "🎈 充气球衣",
      "icon": "inflate_shirt",
      "slot": "shirt_slot",
      "model": "",
      "score_bonus": 0.10,
      "effects": [
        {
          "kind": "body_scale",
          "target": "self",
          "params": { "scale": 1.5, "width": 1.5 }
        }
      ]
    },
    {
      "id": "halo",
      "display_name": "✨ 光环",
      "icon": "halo",
      "slot": "hat_slot",
      "model": "",
      "score_bonus": 0.12,
      "effects": [
        {
          "kind": "emission_glow",
          "target": "self",
          "params": { "strength": 0.6 }
        }
      ]
    },
    {
      "id": "guitar",
      "display_name": "🎸 吉他",
      "icon": "guitar",
      "slot": "accessory_slot",
      "model": "",
      "score_bonus": 0.08,
      "effects": [
        {
          "kind": "spring_wobble",
          "target": "self",
          "params": { "scale": 2.5 }
        }
      ]
    }
  ]
}
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | 唯一标识，不重复刷新的判断键 |
| `slot` | String | 对应 OutfitManager 三槽之一 |
| `score_bonus` | float | 快门帧该件加成上限（0~1 权重后入 outfit 维度） |
| `effects` | Array | 穿上生效，卸下还原；复用 ItemEffect 框架 |

### 2.2 新增 GarmentDef（类比 ItemDef）

```
GarmentDef extends RefCounted
  id: String
  display_name: String
  icon: String
  slot: String
  model: String
  model_scale: float
  score_bonus: float
  effects: Array[ItemEffect]
```

### 2.3 GarmentConfig（类比 ItemConfig）

读 `garments.json`，提供：
- `all_ids()` → `Array[String]`
- `get_garment(id)` → `GarmentDef`
- `get_spawn_count()` → int（初始刷新件数，默认 = garments 总件数）

---

## 三、服装刷新机制

### 3.1 GarmentSpawner（新脚本）

- 监听 `battle_started` / `battle_ended`
- 开局将所有服装 id 各刷新一件（一件 = 一个 `GarmentPickup` 节点）
- **不重复刷新**：以 `_spawned_ids: Dictionary[String, bool]` 记录已在场的 id，`GarmentPickup` 被拾取时通知 spawner 移除该 id，允许后续刷同一 id
- 与道具箱共用 `item_hotspot` 组热点（先到先得，不单独划分）
- 服装刷新独立于道具箱预算（不占 ItemSpawner 的 max_active）

### 3.2 GarmentPickup（新脚本，类比 ItemBox）

- `extends Area3D` + `add_to_group("pickup_items")`（复用 PlayerController 长按拾取流程）
- `pickup_for(player) -> String`：返回 `garment_id`，自身 `queue_free()`，通知 GarmentSpawner
- 落地动画：生成时在热点上方 3.5m 处，`Tween` 做下落（ease_in） + 落地弹跳（0.2s 向上 0.3m → ease_out 落定），总时长约 0.6s

### 3.3 PlayerController 对 garment 的处理

`_pickup_item_id()` 目前对所有 `pickup_items` 成员调用 `pickup_for()`。
返回 id 后，需在 `pickup_item()` 中区分道具与服装：

```gdscript
# 伪代码
func _pickup_result(id: String, source_node: Node) -> void:
    if GarmentSystem.is_garment(id):
        GarmentSystem.equip_garment(self, id)
    else:
        pickup_item(id)   # 原道具流程不变
```

> **注意**：`_pickup_item_id()` 目前同时处理 ItemBox 和 GarmentPickup，
> 拾取接口保持 `pickup_for(player) -> String` 统一，区分逻辑在 `PlayerController` 侧。

---

## 四、服装装备与效果机制

### 4.1 GarmentSystem（新 autoload 或挂在 GameManager 下）

负责：
1. 加载 `GarmentConfig`
2. `equip_garment(player, garment_id)` — 调 OutfitManager 装备模型 + 应用 effects
3. `unequip_garment(player, slot)` — 卸下旧件时 revert effects + OutfitManager 卸载
4. `get_equipped_score(player)` — 读玩家已装备件数与 score_bonus，折算 outfit 绝对分

### 4.2 效果触发（on_wear / on_remove）

服装效果不像道具有"使用时机"，触发时机固定：
- **穿上（on_wear）**：`equip_garment` 调用后立即 `effect.apply(ctx)`，**duration = 0**（永久持续，不进 `_active_effects` 计时队列）
- **脱下（on_remove）**：替换同槽或战斗结束时调用 `effect.revert(ctx)`

需新增的服装专属效果（ItemEffect 子类）：

| kind | 脚本 | 行为 |
|------|------|------|
| `head_scale` | `garment_head_scale_effect.gd` | 写 `player.head_scale` |
| `body_scale` | `garment_body_scale_effect.gd` | 写 `player.body_scale` + `body_width` |
| `spring_wobble` | `garment_spring_wobble_effect.gd` | 调 `player.spring_rig.apply_preset("kowtow")` |
| `emission_glow` | `garment_emission_glow_effect.gd` | 对角色所有 MeshInstance3D 开启自发光（保留 revert） |

> `player_speed` 已有，直接复用（duration=0 = 永久，revert 还原 multiplier=1.0）

### 4.3 PlayerController 存储服装数据

`PlayerController` 新增：
```gdscript
## 当前装备的服装 id（槽位名 -> garment_id）
var equipped_garments: Dictionary = {}
```

`GarmentSystem.equip_garment` 写入，`unequip_garment` 清除；结算时 `ScoreAnalyzer` 读此字段。

---

## 五、评分接入

### 5.1 outfit 绝对分计算

`GarmentSystem.get_equipped_score(player) -> float`（0~1）：

```
score = Σ garment.score_bonus for each equipped garment
score = clamp(score, 0.0, 1.0)
```

简单线性叠加，上限 1.0。若所有 score_bonus 之和 ≥ 1.0，满装备即满分。

### 5.2 与现有 ScoreAnalyzer 接入

`LevelBase._build_actor_meta(player)` 中 `outfit` 字段改为：
```gdscript
"outfit": GarmentSystem.get_equipped_score(player)
```

（目前该字段为占位 0.0，改为实读）

---

## 六、落地动画规格

| 参数 | 值 |
|------|-----|
| 生成高度 | 热点 y + 3.5m |
| 下落时长 | 0.45s（ease_in，先慢后快） |
| 弹跳高度 | 0.3m（ease_out，迅速向上再落地 0.15s） |
| 落定后 | 旋转 y 轴 1.5 rad/s 持续转动（同 ItemBox） |
| 碰撞 | 下落期间关闭 Area3D 监听（防误拾取），落定后开启 |

---

## 七、HUD 接入

- `EventBus.outfit_changed(player_index, slot_int, garment_id)` 已有信号，`GarmentSystem.equip_garment` 负责 emit
- 槽位整数映射：`hat_slot=0` / `shirt_slot=1` / `accessory_slot=2`
- `PlayerPanel` 监听此信号更新图标槽（已有 slot 0~2 预留位，直接用）
- 拾取气泡：`PickupBubbles` 监听同信号，走服装 id 直查 `ItemIcons` 图标

---

## 八、实现步骤（推荐顺序）

| 步骤 | 内容 | 依赖 |
|------|------|------|
| S1 | 新增 `garments.json`，录入 6 件服装数据 | 无 |
| S2 | `GarmentDef` + `GarmentConfig`（类比 ItemDef/ItemConfig） | S1 |
| S3 | `GarmentPickup`（Area3D + 落地 Tween + pickup_for） | S2 |
| S4 | `GarmentSpawner`（监听 battle_started，一件一件刷，不重复） | S3 |
| S5 | `PlayerController`：`_pickup_result` 分流道具 vs 服装 | S3 |
| S6 | 服装专属 ItemEffect 子类（head_scale / body_scale / spring_wobble / emission_glow） | 无 |
| S7 | `GarmentSystem` autoload（equip/unequip/get_equipped_score，持久化到 equipped_garments） | S5 S6 |
| S8 | 评分接入：`LevelBase._build_actor_meta` outfit 字段改读 GarmentSystem | S7 |
| S9 | HUD：`outfit_changed` 信号接入 PlayerPanel + PickupBubbles | S7 |
| S10 | 联调验证：四人同场抢装，评分 outfit 维度有分差 | 全部 |

---

## 九、关键约束与边界

| 约束 | 说明 |
|------|------|
| 服装不消耗 | 穿戴后永久生效，不像道具被"用掉" |
| 同槽替换 | 新装备直接顶旧，旧效果先 revert 再 apply 新的 |
| 不可剥夺 | 已穿戴服装不能被其他玩家直接抢走（场上的 GarmentPickup 可抢） |
| 不重复在场 | 同 id 只能有 1 个 GarmentPickup 在场，被拾取后 spawner 可重刷（本期不重刷，战斗内不补充） |
| 永久效果不进计时 | duration=0 的效果不进 `ItemSystem._active_effects`，由 GarmentSystem 手动 revert |
| 战斗结束清空 | `battle_ended` 时 GarmentSystem 对所有玩家调用 unequip_all，还原所有效果 |
