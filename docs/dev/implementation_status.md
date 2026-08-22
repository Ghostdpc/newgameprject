# 程序实现状态与开发记录

> 版本：v1.0 · 更新：2026-08-22
> 记录本轮开发对场景/相机/关卡/UI/结算的改动，供后续开发查阅

---

## 1. 当前流程（S0-S7）

```
S0 标题(main_menu) → S1/S2 加入+确认(lobby) → S3 主题公布(3s)
→ S4 混战(45s, 时间道具可改倍率/加减时) → S5 快门(0.5x慢放+白闪)
→ S6 五维刷分 → S7 冠军结算(重开/返回房间)
```

- 流程由 `GameManager`（autoload）驱动，`GameStage` 枚举见 `scripts/autoload/game_manager.gd`
- 大厅确认人数后进 `scenes/levels/demo_stage.tscn`（`lobby.gd:191`）
- 各阶段时长配置在 `data/configs/game_flow.json`

---

## 2. 关卡框架

### 层级
```
LevelBase (scripts/levels/level_base.gd)   # 玩法骨架，通用
├── DemoStage (demo_stage.gd)              # 完整流程关卡（当前大厅进入）
├── PhotoStage (photo_stage.gd)            # 正式关卡模板
└── PhotoStageTest (photo_stage_test.gd)   # 测试关卡（固定4人+12s加速）
```

### LevelBase 职责
- 相机初始化（MainCamera + 拍照 rig 查找）
- 玩家生成（只实例化 + 赋值 index/color，控制靠 PlayerController 内建）
- 出界重生（`FALL_Y=-5` 判定，`RESPAWN_WAIT=2s`，随机复活点 + 黄色光柱标记）
- 信号连接（battle_started/ended、photo_taken、settlement_completed、flow_finished）
- 快门白闪（`HUD/FlashLayer/ShutterFlash`）
- 结算衔接（`ScoringScreen.setup(player_hud)` + `show_results`）

### 子类扩展点（hook）
```gdscript
_setup_level()               # 舞台布置、道具注册、特殊玩法
_on_level_ready()            # 关卡加载完成（可自动开局）
_on_level_battle_started()   # 混战开始
_on_level_battle_ended()     # 混战结束→快门前
_on_level_decisive_moment()  # 最后3秒
_on_level_photo_taken(tex)   # 收到照片
_on_level_settlement(res)    # 结算结果
get_player_count()           # 玩家数 2-4
get_spawn_points()           # 出生点
```

---

## 3. 可复用拍照相机组件

### PhotoCameraRig（`scenes/camera/photo_camera_rig.tscn` + `scripts/camera/photo_camera_rig.gd`）

策划把 rig 拖进场景即可，无需写代码：

| 操作 | 参数 |
|------|------|
| 相机位置 | rig 节点的 `Position` |
| 拍摄区域中心 | 拖动 `LookTarget` 子节点（相机自动看向它） |
| 视野范围 | `fov`（越小范围越小） |
| RT 尺寸 | `viewport_size` |

### 关键机制
- 相机持续渲染到内部 SubViewport，供 HUD 取景框实时显示 + 快门截图
- **相机模型放 visibility layer 3**，PhotoCamera `cull_mask=1` 排除模型 → 拍照画面无模型（无黑球），主相机能看到模型
- 自动 `add_to_group("photo_camera_rig")` + 注册 `CameraSystem`
- 接口：`get_camera()` / `get_controller()` / `get_render_viewport()`

---

## 4. UI 结构（battle_hud.tscn 三层 CanvasLayer）

| 层 | layer 值 | 内容 |
|----|---------|------|
| `MainLayer` | 1 | 取景框（RT+四角贴花+快门图标+倒计时）、阶段名、飞字浮层 |
| `PlayerLayer` | 100 | 四角玩家面板（高优先级，不被结算界面遮挡） |
| `FlashLayer` | 200 | 快门白闪（最高，覆盖一切） |

- `hud.gd` 挂在 `MainLayer`；`player_hud.gd` 挂在 `PlayerLayer/PlayerHUD`
- ScoringScreen layer=15（低于玩家卡 100，高于取景框 1）
- **倒计时在取景框内底部中央**（模拟真实相机 UI，交互文档写错已按此实现）

### 四角玩家面板（PlayerHUD + PlayerPanel）
- P1左上 / P2右上 / P3左下 / P4右下
- 三重辨识：颜色 + 编号 + 形状（圆/三角/方/菱，`ItemIcons` 图标）
- 服装 3 槽（头/身/手）+ 道具槽（单槽，预留扩展）
- 评分区（S6 逐维刷分）+ 皇冠（S7 冠军）

---

## 5. 玩家配色配置

