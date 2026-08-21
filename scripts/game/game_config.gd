## 職責：各遊戲階段時長配置（秒，0 = 跳過或等待玩家操作）

class_name GameConfig
extends Resource

## 主題公布（0 = 跳過）
@export var theme_announce_duration: float = 0.0

## 搶衣服階段（0 = 跳過）
@export var grab_clothes_duration: float = 0.0

## 倒計時混戰/搶鏡頭（核心玩法）
@export var battle_duration: float = 60.0

## 系統評分展示（0 = 停留直到玩家按鈕）
@export var scoring_duration: float = 0.0
