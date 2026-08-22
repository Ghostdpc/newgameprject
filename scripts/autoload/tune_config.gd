## 職責：飛撲/擊飛/布娃娃 運行時可調參數 + 屏幕調參面板（F3 開關）
## 快速調試手感用：F3 顯示，[ ] 選參數，- = 減/加，0 重置當前

extends CanvasLayer

# ---- 可調參數（各狀態直接讀 TuneConfig.xxx）----
var dive_force: float = 9.0        ## 自己飛撲衝刺速度
var hit_force: float = 6.0         ## 擊飛目標水平力
var hit_upward: float = 7.0        ## 擊飛目標上拋初速
var stun_gravity: float = 45.0     ## 被擊飛期間重力（大=上升下降快）
var ground_brake: float = 30.0     ## 倒地落地水平刹車（大=立刻停）
var ragdoll_linear_damp: float = 0.3   ## 布娃娃線性阻尼（小=軟）
var ragdoll_angular_damp: float = 0.3  ## 布娃娃角阻尼（小=擺動大）
var stun_duration: float = 1.8         ## 倒地（Stunned）時長，秒

const _DEFAULTS: Dictionary = {
	"dive_force": 9.0, "hit_force": 6.0, "hit_upward": 7.0,
	"stun_gravity": 45.0, "ground_brake": 30.0,
	"ragdoll_linear_damp": 0.3, "ragdoll_angular_damp": 0.3,
	"stun_duration": 1.8,
}

const CONFIG_PATH: String = "res://data/configs/tune.json"

var _params: Array = [
	{"name": "dive_force", "step": 0.5, "desc": "自己飛撲衝刺速度（大=衝更遠）"},
	{"name": "hit_force", "step": 0.5, "desc": "擊飛目標水平力（大=撞出更遠）"},
	{"name": "hit_upward", "step": 0.5, "desc": "擊飛上拋初速（大=飛更高）"},
	{"name": "stun_gravity", "step": 2.0, "desc": "被擊飛期間重力（大=上升下降快）"},
	{"name": "ground_brake", "step": 2.0, "desc": "倒地落地水平刹車（大=立刻停）"},
	{"name": "ragdoll_linear_damp", "step": 0.1, "desc": "布娃娃線性阻尼（小=更軟更滑）"},
	{"name": "ragdoll_angular_damp", "step": 0.1, "desc": "布娃娃角阻尼（小=擺動更誇張）"},
	{"name": "stun_duration", "step": 0.5, "desc": "倒地癱軟時長，秒"},
]
var _selected: int = 0
var _label: Label
var _status: String = ""

func _ready() -> void:
	layer = 128
	_load()
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_color_override("font_color", Color.YELLOW)
	_label.add_theme_font_size_override("font_size", 20)
	add_child(_label)
	visible = false
	_refresh()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_F3:
			visible = not visible
			_refresh()
			get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT:
			if visible:
				_status = ""
				_selected = (_selected - 1 + _params.size()) % _params.size()
				_refresh()
				get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:
			if visible:
				_status = ""
				_selected = (_selected + 1) % _params.size()
				_refresh()
				get_viewport().set_input_as_handled()
		KEY_MINUS:
			if visible:
				_status = ""
				_adjust(-1)
				get_viewport().set_input_as_handled()
		KEY_EQUAL:
			if visible:
				_status = ""
				_adjust(1)
				get_viewport().set_input_as_handled()
		KEY_0:
			if visible:
				_status = ""
				var pname: String = _params[_selected]["name"]
				set(pname, _DEFAULTS[pname])
				_refresh()
				get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if visible:
				_save()
				get_viewport().set_input_as_handled()

func _adjust(dir: int) -> void:
	var p: Dictionary = _params[_selected]
	var pname: String = p["name"]
	var step: float = p["step"]
	set(pname, maxf(float(get(pname)) + dir * step, 0.0))
	_refresh()

func _refresh() -> void:
	if not _label:
		return
	var head := "[F3] 調參面板   [ ] 選  - = 調值  0 重置  Enter 保存"
	if _status != "":
		head += "   ★ " + _status
	var lines: Array[String] = [head]
	for i in _params.size():
		var pname: String = _params[i]["name"]
		var mark := ">" if i == _selected else " "
		lines.append("%s %-20s %.2f" % [mark, pname, float(get(pname))])
	# 當前選中參數的中文說明
	if _params.size() > 0:
		var cur: Dictionary = _params[_selected]
		lines.append("")
		lines.append("≻ %s：%s" % [cur["name"], cur.get("desc", "")])
	_label.text = "\n".join(lines)

## 從 res://data/configs/tune.json 讀取覆蓋默認值
func _load() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for k in (parsed as Dictionary):
			if _DEFAULTS.has(k):
				set(k, float((parsed as Dictionary)[k]))

## 保存當前參數到 res://data/configs/tune.json（持久化）
func _save() -> void:
	var data: Dictionary = {}
	for k in _DEFAULTS:
		data[k] = float(get(k))
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		_status = "保存失敗（無法寫入）"
		_refresh()
		push_error("TuneConfig: 無法寫入 %s" % CONFIG_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_status = "已保存 → tune.json"
	_refresh()
