# 道具特效交接

## 已导入参考资产

设计文档中的 7 张参考图已导入：

- `res://assets/textures/fx/reference/energy_drink_reference.png`
- `res://assets/textures/fx/reference/banana_peel_reference.png`
- `res://assets/textures/fx/reference/fast_forward_reference.png`
- `res://assets/textures/fx/reference/slow_hourglass_reference.png`
- `res://assets/textures/fx/reference/time_battery_reference.png`
- `res://assets/textures/fx/reference/time_scissors_reference.png`
- `res://assets/textures/fx/reference/camera_remote_reference.png`

这些是用于美术对照的源图片，不会在运行时直接显示。

## 运行时资源

| 效果 | 场景 | 脚本 | 显示位置 |
| --- | --- | --- | --- |
| 脚底能量圈 | `res://scenes/fx/world_item_vfx.tscn` | `res://scripts/vfx/world_item_vfx.gd` | 角色脚底，跟随角色 |
| 香蕉眩晕星 | `res://scenes/fx/world_item_vfx.tscn` | `res://scripts/vfx/world_item_vfx.gd` | 角色头顶环绕 |
| 屏幕边缘框 | `res://scenes/fx/fullscreen_item_post.tscn` | `res://scripts/vfx/fullscreen_item_post.gd` | CanvasLayer 50 |
| 边缘框形状 | 运行时生成 | `res://scripts/vfx/screen_edge_mask.gd` | `UIMask/EdgeMask` |
| 左右向内粒子流 | 运行时生成 | `res://scripts/vfx/edge_particle_stream.gd` | `UIMask/EdgeParticleStream` |
| 快进/慢放方向提示 | 运行时生成 | `res://scripts/vfx/time_direction_badge.gd` | `UIMask/TimeDirectionBadge` |
| 道具事件接线 | `res://scenes/fx/prop_vfx_layer.tscn` | `res://scripts/vfx/prop_vfx_layer.gd` | 项目 Autoload：`PropVfx` |

## 道具映射

- 能量饮料：橙黄色脚底能量圈，持续 3 秒。
- 香蕉皮放置：黄色脚底警示圈；踩中后显示头顶环绕眩晕星。
- 快进发条：橙色脚底圈 + 橙色边缘框 + 顶部 `>> 2.0x` + 左右向内高速粒子流。
- 慢放沙漏：蓝色脚底圈 + 蓝色边缘框 + 顶部 `<< 0.5x` + 左右向内缓速粒子流。
- 加时电池：绿色脚底圈 + 绿色边缘脉冲。
- 减时剪刀：红色脚底圈 + 红色边缘警告抖动。
- 相机遥控器：金色脚底圈 + 金色取景感边缘框。

## 如何查看

### 独立预览

1. 在 Godot 的 FileSystem 双击 `res://scenes/tech_demos/prop_vfx_demo.tscn`。
2. 按 `F6` 运行当前场景。
3. 特效会自动轮播；`Left` / `Right` 切换条目，`Space` 重播当前条目。

### 在正式对局查看

1. 打开 `res://scenes/levels/room_battle.tscn`。
2. 按 `F6` 运行。
3. 拾取并使用相应道具；`PropVfx` autoload 会监听 `EventBus.item_used` 和 `EventBus.trap_triggered` 并自动生成对应特效。

### 在 Remote 场景树调参

运行对局或预览后，在 Godot 的 Remote 标签查看：

- `/root/PropVfx/FullscreenItemPost/UIMask`
- `/root/PropVfx/FullscreenItemPost/UIMask/EdgeMask`
- `/root/PropVfx/FullscreenItemPost/UIMask/EdgeParticleStream`
- `/root/PropVfx/FullscreenItemPost/UIMask/TimeDirectionBadge`
- 当前场景根节点下动态生成的 `WorldItemVfx`

可直接在对应 GDScript 中调整边缘颜色、粒子数量/速度、方向徽标文字，以及脚底圈和星星的尺寸、持续时间。
