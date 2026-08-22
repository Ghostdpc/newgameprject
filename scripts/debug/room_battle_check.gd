## 调试用：headless 跑 room_battle，打印房间 bounds / 碰撞分类统计
extends Node3D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var level := get_node_or_null("RoomBattle")
	if not level:
		print("NO_LEVEL")
		get_tree().quit()
		return
	var room := level.get_node_or_null("Stage/Room") as Node3D
	if not room:
		print("NO_ROOM")
		get_tree().quit()
		return
	await get_tree().create_timer(2.0).timeout
	print("ROOM_SCALE_NODE=%s" % room.scale)
	# bounds（raw，不含根 scale）
	var has := false
	var bounds := AABB()
	var meshes: Array[MeshInstance3D] = []
	_collect(room, meshes)
	for mi in meshes:
		if mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var p := mi.global_transform * Vector3(x, y, z)
					if has:
						bounds = bounds.expand(p)
					else:
						bounds = AABB(p, Vector3.ZERO)
						has = true
	print("ROOM_SIZE_AFTER_SCALE=%s" % bounds.size)
	print("ROOM_CENTER=%s" % bounds.get_center())
	# raw（去掉根 scale 的顶点范围）
	var raw := AABB()
	var has2 := false
	for mi in meshes:
		if mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					var p2 := mi.transform * Vector3(x, y, z)
					if has2:
						raw = raw.expand(p2)
					else:
						raw = AABB(p2, Vector3.ZERO)
						has2 = true
	print("ROOM_RAW_SIZE=%s" % raw.size)
	# 诊断：最大的 global 位置（找偏移来源）
	var big: Array = []
	for mi in meshes:
		if mi.mesh == null:
			continue
		big.append([mi.global_position.length(), mi.name, mi.global_position])
	big.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(8, big.size()):
		print("BIG %s pos=%s" % [big[i][1], big[i][2]])
	# 统计
	var static_count := 0
	var prop_count := 0
	var ignore_count := 0
	for c in room.get_children():
		pass
	for mi in meshes:
		var parent := mi.get_parent()
		if parent is RigidBody3D:
			prop_count += 1
		elif not mi.get_node_or_null("Col") == null:
			static_count += 1
		else:
			ignore_count += 1
	print("COLLISION_STATIC=%d PROP=%d IGNORE=%d" % [static_count, prop_count, ignore_count])
	print_rich("CHECK_DONE")
	get_tree().quit()

func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect(c, out)
