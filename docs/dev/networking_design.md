# 联机多人设计方案（零服务器优先）

> 状态：方案定稿（零服务器优先，传输层留替换接口）
> 日期：2026-08-25
> 关联文档：`architecture.md`（当前仅本地 4 人）、`scoring_system_design.md`、`scoring_mask_fix_design.md`

---

## 0. 决策摘要

| 决策点 | 选择 | 理由 |
|---|---|---|
| 网络拓扑 | ENet listen-server（host 权威） | 2-4 人派对规模，实现最简，无中心服务器 |
| 服务器 | **零自建服务器** | 避免部署与"服务器挂了没法玩"风险 |
| 局域网发现 | UDP 广播 + 自定义房间名 | 零服务器，可读性最高 |
| 跨网连接 | 中文 4 字码（编码 IP:端口）+ UPnP | 零服务器，码即地址，可读可口头传播 |
| 鉴权 | 房间密码（可选） | 码做寻址，密码做防错进 |
| 混合席位 | host 本地多人 + 远端多人自由组合 | 席位所有权模型天然支持 |
| 传输层 | 内置 ENet，接口留替换位 | 后续可换 GodotSteam / NodeTunnel |
| 权威模型 | host 唯一真相源 | ragdoll/物理/结算必须单一权威 |

---

## 1. 现状与可行性

### 现状

- Godot 4.7，Forward Plus，3D。
- 本地 4 人同屏已支持：`GameManager.player_devices: Array[int]` 绑设备，`PlayerInput`（`scripts/player/player_input.gd`）封装键盘 P1/P2 + 手柄 P1-P4。
- 物理驱动：`CharacterBody3D` 玩家 + `RigidBody3D` 物理物 + 主动布娃娃（`PhysicalBoneSimulator3D`）+ 弹簧骨骼。
- 打分：`SettlementSystem` 在本机 GPU 做 mask 渲染 + 像素统计（`scripts/systems/settlement_system.gd`）。
- 零网络代码。

### 可行性结论

- 本地同屏：已支持，仅需扩展设备绑定。
- 联机：可行，但物理非确定性 → 只能**状态同步**，不能锁步。
- 结算：天然适合 host 独占（结算读 host 场景真实渲染位置）。

---

## 2. 网络拓扑

### Host 权威（listen-server）

```
host（peer 1）＝ 权威模拟者 + 玩家
client（peer 2..N）＝ 输入采集 + 表现播放
```

- 全部 4 席的物理/ragdoll/道具/状态机/结算都在 host 跑。
- client 只做两件事：**采集输入 + 播放表现**。
- 与当前本地 4 人一台机模拟等价，host 模拟负担不增加。

### 传输层替换接口

传输层抽象为一个 `NetTransport` 接口，Phase 1 用 ENet 实现。后续换 GodotSteam MultiplayerPeer / NodeTunnel 时，游戏层代码不动。

| 阶段 | 传输层 |
|---|---|
| 一期 | 内置 `ENetMultiplayerPeer` |
| 后续可选 | `SteamMultiplayerPeer`（GodotSteam）/ NodeTunnel |

---

## 3. 零服务器连接方案

### 3.1 局域网发现（一期）

```
host：PacketPeerUDP 周期性广播 {房间名, IP, 端口, 人数/4}
client：监听广播 → 房间列表 → 玩家点选
```

- 房间名自定义，可读性 100%，零服务器。
- 两个 host → 列表两条，按房间名区分。

### 3.2 跨网：中文 4 字码 + UPnP

#### 编码

```
IPv4(32bit) + 端口(16bit) = 48bit
4096 高频字表 = 12bit/字 → 4 字
例：山河月明
```

- 码即地址，自包含，零服务器，可口头传播。
- 输错一字 → 解码出错误地址 → 基本连不上，不会错进别人房间（安全性天然 OK）。

#### 穿透

- host 用 Godot `UPNP` 类自动请求路由器端口映射 + 查公网 IP：

