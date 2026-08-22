# JSON 配置數據規範

> 本文件面向策劃，說明如何填寫和新增 JSON 配置文件。

---

## 目錄位置

所有配置文件放在：
```
data/configs/
└── *.json
```

---

## 文件命名規範

- 全小寫 `snake_case`，例如：`game_flow.json`、`items.json`
- 名稱對應配置功能類別，不要縮寫

---

## JSON 格式規則

| 規則 | 說明 |
|------|------|
| 編碼 | UTF-8，無 BOM |
| 縮進 | 2 個空格 |
| 鍵名 | 全小寫 `snake_case` |
| 布爾值 | `true` / `false`（小寫，不用 0/1） |
| 注釋 | 不支持 `//`，用 `"_comment": "..."` 代替 |
| 末尾逗號 | 不允許（標準 JSON） |

---

## 數值類型對照

| 用途 | JSON 類型 | 示例 |
|------|-----------|------|
| 時長（秒） | number（可帶小數） | `15`、`1.5` |
| 計數 | number（整數） | `4` |
| 開關 | boolean | `true` |
| 名稱 / ID | string | `"grab_hat"` |
| 列表 | array | `["a", "b"]` |
| 嵌套配置 | object | `{ "x": 1 }` |

---

## 通用語義約定

- **duration 類鍵（時長）**：
  - `0` = **跳過此階段** 或 **等待玩家手動確認**（具體語義見各文件說明）
  - 正數 = 按秒計時自動推進
- **缺失的鍵** → 使用代碼默認值，不會報錯
- `_comment` 鍵僅作說明，程序加載時會自動忽略

---

## 現有配置文件

### `game_flow.json` — 遊戲流程階段時長

```json
{
  "_comment": "遊戲流程各階段時長（秒）。0 = 跳過；SCORING 的 0 = 等待玩家手動確認",
  "theme_announce_duration": 0,
  "grab_clothes_duration": 0,
  "battle_duration": 15,
  "scoring_duration": 0
}
```

| 鍵 | 說明 | 默認值 |
|----|------|--------|
| `theme_announce_duration` | 主題公布展示時長 | `0`（跳過）|
| `grab_clothes_duration` | 搶衣服階段時長 | `0`（跳過）|
| `battle_duration` | 搶鏡頭核心玩法時長 | `15` |
| `scoring_duration` | 結算展示時長 | `0`（等待操作）|

---

## 新增配置文件流程

1. 在 `data/configs/` 新建 `your_config.json`
2. 頂部加 `"_comment"` 說明用途
3. 通知程序端在對應腳本中讀取（`ConfigLoader.load_config("your_config")`）
4. 在本文件補充對應表格說明

---

## 示例：完整規範文件

```json
{
  "_comment": "示例配置，用於說明格式",
  "some_duration": 5,
  "max_players": 4,
  "enable_feature": true,
  "item_ids": ["hat_01", "shirt_01"]
}
```
