## 驗證：face_demo 的表情位姿微調鍵確實驅動 PlayerFaceController
extends GutTest

func test_face_demo_keys_nudge_expression() -> void:
	var scene: PackedScene = load("res://scenes/tech_demos/face_demo.tscn")
	var inst: Node = scene.instantiate()
	add_child_autofree(inst)
	await wait_frames(3)
	# face_demo.tscn 根節點 FaceDemo 即 controller 腳本
	var ctrl: Node = inst  # get_node("FaceDemo")
	var p1: Node = inst.get_node("PlayerP1")
	var fc: Node = p1.get("face")
	assert_not_null(fc, "P1 有 face")
	fc.show_expression(0)
	await wait_frames(1)
	var debug_before: String = fc.call("debug_info")
	var ev := InputEventKey.new()
	ev.keycode = KEY_2
	ev.pressed = true
	ctrl._unhandled_input(ev)
	var debug_after: String = fc.call("debug_info")
	# 若 fallback，fallback_offset 變化；若貼皮，bone_offset 變化——都比對 debug 字串改變
	assert_ne(debug_after, debug_before, "KEY_2 應改變表情位姿")