```gdscript
var upnp := UPNP.new()
upnp.discover()
var gateway := upnp.get_gateway()
gateway.add_port_mapping(port, port, "CameraFighter", "UDP")
var public_ip := upnp.query_external_address()
```

#### 连通降级（必须处理，否则用户拿到废码）

编码假设 host 有**可路由的公网 IPv4**，以下情况编出的码跨网必连不上，须在生码前检测并明确提示：

| 情况 | 检测 | 处理 |
|---|---|---|
| UPnP 失败/被路由器关闭 | `discover()` 无网关或 `add_port_mapping` 失败 | 提示"仅局域网可用"，不生成跨网码 |
| CGNAT（运营商级 NAT，无公网 IP） | `query_external_address()` 返回私有/共享段（10./100.64./192.168./172.16-31.） | 同上，或引导后续 relay 方案（§11） |
| IPv6-only / 双栈无 v4 | 无可编码 IPv4 | 一期不支持编码，走局域网或后续 relay |
| 家宽公网 IP 动态 | — | 码有时效（重拨即失效），UI 提示"码仅本次会话有效" |

> 结论：中文码是"有公网 IPv4 且 UPnP 可用"时的可读寻址手段，**不是万能连通方案**。连不通的比例见 §10。

#### 字表设计

| 项 | 做法 |
|---|---|
| 字数 | 4096 高频字（GB2312 一级字库） |
| 排除 | 形近易混字（己/已/巳）、生僻字 |
| 校验 | 4 字无校验；可 2048 字表 × 5 字留 7bit 校验 |
| 多音字 | 影响小，码是随机组合无语义 |

#### 选字 UI（手柄友好）

- 房间码是"从固定字表选 4 字"，不是自由文本 → 用**网格选字**而非输入法。
- `ui/room_code_picker.tscn`：4 槽位 + 拼音分组字表网格。
- 手柄：RB/LB 翻组（26 拼音组）→ 摇杆选字 → A 确认；键盘：方向键 + 回车。
- 键盘/手柄共用同一 UI，零输入法依赖、零平台差异。
- Godot 原生 Control `focus_neighbor_*` 导航，无需插件。

### 3.3 密码鉴权（可选）

- 码负责寻址（找到 host），密码负责鉴权（防错进）。
- 流程：client 连接 → 发密码 → host 校验 → 通过才准入。
- 码撞了（跨网 4 字码基本不撞，但局域网房间名可能重名）→ 密码不同则拒绝。

### 3.4 端口策略

- 端口固定（如 7001），码只需编码 IP（32bit）→ 码从 4 字缩到 3 字（4096 表）或 4 字（1024 表）。
- 建议：固定端口 + 1024 字表 + 4 字码，选字更快（每组 ~40 字，5×8 网格）。

---

## 4. 混合席位（本地 + 远端多人）

### 席位所有权模型

```
seat(0-3) 全局唯一，player_index 不变，颜色按席位
owner ∈ { Local(device_id) | Remote(peer_id) }
```

`GameManager.player_devices: Array[int]` → `player_owners: Array[Dictionary]`：

```
{kind:"local", device:0}   # 本地手柄
{kind:"local", device:-1}  # 本地键盘
{kind:"remote", peer_id:1} # 远端 peer
```

### 自由组合（ 远端 A | 远端 B | 席位表 |
|---|---|---|---|
| 2（键盘+手柄） | 1 | 1 | [L(-1), L(0), R(A), R(B)] |
| 1 | 2 | 1 | [L(-1), R(A), R(A), R(B)] |
| 4 全本地 | — | — | 现有逻辑不变 |
| 1 | 1 | 1 + 1 空 | 空席不生成玩家 |

### 要点

- 远端多席位 = 远端机器复用现有 `PlayerInput` 本地多设备采集，**上行原始输入**，权威模拟仍在 host。
- Local 席位零延迟直读 `Input`，不进网络栈。
- 每个 client 渲染全部 4 席 puppet（共享俯视相机，同屏对战）。
- 相机确定性：机位来自关卡配置（`level_base.gd` 的 `main_cam_pos` 等），各端本地渲染同样画面，无需同步。

