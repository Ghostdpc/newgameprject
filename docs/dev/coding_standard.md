# GDScript 開發規範

## 命名規範

| 類型 | 規範 | 示例 |
|------|------|------|
| 類名 | `PascalCase` | `CharacterStateMachine` |
| 函數 | `snake_case` | `push_behavior()` |
| 變量 | `snake_case` | `move_speed` |
| 常量 | `UPPER_SNAKE_CASE` | `MAX_PLAYERS` |
| 信號 | `snake_case` 動詞過去式 | `health_changed`, `item_picked_up` |
| 枚舉 | 類名 `PascalCase`，值 `UPPER_SNAKE_CASE` | `enum State { IDLE, MOVING }` |
| 私有成員 | 前綴 `_` | `_current_state`, `_on_body_entered()` |

---

## 文件結構順序

每個 `.gd` 文件按此順序排列：

```gdscript
## 職責：一句話描述此腳本的用途

class_name ClassName
extends ParentClass

# 信號
signal something_happened(param: Type)

# 枚舉
enum State { IDLE, MOVING }

# 常量
const MAX_VALUE: int = 100

# 導出變量（Inspector 可見）
@export var speed: float = 5.0

# 公開變量
var current_state: State

# 私有變量
var _internal_timer: float

# 節點引用（onready）
@onready var _mesh: MeshInstance3D = $Mesh

# 內建虛函數
func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

func _physics_process(delta: float) -> void:
    pass

# 公開方法

# 私有方法（前綴 _）

# 信號回調（前綴 _on_）
func _on_body_entered(body: Node3D) -> void:
    pass
```

---

## 類型聲明
- **所有變量、參數、返回值必須聲明類型**
- 無返回值用 `-> void`
- 未知類型用 `Variant`（盡量避免）

```gdscript
# 好
func calculate_score(viewport: ViewportTexture) -> float:
    pass

# 壞
func calculate_score(viewport):
    pass
```

---

## 信號規範
- 系統間通訊優先用信號（解耦）
- 全局信號定義在 `EventBus`，本地信號定義在各自腳本
- 信號連接優先在 `_ready()` 中用代碼連接，避免場景內隱式連接

```gdscript
# 好 —— 代碼連接，顯式可追蹤
func _ready() -> void:
    EventBus.game_started.connect(_on_game_started)

# 避免 —— 場景編輯器拖拽連接（難以追蹤）
```

---

## 場景 / 節點規範
- 一個場景對應一個主腳本（`class_name` 與場景名一致）
- 子場景用 `@export` 注入或 `$` 引用，不用 `get_node()` 硬編碼路徑
- 物理相關代碼放 `_physics_process()`，純邏輯放 `_process()`

---

## 測試規範（GUT）
- 測試文件放 `tests/`，命名 `test_<模塊名>.gd`
- 繼承 `GutTest`
- 每個測試函數前綴 `test_`
- 每個功能模塊至少覆蓋：正常流程 / 邊界值 / 異常輸入

```gdscript
## 職責：測試 ScoreSystem 打分邏輯

extends GutTest

func test_score_returns_zero_when_no_players_in_zone() -> void:
    var score_system := ScoreSystem.new()
    var result := score_system.calculate_score(null)
    assert_eq(result, 0.0)
```

---

## 禁止項
- 禁止使用 `get_node()` 硬編碼絕對路徑
- 禁止在信號回調裡直接修改其他系統狀態（應發信號，讓對方自己響應）
- 禁止 `print()` 留在提交代碼中（用 `push_warning()` / `push_error()`）
- 禁止無類型的公開 API

---

## 目錄 → 職責對照

| 目錄 | 職責 |
|------|------|
| `scripts/autoload/` | 全局單例 |
| `scripts/player/` | 輸入接收、狀態機驅動 |
| `scripts/character/` | 布娃娃、動畫、換裝 |
| `scripts/camera/` | 相機行為基類與具體實現 |
| `scripts/items/` | 道具框架與具體道具 |
| `scripts/systems/` | 遊戲規則系統（打分/區域/計時） |
| `scripts/ui/` | UI 邏輯 |
| `tests/` | GUT 單元測試 |
