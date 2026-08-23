## 職責：表情貼臉測試場景控制。
## P1: Q/E 切換表情（按住連續）/ R清除；WASD 移動；T 凍結/解凍角色動畫
## P2: U/I 切換表情（按住連續）/ O清除
## 表情素材為「子沐创意素材 (N)」自動切分後的全部單表情，Q/U 每按一次輪流切換
## P1 表情位姿微調（主鍵盤）：
##   T/G=X±  Y/H=Y±  U/J=Z±  N/M=偏航  B/V=俯仰  5=還原默認

extends Node3D

const POS_STEP := 0.02
const ROT_STEP := 5.0
## 長按連續切換的最小間隔（秒）
const HOLD_INTERVAL := 0.12

var _hint_label: Label
var _last_debug: String = ""
## 長按計時器
var _hold_timer: float = 0.0
## 輸入框
var _edit: LineEdit
var _edit_mode: Label

func _ready() -> void:
	_hint_label = $UILayer/Hint as Label
	_edit = $UILayer/FaceEdit as LineEdit
	_edit_mode = $UILayer/EditMode as Label
	if _edit:
		_edit.text_submitted.connect(_apply_input)
	await get_tree().process_frame
	_refresh_hint()

## 解析 輸入框 的 數值設置：pos/x,y,z 或 rot/x,y,z 或 scale/f
func _apply_input(text: String) -> void:
	_edit.clear()
	_edit.release_focus()
	var p1 := get_node_or_null("PlayerP1") as Node
	if p1 == null:
		return
	var fc := _face_of(p1)
	if fc == null:
		return
	var t := text.strip_edges()
	# 剝離前綴：pos/x,y,z | rot/x,y,z | scale/f
	var nums := t.split("/", false, 1)
	var cmd := ""
	if nums.size() == 2:
		cmd = nums[0].strip_edges()
		t = nums[1].strip_edges()
	var parts := t.split(",")
	if cmd == "scale" or cmd == "s":
		var f := float(parts[0].strip_edges())
		var s: Node3D = fc.get("_sprite")
		if s and f > 0:
			# 縮放整個顯示節點（平面 sprite 也支持）
			s.scale = Vector3.ONE * f
			fc.set("_user_scale", f)
			_feedback("scale=%.2f" % f)
		return
	if parts.size() != 3:
		_feedback("格式：pos/x,y,z 或 rot/x,y,z 或 scale/f")
		return
	var v := Vector3(float(parts[0].strip_edges()),
		float(parts[1].strip_edges()), float(parts[2].strip_edges()))
	if cmd == "pos":
		fc.set("bone_offset", v)
		var s: Node3D = fc.get("_sprite")
		if s: s.position = v
		_feedback("pos=%s" % v)
	elif cmd == "rot":
		fc.set("bone_rotation", v)
		var s: Node3D = fc.get("_sprite")
		if s: s.rotation = v
		_feedback("rot=%s" % v)
	else:
		_feedback("未知指令：%s" % t)
	_refresh_hint()

func _feedback(t: String) -> void:
	var fb := get_node_or_null("UILayer/Feedback") as Label
	if fb:
		fb.text = t

## 每幀刷新提示，讓位姿參數一直可見
func _process(delta: float) -> void:
	_refresh_hint()
	# 輸入框聚焦時自動凍結玩家，防止打字觸發移動/跳/撲
	var editing := _edit != null and _edit.has_focus()
	_apply_auto_freeze(editing)
	_handle_hold(delta)

## 輸入時凍結玩家（不覆蓋用戶手動 T 凍結，僅在欄聚焦時頂用）
func _apply_auto_freeze(editing: bool) -> void:
	var p1 := get_node_or_null("PlayerP1") as Node
	var p2 := get_node_or_null("PlayerP2") as Node
	for p in [p1, p2]:
		if p == null:
			continue
		if editing:
			p.set("frozen", true)
		elif not (p.get("_user_frozen") == true):
			p.set("frozen", false)