### 入口

- 主菜单可两按钮（本地游戏 / 联机游戏），但底层大厅/流程一套。
- 大厅统一入口：`lobby.tscn` 加 mode 参数（local / host / join），席位加入来源扩展为"本地设备 或 远端 peer"。
- 混合模式天然需要同一大厅——分开两套反而做不出混合模式。

---

## 5. 同步频率与通道

| 数据 | 方向 | 频率 | 通道 |
|---|---|---|---|
| 输入意图（按键 level + 移动向量） | client→host | 60Hz（每物理帧） | unreliable，见下"边缘输入修正" |
| 状态快照（pos/vel/state + 时间戳） | host→client | 30Hz（每2物理帧） | unreliable + 插值 |
| 关键事件（击飞/道具/拾取/陷阱） | host→client | 触发时 | reliable |
| 阶段切换/倒计时 | host→client | 变化时 | reliable |
| 席位分配/房间状态 | host↔client | 大厅 | reliable |
| 结算结果 + 照片 PNG | host→client | 回合末 | reliable |

### 带宽验证（不构成瓶颈）

- 上行输入 ≈ 30B × 60Hz ≈ 1.8KB/s/席。
- 下行状态 ≈ 50B/席 × 4 席 × 30Hz ≈ 6KB/s。

### 频率依据

- 输入上行 60Hz：输入采样频率 = 操作响应粒度，越高越跟手，带宽可忽略。
- 状态下行 30Hz：帧间 33ms < 插值窗口 100~150ms，视觉平滑够用，60Hz 收益递减。

### 边缘输入修正（重要，防丢操作）

> 现状：`player_input.gd` 的动作全是**边缘触发**——`is_jump_just_pressed` / `is_dive_just_pressed` / `is_pickup_just_pressed` / `is_use_item_just_pressed`（`player_input.gd:48-84`）只在按下的那一物理帧为 true。

若把边缘信号直接走 "unreliable + 最新覆盖不排队"：该帧的包一旦丢（unreliable 必然偶发丢），host 缓冲会被下一帧的"松开"覆盖 → **这次跳跃/放道具/拾取彻底丢失**，玩家"按了没反应"。这是功能性 bug，不是体感问题。

**修法（采纳）：client 不上行边缘，上行按键 level 状态（当前是否按住 + 移动向量），host 侧 `RemoteInputProvider` 自己算 `just_pressed`（比对上一帧 level）。**

- 移动向量、按住类（`is_pickup_held`）本就是 level 量，丢帧靠下一帧自愈，无损。
- 边缘由 host 从连续 level 推导，只要"按下→松开"两个 level 有一个到达即可判出一次沿；配合 60Hz 上行，单帧丢包不丢动作。
- 备选：边缘走 reliable 单独通道（实现更直白但多一条可靠流，一般不必）。

### 时间戳 / 时钟基准

- 状态快照必须带 **host tick / 时间戳**；client 按固定缓冲窗口（100~150ms）回放插值，而非"收到即显示"。
- 无需全局时钟同步，client 可用"快照到达本地时间 − 缓冲窗口"近似回放时刻；host tick 仅用于排序与去重乱序包。
- 注意：§4"相机确定性无需同步"指的是相机机位，与此处快照插值时序无关，二者不冲突。

---

## 6. 操作同步链路

```
client 席位：PlayerInput 本地采集（移动向量 + 按键 level 状态）
    │  unreliable RPC，60Hz，带序列号，只发"输入 level"（不发边缘）
    ▼
host：RemoteInputProvider 写缓冲（最新覆盖，不排队）
    │  host 比对上一帧 level → 自算 just_pressed 边缘（防丢操作，见 §5）
    ▼
host：4席全部本地权威模拟（physics/ragdoll/道具/状态机）
    │  unreliable 快照，30Hz 广播
    ▼
client：puppet 插值渲染（缓冲 100~150ms 平滑）
```

