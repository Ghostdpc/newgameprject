# 结算评分系统设计文档

> 版本：v1.1 · 2026-08-22
> 依据：`别抢我镜头-完整策划方案.docx`（V1.3）第 8 章「评分与结算」
> 范围：快门帧四维评分算法、掩码渲染管线、绝对分与排名、信号接口
> 状态：五项决议已定稿（见文末），可进入实现

---

## 一、设计目标

快门按下后，纯系统对定格合照评分决出「镜头之王」。评分**基于 PhotoCamera 实际成像（RT）**，而非地面加成或站位坐标——得分来自照片里真实占了多少、在不在 C 位、有没有被挡。

策划原五维（入镜 25% / 站位 25% / 朝向 15% / 遮挡 15% / 服装 20%）在本方案收敛为**四维**，权重可调、默认各 25%，加权和 ×100 得 **0~100 分**：

| 维度 | 默认权重 | 数据来源 |
|------|----------|----------|
| 画面比例 | 25% | 掩码图像素统计 |
| C 位（中心且未被遮挡） | 25% | 掩码图中心加权统计 |
| 服装表现 | 25% | 角色装备数据（不碰像素） |
| 镜头朝向 | 25% | 3D 向量点乘 |

> 原「入镜程度」并入「画面比例」；原「遮挡」并入「C 位」（被挡像素天然不属于该玩家）。权重存 `tune.json`，四权和恒为 1。

---

## 二、核心思路：单张 ID 掩码图

给玩家看的合照 RT 是最终 RGB 图，CPU 读它无法区分「哪块像素是谁」。因此快门帧**额外渲染一张同视角、同分辨率的 ID 掩码图**：

- 每个玩家（角色本体 + 身上所有已穿部件）用一种**纯色 unshaded 材质**填充：P1/P2/P3/P4 各一个可区分的 ID 色，背景纯黑。
- 掩码带正常深度测试：**被挡的像素自然属于挡在前面的玩家**，无需单独算遮挡率。

一张掩码 + 遍历一次像素，同时解出「画面比例」与「C 位」两维。

### 服装是部件，掩码必须连部件一起填色

服装为头/身/手三槽的**独立部件**（非整套）。掩码填色时遍历角色节点树，将**角色本体及其所有已穿部件子节点**统一 override 为该玩家 ID 色。

- 放大金袍等改变判定体积的部件，其增大的投影像素自然计入该玩家 → 画面比例/C 位随之提升。
- 已弹飞/卸下的部件（如皇冠弹飞）不再是角色子节点，不参与填色，正确。

---

## 三、四维算法

设掩码图有效像素总数为 `N_total`（非黑像素，即所有角色占屏像素），玩家 `i` 的像素集合为 `P_i`。

### 3.1 画面比例（25%）

```
raw_ratio[i] = |P_i| / RT像素总数
```

玩家占整张照片的比例。出框、被裁切自然像素少，得分低。

### 3.2 C 位 —— 中心且未被遮挡（25%）

给每个像素一个**中心衰减权重** `w(x, y)`，越靠 RT 中心权重越高：

```
d = distance((x, y), RT中心) / RT半对角线   # 归一到 0~1
w(x, y) = 1 - d          （或高斯 exp(-k·d²)，k 可调）
```

玩家 C 位原始分 = 其像素的中心权重之和：

```
raw_center[i] = Σ_{(x,y) ∈ P_i} w(x, y)
```

- 靠近中心 → 高权像素多 → 高分。
- **被别人挡在中心前** → 中心那块像素颜色是遮挡者的，不计入被挡者 → 被挡者 C 位自动下降。

即「中心」与「没被挡」由同一次加权统计一并解决，无需第二张掩码或射线检测。

### 3.3 服装表现（25%）

不读像素，直接读角色装备数据：

```
raw_outfit[i] = Σ(已装备部件的基础分 + 单件加成) + 主题匹配加成
```

- 装备部件数量、品质、单件表现加成来自服装配置。
- 主题匹配部件按策划给 +5~+8（主题系统联动）。

### 3.4 镜头朝向（25%）

纯 3D 数学，与像素无关。角色**正面朝 +Z**（见 `player_controller.gd:288` 注释，`apply_move` 用 `looking_at` 让 +Z 指向移动方向）：

```
to_cam   = (photo_camera.global_position - player.global_position).normalized()
forward  = player.global_basis.z         # 角色正面 = +Z
dot      = forward.dot(to_cam)           # 范围 -1 ~ 1
raw_face[i] = (dot + 1) / 2              # 归一 0~1，正脸朝镜头=1，背对=0
```

---

## 四、绝对分与总分

