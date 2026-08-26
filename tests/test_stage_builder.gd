## 验证：StageBuilder 小件是否生成为可动物（PhysicalProp）
extends GutTest

func test_stage_builder_dynamic_props() -> void:
	var builder := StageBuilder.new()
	var root := Node3D.new()
	add_child_autofree(root)
	builder.build_show_stage(root)
	var props := _count_prop(root)
	var statics := _count_static(root)
	print("DynamicProp count=", props, " StaticBody count=", statics)
	assert_gt(props, 0, "舞台应有可动物件")

func _count_prop(n: Node) -> int:
	var c := 0
	if n is PhysicalProp:
		c += 1
	for ch in n.get_children():
		c += _count_prop(ch)
	return c

func _count_static(n: Node) -> int:
	var c := 0
	if n is StaticBody3D:
		c += 1
	for ch in n.get_children():
		c += _count_static(ch)
	return c