### 输入抽象

`PlayerInput` 拆 provider：

- `LocalInputProvider(device_id)` — 现有逻辑原封不动（本地直接读边缘，零延迟）。
- `RemoteInputProvider(peer_id, seat_index)` — host 端读"该 peer 最近上行 level"，**自己比对上一帧算边缘**（`just_pressed` 不跨网传，由 host 推导）。

### 延迟现实

- 远端席位 RTT = 输入上行 + host 模拟 + 状态下行 + 插值缓冲。跨网 RTT 40~80ms 时，远端玩家总延迟约 150~230ms。
- 派对格斗类可接受（Gang Beasts 同类）。
- 插值缓冲建议**自适应**：按实测抖动动态调节，低延迟局面缩到 50~80ms，别写死 100~150ms。
- client-side prediction 一期不做（ragdoll 无法干净回滚）。

---

## 7. 结算处理

### 链路

```
host GameManager：battle_ended
    │
    ▼
host SettlementSystem（只在 host 跑）
    ├─ capture_high_res：拍照相机截帧
    ├─ mask viewport 渲染：演员 ID 色 → 像素统计
    ├─ ScoreAnalyzer 四维评分
    └─ settlement_completed(results)
    │
    ▼
host：results 序列化（photo 转 PNG 字节）→ reliable RPC 广播
    │
    ▼
client：收 results → scoring_screen 显示 + 存照片 png
```

### 关键点

1. 结算逻辑只在 host 实例化/执行，client 加 `if not multiplayer.is_server(): return`。
2. 结算输入全部天然 host 权威：`_compute_facing` 读 `global_basis`、`_read_outfit_norm` 读 `GarmentSystem`、`score_penalty` 读 actor——都是 host 侧真实数据，评分逻辑零改动。
3. 照片下发：`results` 里 `photo`/`mask` 转 PNG（640×360 ≈ 几 KB），client `Image.load_png_from_buffer` 复原。**不建议 client 自己截屏**——快门瞬间 client 本地位置是广播插值，与 host 权威图有偏差，"所见非所得"。
4. 快门白闪纯视觉，client 收 `battle_ended` 后本地播放。

---

## 8. ragdoll / 弹簧骨骼策略

### 现状（ragdoll 是击倒核心物理，非纯表现）

- `StunnedState.enter/exit` 开关 ragdoll（`stunned_state.gd:10-19`）。
- `StunnedState.physics_update` 每帧 `sync_body_to_ragdoll()` 回写 body 位置（`stunned_state.gd:32`）。
- `FlyState.launch` 给击飞速度（`fly_state.gd:16-19`）。
- `RagdollRig` 的 impulse/drive 是 gameplay 驱动物理。

### 权威决策

**ragdoll 权威 = host**，与现在本地 4 人一样（host 一台机模拟 4 人 ragdoll）。理由：

1. ragdoll 回写 body 位置 → 各端独立模拟则权威分歧 → 持续瞬移。
2. `PhysicalBoneSimulator3D` 非确定性，跨机结果必不一致。
3. 打分"所见即所得"——host 结算读 host 场景真实位置，client 自己模拟的位置与 host 不一致 → "明明在镜头里却没分"。
4. 碰撞互推 desync、击倒事件需 host 确认，本地预测 ragdoll 无法回滚。

### 改造点

| 位置 | 改动 |
|---|---|
| `player_controller.gd:150` `set_ragdoll()` | 加权威判断：host 全跑；client puppet 不启动 `PhysicalBoneSimulator3D` |
| `stunned_state.gd:14/19` | `set_ragdoll(true/false)` 仅 host 生效 |
| `player_controller.gd:171` `sync_body_to_ragdoll()` | 仅 host 写 body；client puppet 位置来自广播插值 |
| `fly_state.gd:16` `launch()` | 击飞变事件：host 权威广播 `{player_index, direction}` |
| `ragdoll_rig.gd` impulse/drive | 全部 host 权威，client 收事件播 canned 动画 |
| 弹簧骨骼 | 同 ragdoll：host 权威，client 不跑或只跑视觉 |