**画面比例 / C位 改为玩家间相对归一**；服装 / 朝向保持绝对分。

| 维度 | 分母基准 | 说明 |
|------|----------|------|
| 画面比例 | 所有玩家像素总和 | 占比最大者 = 1；4 人均等时各 0.25 |
| C 位 | 所有玩家中心加权总和 × 质心接近系数 | 相对中心加权最高且质心最靠中者 ≈ 1 |
| 服装 | 配置上限 | 全装备才接近 1 |
| 朝向 | 固定（dot 公式）| 正脸朝镜头 = 1，背对 = 0 |

### C 位算法

```
relative_cw[i]  = center_weights[i] / Σ center_weights[j for j in_photo]
proximity[i]    = 1 - (distance(centroid_i, image_center) / half_diag)    # 0~1
center_norm[i]  = relative_cw[i] * proximity[i]
```

- `centroid` = 玩家像素质心（加权质心），反映玩家在画面中实际站位
- 两指标相乘：「抢到中心加权像素」AND「自身质心靠近中心」双重检验
- 被遮挡时像素少 → `center_weights` 小 → `relative_cw` 低 → 自然惩罚

---

## 五、掩码渲染管线

### 5.1 结构

复用 `PhotoCameraRig` 的相机位姿（位置 / fov / look_target），新增一个 mask 用 SubViewport：

```
PhotoCameraRig
├── PhotoViewport (SubViewport)      # 已有：合照 RT，玩家可见
│   └── PhotoCamera (Camera3D)
├── MaskViewport (SubViewport)       # 新增：ID 掩码，仅评分用，关 MSAA
│   └── MaskCamera (Camera3D)        # 与 PhotoCamera 同步 global_transform / fov / size
```

- `MaskCamera` 快门帧复制 `PhotoCamera` 的 `global_transform`、`fov`、viewport size，保证视角与合照**完全同一帧**。
- 两视口同分辨率（默认 640×360），像素一一对应。
- `MaskViewport.msaa_3d = DISABLED`：纯色 unshaded 无需抗锯齿，也避免边缘混色。

### 5.2 ID 材质与填色 —— 一次性 override（时序分离）

**关键约束**：`MeshInstance3D` 是共享场景节点，被主视口 / 合照视口 / 掩码视口共同观察。`material_override` 改的是 mesh 节点本身，一改**所有视口都变色** → 会污染合照。

**破解**：快门是一次性事件（非每帧）。利用现有快门演出时序，把染色卡在「合照已截 + 白闪盖屏」之间串行完成：

```
快门帧时序（单帧内串行）:
  1. 合照 PhotoViewport.get_image()      # 先把合照存下 ← 保护合照不被污染
  2. 白闪 ColorRect 全屏盖住主画面        # 玩家此刻看不到世界（策划本有「白闪定格」）
  3. 遍历角色本体 + 所有已穿部件 mesh，套 ID material_override
  4. MaskCamera 同步 PhotoCamera 位姿 → 渲一帧 → MaskViewport.get_image()
  5. 清除 override，还原
  6. 出分
```

- 合照在染色**之前**已截好；染色期间主画面被白闪盖住；染完立即还原。全程几毫秒。
- **最省**：无双份 mesh、无常驻双材质、无每帧同步，只快门染一次。
- 一个共享的 4 色 ID 材质数组（unshaded，`albedo = ID_COLOR[i]`）够用，`material_override` 换上换下。

> 不采用「独立 visibility layer 常驻」：同一 mesh 无法同时在两层显示不同材质，需复制 mesh 常驻内存，费，违反「越省越好」。

### 5.3 读回与遍历

```gdscript
var img: Image = mask_viewport.get_texture().get_image()   # 快门帧读一次
# 单次遍历 img 所有像素：
#   查像素颜色 → 最近 ID 色匹配到玩家 i
#   累加 count[i]、center_weight[i]
```

- ID 色查最近色即可，**边缘抗锯齿误判接受**（派对游戏无需像素级公平）。已关 MSAA，误判本就极少。
- 640×360 ≈ 23 万像素，单帧遍历一次，性能无压力。

---

## 六、采样时机

**单帧评分，且与合照 RT 是同一帧。** 掩码渲染锁定合照定格那一刻的相机位姿与角色状态——合照截哪帧，掩码就染哪帧，一一对应。评分对象即玩家看到的那张照片，所见即所得。

不做多帧采样 / 峰值均值。

---

## 七、信号与文件

### 7.1 信号（沿用现有，无需新增）

沿用 `SettlementSystem.settlement_completed(results: Dictionary)`（已存在，level_base 已连接）。payload 内含 `photo`（合照 Image）+ `actors`（逐人四维明细）。UI 端（`scoring_screen`/`results_panel`）已按新四维 key 读取。

