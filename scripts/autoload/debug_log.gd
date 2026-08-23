## 調試日誌：所有 print 同時寫入 user://game_log.txt，供打包版崩潰排查
## 用法：DebugLog.log("msg")（註冊為 autoload，名稱 DebugLog）
extends Node

static var _enabled := true
static var _file: FileAccess = null
static var _path := "user://game_log.txt"

func _ready() -> void:
	reopen()

static func _ensure_file() -> void:
	if _file == null:
		_file = FileAccess.open(_path, FileAccess.WRITE)
		if _file:
			_file.store_line("=== game_log start ===")

static func reopen() -> void:
	close()
	_ensure_file()

static func close() -> void:
	if _file:
		_file.close()
		_file = null

static func log(msg: String) -> void:
	if not _enabled:
		return
	_ensure_file()
	if _file:
		_file.store_line("[%d] %s" % [Time.get_ticks_msec(), msg])
		_file.flush()
	print(msg)
