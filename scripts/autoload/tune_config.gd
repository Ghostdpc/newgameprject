## 职责：飞扑/击飞/布娃娃 运行时可调参数 + 屏幕调参面板（F3 开关）
## 快速调试手感用：F3 显示，[ ] 选参数，- = 减/加，0 重置当前

extends CanvasLayer

# ---- 可调参数（各状态直接读 TuneConfig.xxx）----
var move_speed: float = 5.0        ## 角色移动速度
var dive_force: float = 9.0        ## 自己飞扑冲刺速度
var hit_force: float = 6.0         ## 击飞目标水平力
var hit_upward: float = 7.0        ## 击飞目标上抛初速
var stun_gravity: float = 45.0     ## 被击飞期间重力（大=上升下降快）
var ground_brake: float = 30.0     ## 倒地落地水平刹车（大=立刻停）
var ragdoll_linear_damp: float = 0.3   ## 布娃娃线性阻尼（小=软）
var ragdoll_angular_damp: float = 0.3  ## 布娃娃角阻尼（小=摆动大）
var stun_duration: float = 1.8         ## 倒地（Stunned）时长，秒
var head_scale: float = 1.0            ## 头部放大倍率（服装效果）
var body_scale: float = 1.0            ## 身躯放大倍率（服装效果）

const _DEFAULTS: Dictionary = {
	"move_speed": 5.0, "dive_force": 9.0, "hit_force": 6.0, "hit_upward": 7.0,
	"stun_gravity": 45.0, "ground_brake": 30.0,
	"ragdoll_linear_damp": 0.3, "ragdoll_angular_damp": 0.3,
	"stun_duration": 1.8, "head_scale": 1.0, "body_scale": 1.0,
}

const CONFIG_PATH: String = "res://data/configs/tune.json"

var _params: Array = [
	{"name": "move_speed", "step": 0.5, "desc": "角色移动速度（大=跑更快）"},
	{"name": "dive_force", "step": 0.5, "desc": "自己飞扑冲刺速度（大=冲更远）"},
	{"name": "hit_force", "step": 0.5, "desc": "击飞目标水平力（大=撞出更远）"},
	{"name": "hit_upward", "step": 0.5, "desc": "击飞上抛初速（大=飞更高）"},
	{"name": "stun_gravity", "step": 2.0, "desc": "被击飞期间重力（大=上升下降快）"},
	{"name": "ground_brake", "step": 2.0, "desc": "倒地落地水平刹车（大=立刻停）"},
	{"name": "ragdoll_linear_damp", "step": 0.1, "desc": "布娃娃线性阻尼（小=更软更滑）"},
	{"name": "ragdoll_angular_damp", "step": 0.1, "desc": "布娃娃角阻尼（小=摆动更夸张）"},
	{"name": "stun_duration", "step": 0.5, "desc": "倒地瘫软时长，秒"},
	{"name": "head_scale", "step": 0.1, "desc": "头部放大倍率（1=正常，>1 头变大）"},
	{"name": "body_scale", "step": 0.1, "desc": "身躯放大倍率（1=正常，>1 身体变大）"},
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
	var head := "[F3] 调参面板   [ ] 选  - = 调值  0 重置  Enter 保存"
	if _status != "":
		head += "   ★ " + _status
	var lines: Array[String] = [head]
	for i in _params.size():
		var pname: String = _params[i]["name"]
		var mark := ">" if i == _selected else " "
		lines.append("%s %-20s %.2f" % [mark, pname, float(get(pname))])
	# 当前选中参数的中文说明
	if _params.size() > 0:
		var cur: Dictionary = _params[_selected]
		lines.append("")
		lines.append("≻ %s：%s" % [cur["name"], cur.get("desc", "")])
	_label.text = "\n".join(lines)

## 从 res://data/configs/tune.json 读取覆盖默认值
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

## 保存当前参数到 res://data/configs/tune.json（持久化）
func _save() -> void:
	var data: Dictionary = {}
	for k in _DEFAULTS:
		data[k] = float(get(k))
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		_status = "保存失败（无法写入）"
		_refresh()
		push_error("TuneConfig: 无法写入 %s" % CONFIG_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_status = "已保存 → tune.json"
	_refresh()
