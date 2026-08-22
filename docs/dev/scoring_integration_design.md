# 结算接入关卡流程设计文档

> 版本：v1.0 · 2026-08-22
> 依据：`docs/dev/scoring_system_design.md`（四维评分）+ 策划案第 8 章
> 范围：把四维结算系统接入正式关卡（demo_stage / photo_stage）快门→评分→冠军全流程

---

## 一、现状梳理

结算主链已由 `level_base.gd` 接好，无需重搭：

```
battle_ended (GameManager)
  → level_base._on_battle_ended()
  → EventBus.photo_taken.emit(null)
  → CameraSystem 回传合照 ViewportTexture
  → SettlementSystem._on_photo_taken()   # 克隆掩码 → 渲 ID 掩码 → 四维分析
  → settlement_completed(results)
  → level_base._on_settlement_completed()  # 唯一 UI 入口
      ├─ scoring_screen.setup(player_hud)
      ├─ scoring_screen.show_results(results)
      └─ _on_level_settlement(results)      # 关卡 hook
```

场景节点（`demo_stage.tscn` / `photo_stage.tscn` 均已具备）：

| 节点 | 用途 |
|------|------|
| `PhotoCameraRig` | 合照 RT + 注册到 CameraSystem |
| `SettlementSystem` | 四维结算（脚本 `settlement_system.gd`） |
| `ScoringScreen` | S6 逐维刷分 + S7 冠军 |
| `HUD`（battle_hud） | 倒计时 / 取景框 / `ShutterFlash` / `PlayerLayer/PlayerHUD` |

---

## 二、当前问题

| # | 位置 | 问题 |
|---|------|------|
| 1 | `demo_stage.gd:_on_level_settlement` | 又调一次 `_scoring.show_results(results)`，与 `level_base._on_settlement_completed` 重复 → 照片/刷分演出跑两遍 |
| 2 | `demo_stage.gd:_setup_level` | 手动 `flow_finished.connect` + `setup`，与 `level_base._connect_signals` / `_on_settlement_completed` 重复 → 冠军按钮事件触发两次 |
| 3 | 职责不清 | `show_results` 两个入口，后续加关卡易再次踩坑 |

---

## 三、目标与责任划分

**单一入口原则**：结算 UI 只由 `level_base` 驱动，关卡 hook 只做关卡自身表现。

| 层 | 职责 |
|----|------|
| `level_base` | 连 `settlement_completed`；`setup(player_hud)` + `show_results(results)`；连 `flow_finished` 一次 |
| `SettlementSystem` | 只产出 `results`（四维 + 0~100 总分 + 排名），不碰 UI |
| 关卡（`_on_level_settlement`） | 关卡表现：`hud.enter_scoring_mode()` 等，**不再调 show_results** |
| 关卡（`_on_flow_finished` 覆写） | 重开 / 返回房间差异逻辑（虚拟分派，由 base 的连接触发） |

---

## 四、变更清单

| 文件 | 变更 | 说明 |
|------|------|------|
| `scripts/levels/demo_stage.gd` | 修改 | 删 `_setup_level` 里重复的 `setup`/`connect`；删 `_on_level_settlement` 里的 `show_results`，只留 `hud.enter_scoring_mode()`；清理无用 `_scoring`/`_player_hud` 引用 |
| `scripts/levels/photo_stage.gd` | 可选 | 保持现状（base 全权处理），如后续要结算时隐藏 HUD 再补 hook |
| `tests/test_settlement_integration.gd` | 新增 | 端到端组合测试（见 §六） |

> `level_base.gd` 本身无需改动，已满足单一入口。

---

## 五、信号时序（结算段）

```
SettlementSystem.settlement_completed(results)
  └─ level_base._on_settlement_completed(results)
      ├─ scoring_screen.setup(hud)          # 注入四角 PlayerHUD
      ├─ scoring_screen.show_results(results)  # 照片 + 四维逐刷 + 冠军
      └─ demo_stage._on_level_settlement(results)
          └─ hud.enter_scoring_mode()       # 隐藏顶部栏/取景框

ScoringScreen.flow_finished(action)
  └─ demo_stage._on_flow_finished(action)   # 虚拟分派
      ├─ "restart" → change_scene(demo_stage.tscn)
      └─ "lobby"   → GameManager.enter_lobby()
```

---

## 六、测试计划（test_settlement_integration.gd）

不依赖真实渲染，直接调 `SettlementSystem._analyze(photo, mask, cam)` 验证组合层：

1. **四维齐全**：合成掩码 + mock 演员 → 每个 actor 含 `ratio/center/outfit/facing` 四键。
2. **0~100 总分**：满分场景（全屏红 + 正脸 + 满服装）→ `total == 100`。
3. **排名降序**：中心演员 > 角落演员 → `rank` 1/2 正确。
4. **服装读取**：mock `OutfitManager`（2 槽 + 单件加成）→ outfit > 0 且随装备数增长。
5. **朝向读取**：相机在 +Z，演员 forward +Z → `facing == 1.0`。
6. **完全出镜**：像素不足 → `in_photo == false`，像素维度归零，朝向/服装保留。

测试用内嵌 `MockActor`（Node3D + player_index/player_color）与 `MockOutfit`（equipped_slot_count/get_equipped_ids）类，避免依赖真实 PlayerController / OutfitManager 的 _ready 副作用。

---

## 七、验收标准

- [ ] `demo_stage` 全流程（主题→混战→快门→四维刷分→冠军→重开/回房）不重复演出
- [ ] `settlement_completed` 后 `show_results` 只触发一次
- [ ] 冠军按钮（重开/返回房间）单次触发
- [ ] `test_settlement_integration.gd` 全绿
- [ ] 全量 GUT 测试无回归