- 配置：`data/configs/player_colors.json`（`#RRGGBB` 十六进制）
- 读取：`PlayerConfig`（`scripts/game/player_config.gd`，`ConfigTable` 子类，静态单例）
- 使用方（全部统一）：`LevelBase`（3D 角色）、`PlayerHUD`（四角面板）、`lobby`（大厅卡片）、`main_menu`（形状装饰）、`demo_stage`（遮罩匹配色）

改 JSON 后需重新运行游戏（`PlayerConfig._instance` 进程内缓存，不热重载）。

---

## 6. 关键信号接口（EventBus）

```gdscript
# 流程
stage_changed(stage) / stage_timer_updated(seconds) / battle_started() / battle_ended()
# 拍照
photo_taken(viewport_texture)   # null=拍照请求，非null=回传实拍
# 道具
item_picked_up(player_index, item_id) / item_used(player_index, item_id)
item_spawned(item_id, position) / trap_triggered(trap_id, player_index)
# 服装（槽位 0头/1身/2手持）
outfit_changed(player_index, slot, item_id)
# 时间道具（0快进/1慢放/2加时/3减时）
time_effect_applied(effect_type, value)
# 暂停
game_paused_changed(paused)
# 相机
camera_behavior_push_requested(target, behavior) / camera_behavior_pop_requested(...)
```

---

## 7. GameManager 关键接口（流程同事维护，只读）

| 成员 | 说明 |
|------|------|
| `current_stage` / `stage_time_remaining` | 当前阶段/剩余时间 |
| `time_rate` | 倒计时倍率（快进2.0/慢放0.5） |
| `lobby_player_count` | 大厅确认人数（关卡读它生成玩家） |
| `add_time(delta)` | 加时/减时（减时最低1秒），返回实际变化量 |
| `start_game()` / `finish_scoring()` | 开新局 / 结算推进 |
| `enter_lobby()` / `enter_title()` | 返回房间 / 返回标题 |

---

## 8. 本轮关键决策记录

| 决策 | 内容 |
|------|------|
| 拍照相机 | 做成可复用 rig 组件，模型用 layer 隔离避免挡镜头 |
| 相机模型遮挡 | 模型 layer 3 + PhotoCamera cull_mask=1（只渲染场景 layer1） |
| 截图颠倒 | `settlement_system.gd` 删除多余 `flip_y()` |
| 倒计时位置 | 放取景框内底部中央（交互文档写的顶部中央是错的） |
| 玩家卡片层级 | PlayerLayer=100 高于结算 15，只白闪(200)等少数更高 |
| 玩家颜色 | 集中到 `player_colors.json`，消除 5 处硬编码 |
| 假数据 | 移除 `demo_stage.tscn` 的 `DemoUiDriver`（`demo_ui_driver.gd` 保留未删，可复用） |

---

## 9. 待办 / 需与同事对齐

| 事项 | 负责方 | 状态 |
|------|--------|------|
| 真实服装拾取 → `outfit_changed` 信号 | 服装系统同事 | 待接入 |
| 真实道具拾取 → `item_picked_up` | 道具系统（ItemSystem 已有） | 部分接入 |
| 图标资源 `assets/textures/ui/*.svg` | 已齐全 | ✓ |
| 玩家名/头像数据（面板姓名） | 流程/匹配同事 | 待定 |
| 仿相机装饰图（取景框边框精修） | 美术 | 占位中 |
| 暂停/断线 UI | 流程/系统同事 | 待定 |

---

## 10. UI 改版 v1.1（2026-08-22，对照新设计示意图）

### 玩家卡片（PlayerPanel 重写）
- 美术初版 `resources/ui/player.png`（灰阶 atlas）已拆为 8 个零件：
  `assets/textures/ui/card/`：card_bubble / card_body / card_eyes / card_hex / card_p1~p4
  （拆分脚本用边界 flood-fill 抠透明背景，保留封闭白色高光）。
- 染色：`resources/ui/card_tint.gdshader`（保明度 tint：黑描边保持黑、灰阶染玩家色）。
- 合成：泡泡外框(按象限 flip_h/flip_v，尾巴朝屏幕中心) + 小人身体 + 眼睛 +
  P#字标(外上角) + 六边形道具槽(外下角)；卡片尺寸 `CARD_W/H = 240x268`，
  `player_hud.gd:_position_panel` 按四角精确锚定。
- 评分面板（S6）改为半透明小面板叠在头像上；服装槽保持移除状态。

### 相机取景框（新设计：透明标线）
- 删除旧实心取景框（Backing/PhotoRect/FrameBorder/四角贴花/快门图标/Caption）。
- 新 `scripts/ui/focus_reticle.gd`（FocusReticle，`_draw()`）：四角直角括号 +
  中心留缺口对焦圆 + 内侧回声弧 + 十字；取景框居中，`460x340`。
- 拍照 RT 不再常驻 HUD（PhotoCameraRig 仍负责快门截图）。
- `hud.gd`：倒计时/倍率色同步染标线；决胜 3 秒标线一起红脉冲（独立 tween）。
- 倒计时位置保持取景框内底部中央（既有决策不变）。

