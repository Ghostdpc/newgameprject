## 職責：表情貼臉測試場景控制。
## P1: Q下一表情 / E上一表情 / R清除；WASD 移動
## P2: U下一表情 / I上一表情 / O清除
## 表情素材為「子沐创意素材 (N)」自動切分後的全部單表情，Q/U 每按一次輪流切換
## P1 表情位姿微調（主鍵盤）：
##   T/G=X±  Y/H=Y±  U/J=Z±  N/M=偏航  B/V=俯仰  5=還原默認

extends Node3D

const POS_STEP := 0.02
const ROT_STEP := 5.0

var _hint_label: Label
var _last_debug: String = ""

func _ready() -> void:
	_hint_label = $UILayer/Hint as Label
	await get_tree().process_frame
	_refresh_hint()

## 每幀刷新提示，讓位姿參數一直可見
func _process(_delta: float) -> void:
	_refresh_hint()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	# 有些鍵 keycode 為 0 只填 physical；兼容兩者
	if k == 0:
		k = (event as InputEventKey).physical_keycode
	var p1 := get_node_or_null("PlayerP1") as Node
	var p2 := get_node_or_null("PlayerP2") as Node
	match k:
		KEY_Q: _cycle(p1, 1)
		KEY_E: _cycle(p1, -1)
		KEY_R: _clear(p1)
		KEY_U: _cycle(p2, 1)
		KEY_I: _cycle(p2, -1)
		KEY_O: _clear(p2)
		KEY_1: _nudge(p1, Vector3(-POS_STEP, 0, 0), 0.0)
		KEY_2: _nudge(p1, Vector3(POS_STEP, 0, 0), 0.0)
		KEY_3: _nudge(p1, Vector3(0, POS_STEP, 0), 0.0)
		KEY_4: _nudge(p1, Vector3(0, -POS_STEP, 0), 0.0)
		KEY_5: _nudge(p1, Vector3(0, 0, -POS_STEP), 0.0)
		KEY_6: _nudge(p1, Vector3(0, 0, POS_STEP), 0.0)
		KEY_7: _nudge(p1, Vector3.ZERO, -ROT_STEP)
		KEY_8: _nudge(p1, Vector3.ZERO, ROT_STEP)
		KEY_9: _pitch(p1, -ROT_STEP)
		KEY_0: _pitch(p1, ROT_STEP)
		KEY_MINUS: _reset_debug(p1)
	_refresh_hint()

## 微調位置/偏航
func _nudge(actor: Node, delta_pos: Vector3, delta_yaw_deg: float) -> void:
	var fc := _face_of(actor)
	if fc == null:
		return
	if delta_pos != Vector3.ZERO:
		fc.call("nudge_offset", delta_pos)
	if delta_yaw_deg != 0.0:
		fc.call("nudge_facing", delta_yaw_deg)

## 微調俯仰
func _pitch(actor: Node, delta_deg: float) -> void:
	var fc := _face_of(actor)
	if fc:
		fc.call("nudge_pitch", delta_deg)

## 還原默認偏移與旋轉（貼皮模式：bone_offset + 背向旋轉；fallback：歸回預設）
func _reset_debug(actor: Node) -> void:
	var fc := _face_of(actor)
	if fc == null:
		return
	var sprite: Node3D = fc.get("_sprite")
	if fc.get("_used_fallback"):
		fc.set("fallback_offset", Vector3(0.0, 2.2, 0.0))
		if sprite:
			sprite.position = fc.get("fallback_offset")
	else:
		fc.set("bone_offset", Vector3(0.0, 0.5, -0.42))
		if sprite:
			sprite.position = fc.get("bone_offset")
	if sprite:
		sprite.rotation = Vector3(0.0, PI, 0.0) if not fc.get("_used_fallback") else Vector3.ZERO

func _face_of(actor: Node) -> Node:
	if actor == null:
		return null
	return actor.get("face") as Node

func _cycle(actor: Node, dir: int) -> void:
	if actor == null:
		return
	var fc := actor.get("face") as Node
	if fc == null:
		return
	var total: int = fc.call("count")
	var cur: int = fc.get("_current_index")
	var next_idx: int
	if total <= 0:
		return
	if cur < 0:
		next_idx = 0
	elif dir > 0:
		next_idx = cur + 1 if cur < total - 1 else -1
	else:
		next_idx = cur - 1 if cur > 0 else -1
	fc.call("show_expression", next_idx)

func _clear(actor: Node) -> void:
	if actor != null:
		var fc := actor.get("face") as Node
		if fc:
			fc.call("clear")

func _refresh_hint() -> void:
	var p1 := get_node_or_null("PlayerP1") as Node
	var p2 := get_node_or_null("PlayerP2") as Node
	var t1 := _face_total(p1)
	var c1 := _cur_desc(p1)
	var c2 := _cur_desc(p2)
	var d1 := "（無表情系統）"
	var f1 := _face_of(p1)
	if f1:
		d1 = String(f1.call("debug_info"))
	_hint_label.text = (
		"表情素材共 %d 張\n"
		+ "[P1] Q下 / E上 / R清除 → %s    [P2] U下 / I上 / O清除 → %s\n"
		+ "P1 位姿 → %s\n"
		+ "P1位姿[主鍵數字] 1/2=X  3/4=Y  5/6=Z  7/8=偏航  9/0=俯仰  -=還原"
	) % [t1, c1, c2, d1]
	if d1 != _last_debug:
		_last_debug = d1
		print("[face] ", d1)

func _face_total(actor: Node) -> int:
	if actor == null:
		return 0
	var fc := actor.get("face") as Node
	return fc.call("count") if fc else 0

func _cur_desc(actor: Node) -> String:
	if actor == null:
		return "無角色"
	var fc := actor.get("face") as Node
	if fc == null:
		return "無表情系統"
	var cur: int = fc.get("_current_index")
	return "表情 #%d" % (cur + 1) if cur >= 0 else "無表情"