## 長按 Q/E / U/I 連續切換表情；數字鍵連續微調位姿
func _handle_hold(delta: float) -> void:
	if _edit and _edit.has_focus():
		return
	_hold_timer += delta
	if _hold_timer < HOLD_INTERVAL:
		return
	_hold_timer = 0.0
	var p1 := get_node_or_null("PlayerP1") as Node
	var p2 := get_node_or_null("PlayerP2") as Node
	if Input.is_key_pressed(KEY_Q):
		_cycle(p1, 1)
	if Input.is_key_pressed(KEY_E):
		_cycle(p1, -1)
	if Input.is_key_pressed(KEY_U):
		_cycle(p2, 1)
	if Input.is_key_pressed(KEY_I):
		_cycle(p2, -1)
	# 數字鍵長按連續微調
	if Input.is_key_pressed(KEY_1):
		_nudge(p1, Vector3(-POS_STEP, 0, 0), 0.0)
	if Input.is_key_pressed(KEY_2):
		_nudge(p1, Vector3(POS_STEP, 0, 0), 0.0)
	if Input.is_key_pressed(KEY_3):
		_nudge(p1, Vector3(0, POS_STEP, 0), 0.0)
	if Input.is_key_pressed(KEY_4):
		_nudge(p1, Vector3(0, -POS_STEP, 0), 0.0)
	if Input.is_key_pressed(KEY_5):
		_nudge(p1, Vector3(0, 0, -POS_STEP), 0.0)
	if Input.is_key_pressed(KEY_6):
		_nudge(p1, Vector3(0, 0, POS_STEP), 0.0)
	if Input.is_key_pressed(KEY_7):
		_nudge(p1, Vector3.ZERO, -ROT_STEP)
	if Input.is_key_pressed(KEY_8):
		_nudge(p1, Vector3.ZERO, ROT_STEP)
	if Input.is_key_pressed(KEY_9):
		_pitch(p1, -ROT_STEP)
	if Input.is_key_pressed(KEY_0):
		_pitch(p1, ROT_STEP)
	if Input.is_key_pressed(KEY_BRACKETLEFT):
		_roll(p1, -ROT_STEP)
	if Input.is_key_pressed(KEY_BRACKETRIGHT):
		_roll(p1, ROT_STEP)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# LineEdit 輸入中不處理調試鍵
	if _edit and _edit.has_focus():
		return
	var k := (event as InputEventKey).keycode
	# 有些鍵 keycode 為 0 只填 physical；兼容兩者
	if k == 0:
		k = (event as InputEventKey).physical_keycode
	var p1 := get_node_or_null("PlayerP1") as Node
	var p2 := get_node_or_null("PlayerP2") as Node
	match k:
		KEY_R: _clear(p1)
		KEY_O: _clear(p2)
		KEY_T: _toggle_freeze(p1)
		KEY_M: _toggle_mask(p1)
		KEY_H: _toggle_garment_attach(p1)
		KEY_N: _toggle_head_texture(p1)
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
		KEY_BRACKETLEFT: _roll(p1, -ROT_STEP)
		KEY_BRACKETRIGHT: _roll(p1, ROT_STEP)
		KEY_MINUS: _reset_debug(p1)
	_refresh_hint()

## 凍結/解凍：暫停動畫 + 關閉彈簧骨骼，角色定住方便看表情
func _toggle_freeze(actor: Node) -> void:
	if actor == null:
		return
	var user_frozen: bool = not (actor.get("frozen") == true)
	actor.set("_user_frozen", user_frozen)
	actor.set("frozen", user_frozen)
	var ap: AnimationPlayer = actor.get("_animation_player")
	var sr: Node = actor.get("spring_rig")
	if ap:
		if user_frozen:
			ap.pause()
		else:
			ap.play(actor.get("_current_anim"))
	if sr:
		sr.set_active(not user_frozen)

## 切換半球面具/平面貼紙（M 鍵）
func _toggle_mask(actor: Node) -> void:
	var fc := _face_of(actor)
	if fc == null:
		return
	var skel: Node = fc.get("skeleton")
	if skel == null:
		return
	fc.use_face_mask = not fc.use_face_mask
	var keep: int = int(fc.get("_current_index"))
	if fc.get("_sprite"):
		fc.get("_sprite").queue_free()
	fc.set("_sprite", null)
	fc.setup(skel)
	if keep >= 0 and fc.count() > 0:
		fc.show_expression(min(keep, fc.count() - 1))
	var fb := get_node_or_null("UILayer/Feedback") as Label
	if fb:
		fb.text = "表情模式：%s" % ("半球面具" if fc.use_face_mask else "平面貼紙")
	_refresh_hint()