### 拾取气泡（交互文档 §8，v1.2 补齐）
- `scripts/ui/pickup_bubble.gd`（PickupBubbles），挂在 `battle_hud.tscn` 的 MainLayer。
- 拾取道具/服装时头顶浮现「泡泡+图标」：泡泡沿用卡片视觉（card_bubble + card_tint 染身份色），
  弹入 0.18s → 跟随头顶 → 1.4s 后上浮淡出，总时长 2.5s；连续拾取立即替换。
- 尾巴随角色屏幕左右半自动镜像；镜头外/角色隐藏时不显示。
- 图标映射：服装 id 直查 ItemIcons，道具 id 兜底走 `ItemConfig.get_item_icon`。

### 脚底朝向/位置指示（v1.3 美术升级）
- 旧 ImmediateMesh 线段瓜子环 → 美术贴花：`assets/textures/fx/ground_marker.png`
  （DreamMaker 生成：水滴环+实心核心+前向箭头，白形；已预处理 alpha=亮度）。
- `player_marker.gd`：QuadMesh + StandardMaterial3D（unshaded + ALPHA，**正常深度测试**：
  光圈贴地被角色身体自然遮挡，不渲染到角色之上；albedo_color 染 PlayerConfig 身份色），
  箭头随角色朝 +Z（模型正面）旋转；呼吸脉冲 ±3.5%；
  `player_index` 从父节点 PlayerController 同步（修了全红的旧问题）。
- 尺寸常量 `MARKER_SIZE=2.0`；layer 4 不进合照。

### 结算界面改版（v1.4，对照新设计图）
- `scoring_screen.gd/tscn` 重写：
  - 中央 **-5° 斜置胶片框**：手绘贴图 `assets/textures/ui/film_frame.png`
    （DreamMaker 生成 + 洋红抠透明，波浪手描边 + 上下 11 齿孔），照片按实测窗口比例
    `FILM_HOLE` 垫底外扩 10px 藏边；照片=拍照 RT。
  - 四角头像卡：泡泡/小人/眼睛染玩家色 + P#字标 + **白色漫画字总分**（FontVariation 加粗+黑描边）
    + 每维刷分时头像旁弹 **玩家色 +xx** 上浮淡出 + 总分弹跳累加。
  - 冠军：新版金皇冠（crown_v2）弹入到冠军头像上。
  - 底部六边形双按钮：再来一局(A) / 返回(X)，图标 icon_restart/icon_exit，鼠标可点、
    结算完成后 A/Enter=重开、X/Esc=返回；刷分阶段仍为房主确认键加速。
  - 结算期间隐藏战斗四角卡（PlayerHUD），重开/返回后恢复。
- 新零件（player_v2.png 拆分）：`card/crown_v2.png`、`card/icon_restart.png`、`card/icon_exit.png`；
  `ItemIcons["crown"]` 已指向新款（战斗卡冠军皇冠同步升级）。
- 字标右缘裁切微调：右角卡 P# 外溢 +16 → +4（player_panel / scoring_screen 同步）。
- 分数字体接入：`assets/fonts/Kaph-Regular.otf` / `Kaph-Italic.otf`
  （`FONT_SCORE` 总分+键位、`FONT_SCORE_ITALIC` +xx 弹字），替代 FontVariation 假粗体。

### 音频系统（v1.5）
- autoload `SoundMgr`（`scripts/autoload/sound_manager.gd`）：8 路 SFX 复音池 + 单路 BGM。
- BGM（DreamMaker Suno 纯器乐）：`assets/audio/bgm/title.mp3`（标题/大厅/主题）、
  `battle.mp3`（混战）；SCORING 淡出；battle_started 切战斗曲。
- SFX（程序合成卡通风，`assets/audio/sfx/*.wav` 共 16 个）：
  ui_click/join/confirm/tick/battle_start/pickup/interrupt/item_use/
  time_fast/time_slow/time_add/time_sub/hit/shutter/score_tick/champion。
- 信号驱动：item_picked_up→pickup、item_used→use、trap_triggered→hit、
  time_effect_applied→四类时间音、photo_taken(非null)→shutter、最后3秒→tick。
- 显式挂点：大厅加入/取消/开始、标题确认、结算刷分 score_tick、冠军 champion、
  结算按钮 confirm/ui_click。

### 顺手修复
- `camera_offset_effect.gd:25` 类型推断 Parse Error（`var cam :=` → 显式 `Camera3D`），
  此前导致 camera_remote 道具效果注册失败。

### 流程归属整理
- ScoringScreen 的 `setup/show_results/flow_finished` 统一由 `LevelBase` 接管；
  `demo_stage.gd` 移除重复接线，只保留 `_on_level_settlement` 里 `enter_scoring_mode()`。
- `scoring_screen.gd`：新一轮（stage != SCORING）自动收起并清空评分面板。
