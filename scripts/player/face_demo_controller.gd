## 職責：表情貼臉測試場景控制。
## P1: Q下一表情 / E上一表情 / R清除；WASD 移動
## P2: U下一表情 / I上一表情 / O清除
## 表情素材為「子沐创意素材 (N)」自動切分後的全部單表情，Q/U 每按一次輪流切換

extends Node3D

var _hint_label: Label

func _ready() -> void:
	_hint_label = $UILayer/Hint as Label
	await get_tree().process_frame
	_refresh_hint()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	var p1 := get_node_or_null("PlayerP1") as Node
	var p2 := get_node_or_null("PlayerP2") as Node
	match k:
		KEY_Q: _cycle(p1, 1)
		KEY_E: _cycle(p1, -1)
		KEY_R: _clear(p1)
		KEY_U: _cycle(p2, 1)
		KEY_I: _cycle(p2, -1)
		KEY_O: _clear(p2)
	_refresh_hint()

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
	var t2 := _face_total(p2)
	var c1 := _cur_desc(p1)
	var c2 := _cur_desc(p2)
	_hint_label.text = "表情素材共 %d 張（素材資料夾自動切分）\n[P1] Q下 / E上 / R清除 → %s\n[P2] U下 / I上 / O清除 → %s" % [t1, c1, c2]

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
