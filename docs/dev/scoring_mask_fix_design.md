# 结算遮罩渲染问题修正设计文档

> 版本：v1.0 · 2026-08-22
> 依据：`scoring_system_design.md`（四维评分）
> 范围：修正两个遮罩渲染问题：T-pose 克隆 + 遮挡物无效

---

## 一、问题清单

### 问题 A：克隆 mesh 是 T-pose

**根因**：`_clone_meshes` 仅复制 `MeshInstance3D.global_transform`，而蒙皮 mesh 的骨骼形变由 `Skeleton3D` 实时驱动（存于 GPU），CPU 侧的 `Mesh` 资源是 bind-pose，直接克隆得到的是 T-pose。

### 问题 B：场景遮挡物未参与遮挡

**根因一**：掩码视口使用**独立 `world_3d`**，主场景的任何物体（墙壁、地板、道具台）都不在其中，掩码相机看到的只有被克隆进去的演员副本，遮挡为零。

**根因二**：即使克隆遮挡物为黑色，黑色与背景（也是黑色）无法区分，无法实现深度遮挡——纯色 unshaded 材质在独立黑色世界里，深度测试靠各克隆体的 z 值，颜色是什么不影响遮挡关系；但若未克隆遮挡物则相机直接"穿透"。

---

## 二、方案选型：Visibility Layer Override

放弃「独立 world_3d + 克隆 mesh」做法，改用**主世界 visibility layer**：

- 演员（角色本体 + 已穿部件）平时只渲染在 layer 1（正常可见）。
- 快门帧额外给每个演员分配一个 **layer 2 副本**，搭配 **unshaded ID 材质**。
- `MaskCamera` 设 `cull_mask = layer 2`，渲染一帧 → 得 ID 掩码。
- `MaskCamera` 放在**主场景（不用独立 world_3d）**，主场景所有 layer 1 物体（墙壁/地板/道具台）对 layer 2 的相机**不可见**，但演员在 layer 2 的副本材质可见，且演员被场景物体遮挡的部分天然被深度剔除。

关键：`MaskCamera.cull_mask` 只开 layer 2 → 只看演员 ID 色，场景几何自动遮挡（靠 GPU 深度缓冲），无需克隆任何场景物体。

### 为什么场景物体能遮挡 layer 2 的演员？

Godot 的遮挡是 **z-buffer**，不是按 visibility layer 分桶——`cull_mask = layer 2` 只决定哪些物体被画到颜色缓冲，但场景里 layer 1 物体的深度依然写入深度缓冲，layer 2 的演员副本在光栅化时会与这些深度值比较，被挡的片段被丢弃。

> **注意**：Godot 4 `SubViewport` 中 `world_3d` 若设为独立 world，则场景物体的深度不参与该视口的深度测试。因此改为**共享主场景 world_3d**（不赋值 = 自动继承）。

### 实现步骤

```
快门帧（串行，几毫秒）:
  1. 合照 RT 已由 CameraSystem.photo_taken 传回 → 存为 photo_image
  2. 遍历每个 settlement_actor：
       a. 遍历 actor 及其部件的所有 MeshInstance3D
       b. 给每个 mesh 追加 layer 2（layers |= MASK_LAYER_BIT）
       c. 设 material_override 为该玩家 unshaded ID 材质
  3. MaskCamera 同步 PhotoCamera 位姿，set UPDATE_ONCE
  4. await 2 帧 → mask_image = MaskViewport.get_texture().get_image()
  5. 遍历 actor mesh 取消 layer 2，清除 material_override（或还原原材质）
  6. 出分
```

---

## 三、MaskViewport 结构变化

旧：独立 world_3d + 克隆 Node3D 树

新：
```
SettlementSystem
└── MaskViewport (SubViewport)
    │  world_3d = null (继承主场景，关键！)
    │  msaa_3d = DISABLED
    │  render_target_update_mode = UPDATE_DISABLED (默认)
    └── MaskCamera (Camera3D)
           cull_mask = MASK_LAYER_BIT (只显示 layer 2)
           # 位姿每次快门帧同步 PhotoCamera
```

不再需要 `_clones_root` / `_spawn_mask_clones` / `_clear_mask_clones`。

---

## 四、演员 mesh override 细节

### 4.1 ID 颜色表

4 名玩家使用高可分 ID 色（接近但不等于 PlayerConfig 玩家色，避免与正式颜色混淆；纯饱和原色最易区分）：

| 玩家 | ID 色 |
|------|-------|
| P1 | `Color(1, 0, 0)` 纯红 |
| P2 | `Color(0, 1, 0)` 纯绿 |
| P3 | `Color(0, 0, 1)` 纯蓝 |
| P4 | `Color(1, 1, 0)` 纯黄 |

存入 `score_config.json["id_colors"]`，可调。

### 4.2 override 流程

```gdscript
# 染色
func _apply_id_override(actor: Node3D, mat: StandardMaterial3D) -> Array:
    var affected: Array[MeshInstance3D] = []
    for mi in _collect_meshes(actor):
        mi.layers |= MASK_LAYER_BIT            # 追加 layer 2，保留原 layer 1
        mi.material_override = mat
        affected.append(mi)
    return affected

# 还原
func _revert_id_override(affected: Array) -> void:
    for mi in affected:
        mi.layers &= ~MASK_LAYER_BIT           # 移除 layer 2
        mi.material_override = null
```

注意：`OutfitManager._recolor` 也使用 `material_override`，因此还原时清 `null` 会暴露底层材质。
解决方案：染色前记录 `mi.material_override`（原 override），还原时写回原值，而不是写 null。

---

## 五、变更清单

| 文件 | 变更 |
|------|------|
| `scripts/systems/settlement_system.gd` | 重写 `_build_mask_viewport`（去掉独立 world，改共享）；删 `_spawn_mask_clones/_clear_mask_clones/_clone_meshes`；新增 `_apply_id_override/_revert_id_override`；`_analyze_async` 改用 override 流程 |
| `data/configs/score_config.json` | 新增 `id_colors` 数组（4 个 RGBA 纯色） |
| `tests/test_settlement_integration.gd` | 补充 override 环境模拟（MockActor 有 MeshInstance3D 子节点） |

---

## 六、遮挡验证

由于场景几何在主世界，深度自动生效。可在调试面板（`scoring_screen` 右侧 mask panel）直观验证：
- 被墙壁/地板遮挡的演员部分应显示黑色（无 ID 色）。
- 被其他演员挡住的部分应显示遮挡者的 ID 色。
