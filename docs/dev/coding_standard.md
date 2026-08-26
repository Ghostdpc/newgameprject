# GDScript 开发规范

## 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 类名 | `PascalCase` | `CharacterStateMachine` |
| 函数 | `snake_case` | `push_behavior()` |
| 变量 | `snake_case` | `move_speed` |
| 常量 | `UPPER_SNAKE_CASE` | `MAX_PLAYERS` |
| 信号 | `snake_case` 动词过去式 | `health_changed`, `item_picked_up` |
| 枚举 | 类名 `PascalCase`，值 `UPPER_SNAKE_CASE` | `enum State { IDLE, MOVING }` |
| 私有成员 | 前缀 `_` | `_current_state`, `_on_body_entered()` |

---

## 文件结构顺序

每个 `.gd` 文件按此顺序排列：

```gdscript
## 职责：一句话描述此脚本的用途

class_name ClassName
extends ParentClass

# 信号
signal something_happened(param: Type)

# 枚举
enum State { IDLE, MOVING }

# 常量
const MAX_VALUE: int = 100

# 导出变量（Inspector 可见）
@export var speed: float = 5.0

# 公开变量
var current_state: State

# 私有变量
var _internal_timer: float

# 节点引用（onready）
@onready var _mesh: MeshInstance3D = $Mesh

# 内建虚函数
func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

func _physics_process(delta: float) -> void:
    pass

# 公开方法

# 私有方法（前缀 _）

# 信号回调（前缀 _on_）
func _on_body_entered(body: Node3D) -> void:
    pass
```

---

## 类型声明
- **所有变量、参数、返回值必须声明类型**
- 无返回值用 `-> void`
- 未知类型用 `Variant`（尽量避免）

```gdscript
# 好
func calculate_score(viewport: ViewportTexture) -> float:
    pass

# 坏
func calculate_score(viewport):
    pass
```

---

## 信号规范
- 系统间通讯优先用信号（解耦）
- 全局信号定义在 `EventBus`，本地信号定义在各自脚本
- 信号连接优先在 `_ready()` 中用代码连接，避免场景内隐式连接

```gdscript
# 好 —— 代码连接，显式可追踪
func _ready() -> void:
    EventBus.game_started.connect(_on_game_started)

# 避免 —— 场景编辑器拖拽连接（难以追踪）
```

---

## 场景 / 节点规范
- 一个场景对应一个主脚本（`class_name` 与场景名一致）
- 子场景用 `@export` 注入或 `$` 引用，不用 `get_node()` 硬编码路径
- 物理相关代码放 `_physics_process()`，纯逻辑放 `_process()`

---

## 测试规范（GUT）
- 测试文件放 `tests/`，命名 `test_<模块名>.gd`
- 继承 `GutTest`
- 每个测试函数前缀 `test_`
- 每个功能模块至少覆盖：正常流程 / 边界值 / 异常输入
- **实现完毕后必须先自行跑一遍测试（`godot --headless -s addons/gut/gut_cmdln.gd`），确认全绿再提交**

```gdscript
## 职责：测试 ScoreSystem 打分逻辑

extends GutTest

func test_score_returns_zero_when_no_players_in_zone() -> void:
    var score_system := ScoreSystem.new()
    var result := score_system.calculate_score(null)
    assert_eq(result, 0.0)
```

---

## 禁止项
- 禁止使用 `get_node()` 硬编码绝对路径
- 禁止在信号回调里直接修改其他系统状态（应发信号，让对方自己响应）
- 禁止 `print()` 留在提交代码中（用 `push_warning()` / `push_error()`）
- 禁止无类型的公开 API

---

## 目录 → 职责对照

| 目录 | 职责 |
|------|------|
| `scripts/autoload/` | 全局单例 |
| `scripts/player/` | 输入接收、状态机驱动 |
| `scripts/character/` | 布娃娃、动画、换装 |
| `scripts/camera/` | 相机行为基类与具体实现 |
| `scripts/items/` | 道具框架与具体道具 |
| `scripts/systems/` | 游戏规则系统（打分/区域/计时） |
| `scripts/ui/` | UI 逻辑 |
| `tests/` | GUT 单元测试 |