### 远端表现方案（二选一，推荐一）

1. **canned 动画**（推荐一期）：Fly→击飞动画、Stunned→倒地动画、香蕉→滑行动画。不做远端 ragdoll 物理，无瞬移，跨机一致。
2. **本地 ragdoll 只演不写**：client 跑 ragdoll 但不接权威、不回写 body，每帧软修正到 host 位置。视觉丰富但成本高、仍有轻微抖动。

---

## 9. 分阶段实施计划

| 阶段 | 内容 | 风险 |
|---|---|---|
| P1 | `NetManager` autoload + 传输抽象 + 大厅房间（LAN 广播 / 中文码 + UPnP / 密码鉴权）+ 席位分配 | 低 |
| P2 | `PlayerInput` 拆 Local/Remote provider，输入上行 60Hz | 低 |
| P3 | 状态同步：host 权威模拟 + puppet 插值 + ragdoll 策略（§8） | **高** |
| P4 | 事件网络化：EventBus → 可靠 RPC（道具/服装/相机行为/击飞） | 中 |
| P5 | 结算 host 独占 + 照片 PNG 下发（§7） | 中 |
| P6 | 混合席位收尾（本地多设备 + 远端多席 + 断线处理） | 中 |

### 里程碑建议

- **P1+P2 先落地**：地基，零 gameplay 风险，局域网可玩（LAN 广播 + IP 直连验证整套架构）。
- **中文 4 字码后置**：4096 字表维护 + 拼音选字 UI 是不小的活，本质是给"分享一串地址"套皮。P1 先用 **IP:端口直连 + 局域网广播** 跑通全链路，中文码降到 P1 之后（可与 relay 兜底一并做），别让地基背一个字表。
- **P3 单独攻坚**：最大工作量与风险点（ragdoll/物理同步）。
- **P5 反而改动最小**：结算本来就读 host 真实场景。

---

## 10. 风险与待定

| 风险 | 说明 | 应对 |
|---|---|---|
| 跨网连不通（NAT/CGNAT/UPnP） | 不止对称 NAT：**CGNAT**（运营商无公网 IPv4）下 UPnP 映射的是运营商内网口，外面进不来，`query_external_address` 甚至返回私有地址；叠加 UPnP 被关、IPv6-only，实际连不上比例按地区可达 **30~40%**（远高于早期估计的 10-15%） | 一期：生码前检测并明确降级（§3.2），连不通就退局域网；后续换 GodotSteam/NodeTunnel 的 relay 兜底 |
| 远端手感延迟 | RTT 全链路，远端玩家比本地慢半拍 | 一期接受；后续 client-side prediction |
| ragdoll 跨机观感 | 远端 canned 动画 vs host 真实 ragdoll 差异 | 调参 + 二期评估"只演不写" |
| 断线 | 远端掉线 → 席位转 AI/移除；host 掉线 → host migration | 一期：远端掉线移除席位；host migration 不做 |
| 中文字表 | 4096 字表维护 + 选字 UX | 拼音分组 + 固定端口缩码长 |

### 待定项

- 固定端口 vs 编码端口（影响码长 3/4 字）。
- 密码是否必填（码 + 密码双层 vs 仅码）。
- 断线后席位处理细则（转 AI / 移除 / 等待重连）。

---

## 11. 后续可选：传输层替换

保持 §2 的 `NetTransport` 抽象，零服务器方案跑通后可平滑切换：

| 方案 | 代价 | 收益 |
|---|---|---|
| GodotSteam MultiplayerPeer | 绑 Steam 平台 | Valve 免费 relay，跨网 100% 连通 |
| NodeTunnel | 依赖公共 relay 节点 | 不绑平台，drop-in ENet |
| 内置 WebRTC + STUN | 信令自理，连通率非 100% | 真零服务器 |