## 穿上蘑菇帽+把表情貼到服裝上（H 鍵驗證）
func _toggle_garment_attach(actor: Node) -> void:
	var pc := actor as PlayerController
	if pc == null:
		return
	var fc := pc.get("face") as Node
	if fc == null:
		return
	var attach_now: bool = not fc.get("attach_to_garment")
	fc.set("attach_to_garment", attach_now)
	if attach_now:
		# 穿蘑菇帽（hat_slot，實體模型，貼近頭頂適合當"臉"載體）
		var worn := pc.outfit_manager.get_item("hat_slot")
		if worn == null and GarmentSystem:
			GarmentSystem.equip_garment(pc, "mushroom_hat")
		var ok: bool = fc.call("apply_garment_attach")
		print("[face] garment attach ok=", ok, " host=", fc.get("_garment_host"))
		var fb := get_node_or_null("UILayer/Feedback") as Label
		if fb:
			fb.text = "服裝貼臉：%s" % ("已附著蘑菇帽" if ok else "失敗：無服裝節點")
	else:
		# 卸下：還原服裝材質，恢復貼皮
		fc.call("detach_garment", fc.get("skeleton"))
	_refresh_hint()

## 切換直接把表情貼到模型頭部材質(newhuman)（N 鍵）
func _toggle_head_texture(actor: Node) -> void:
	var fc := _face_of(actor)
	if fc == null:
		return
	var on: bool = not fc.get("use_head_texture")
	fc.set("use_head_texture", on)
	if on:
		var ok: bool = fc.call("apply_head_texture")
		print("[face] head_texture ok=", ok)
		var fb := get_node_or_null("UILayer/Feedback") as Label
		if fb:
			fb.text = "頭部貼圖：%s" % ("已貼臉" if ok else "失敗：找不到頭部 surface")
	else:
		# 還原頭部材質 + 恢復貼皮
		fc.call("revert_head_texture")
		fc.set("use_head_texture", false)
		var fb2 := get_node_or_null("UILayer/Feedback") as Label
		if fb2:
			fb2.text = "頭部貼圖：已還原"
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

## 微調滾動
func _roll(actor: Node, delta_deg: float) -> void:
	var fc := _face_of(actor)
	if fc:
		fc.call("nudge_roll", delta_deg)

## 還原默認偏移與旋轉（貼皮模式：bone_offset + bone_rotation；fallback：歸回預設）
func _reset_debug(actor: Node) -> void:
	var fc := _face_of(actor)
	if fc == null:
		return
	var sprite: Node3D = fc.get("_sprite")
	if fc.get("_used_fallback"):
		fc.set("fallback_offset", Vector3(0.0, 2.2, 0.0))
		if sprite:
			sprite.position = fc.get("fallback_offset")
			sprite.rotation = Vector3.ZERO
	else:
		fc.set("bone_offset", Vector3(-0.16, -0.62, 0.04))
		if sprite:
			sprite.position = fc.get("bone_offset")
			if fc.use_face_mask:
				sprite.rotation = fc.get("mask_rotation")
			else:
				sprite.rotation = Vector3(0.0, deg_to_rad(-90.0), 0.0)

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
	var frozen := ""
	if p1 and p1.get("frozen"):
		frozen = "  🧊已凍結"
	_hint_label.text = (
		"表情素材共 %d 張\n"
		+ "[P1] Q/E長按連續切 → %s   [P2] U/I長按連續切 → %s\n"
		+ "P1 位姿 → %s%s\n"
		+ "P1位姿[長按數字連調] 1/2=X  3/4=Y  5/6=Z  7/8=偏航  9/0=俯仰  [/=滾動  -=還原  T=凍結  M=面具/平面  H=貼臉服裝  N=貼頭材質"
	) % [t1, c1, c2, d1, frozen]
	if d1 != _last_debug:
		_last_debug = d1
		print("[face] ", d1)
	if _edit_mode:
		var f2 := _face_of(p1)
		if f2:
			var pos: Vector3 = f2.get("bone_offset")
			var rotv: Vector3 = f2.get("bone_rotation")
			var info := "mask" if f2.use_face_mask else "sprite"
			_edit_mode.text = ("%s  pos=%s  rot=%s" % [info, pos, rotv]) \
				+ "  輸入: pos/x,y,z | rot/x,y,z | scale/f"

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
