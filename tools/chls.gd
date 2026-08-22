extends SceneTree

var _frames: int = 0

func _init() -> void:
	root.add_child(load("res://scenes/tech_demos/active_ragdoll_demo.tscn").instantiate())
	print("LOAD OK")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 50:
		var r := root.get_node("ActiveDemo/Player/RenderModel")
		print("RenderModel children:")
		for c in r.get_children():
			print("  ", c.name, " [", c.get_class(), "]")
		quit(0)
	return false