results 单项结构（实际字段）：

```gdscript
{
  "player_index": int,
  "color":       Color,
  "in_photo":    bool,
  "visible_px":  int,
  "percent":     float,   # 画面比例绝对分 0~1
  "ratio":       float,   # 同上（别名）
  "center":      float,   # C位 绝对分 0~1
  "outfit":      float,   # 服装 绝对分 0~1
  "facing":      float,   # 朝向 绝对分 0~1
  "dimensions":  { key: {"label","score(0~100)"} },   # UI 逐维刷分用
  "total":       float,   # 加权总分 0~100
  "rank":        int,     # 名次 1~4
}
```

### 7.2 文件规划（已落地）

| 文件 | 新增/修改 | 说明 |
|------|----------|------|
| `scripts/systems/score_analyzer.gd` | 新增 | 四维解算纯算法（输入掩码 Image + 演员元数据，输出 results） |
| `scripts/systems/settlement_system.gd` | 修改 | 掩码克隆渲染 + 调 ScoreAnalyzer；朝向/服装读数 |
| `scripts/player/outfit_manager.gd` | 修改 | 新增 `equipped_slot_count()` / `get_equipped_ids()`，`equip()` 支持 item_id |
| `data/configs/score_config.json` | 新增 | 四维权重、中心衰减、颜色容差、min_visible_px |
| `data/configs/outfit_scoring.json` | 新增 | 每槽基础分 + 单件加成 + 满分上限 |
| `scripts/ui/scoring_screen.gd` | 修改 | DIM_ORDER 改为四维 |
| `tests/test_score_analyzer.gd` | 新增 | 纯算法单测 |
| `tests/test_settlement_system.gd` | 新增 | 结算系统初始化冒烟 |

> 实现采用「掩码克隆到 MASK_LAYER 独立视口」方式（复用现有 PhotoParty 验证过的做法），与 §五 描述的「material_override 染色」等效：都是快门帧一次性生成纯色副本、读回后清理，不污染合照。

### 7.3 可调参数（score_config.json）

| 参数 | 建议初值 | 说明 |
|------|----------|------|
| `weights` | 各 0.25 | 四维权重（ratio/center/outfit/facing），和恒为 1 |
| `center_falloff` | `"linear"` | C 位中心衰减方式（linear / gaussian） |
| `falloff_k` | 4.0 | gaussian 衰减系数 |
| `color_tolerance` | 0.06 | 掩码颜色匹配容差 |
| `min_visible_px` | 20 | 低于此像素判完全出镜 |

---

## 八、算法数据流总览

```
快门帧:
  1. 合照 PhotoViewport.get_image()             # 先存合照，保护不被污染
  2. 白闪盖屏 → 角色本体+部件 mesh 套 ID override
  3. MaskCamera 同步 PhotoCamera 位姿 → 渲 ID 掩码
  4. mask_img = MaskViewport.get_texture().get_image()
  5. 清除 override 还原
  6. 遍历 mask_img 一次:
        每人累加 { 像素数 count, 中心加权和 center_weight }
     → ratio[i]  = count[i] / RT总像素             # 画面比例 绝对分
     → center[i] = center_weight[i] / 满屏中心加权总量  # C位 绝对分
  7. outfit[i] = (读装备槽 + 单件加成 + 主题加成) / 配置上限
  8. face[i]   = ((global_basis.z · to_cam) + 1) / 2
  9. total01[i] = Σ w_dim · dim[i]                 # 权重和=1
     score[i]   = round(total01[i] * 100)          # 0~100
 10. 按 score 降序排名 → EventBus.scoring_completed.emit(results)
```

---

## 九、决议记录（已定稿）

| # | 议题 | 决议 |
|---|------|------|
| 1 | 掩码填色方式 | 一次性 `material_override`，卡「合照已截 + 白闪盖屏」之间染色。不污染合照，最省，无常驻双材质/双 mesh |
| 2 | 抗锯齿边缘 ID 误判 | 不特殊处理。掩码视口关 MSAA，像素查最近 ID 色，少量误判接受 |
| 3 | 归一方式 | **不做玩家间归一**。各维绝对分（0~1），加权和 ×100 得 0~100，无人强制满分 |
| 4 | 采样时机 | 单帧，与合照 RT 同一帧同一位姿。不做多帧 |
| 5 | 角色正面朝向轴 | 正面 = `global_basis.z`（+Z），已由 `player_controller.gd:288` 证实 |
| — | 最终分制 | 0~100 分；四维权重存 `tune.json`，和恒为 1 |
