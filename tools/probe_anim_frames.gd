extends SceneTree

func _init() -> void:
	var inst := (load("res://assets/models/human/newnewhuman.fbx") as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var ap: AnimationPlayer = null
	for a in inst.find_children("*", "AnimationPlayer", true, false):
		ap = a as AnimationPlayer
		break
	for name in ap.get_animation_list():
		var anim: Animation = ap.get_animation(name)
		# 收集每條軌的關鍵幀時間,看整體時間分佈
		var max_t := 0.0
		var key_counts := {}
		for t in anim.get_track_count():
			var kc := anim.track_get_key_count(t)
			key_counts[anim.track_get_path(t)] = kc
			if kc > 0:
				max_t = max(max_t, anim.track_get_key_time(t, kc - 1))
		print("anim='%s' length=%.3f tracks=%d maxkey_t=%.3f" % [name, anim.length, anim.get_track_count(), max_t])
		# 骨骼位置軌的關鍵幀時間分佈(找動作段邊界)
		var times := {}
		for t in anim.get_track_count():
			var p := String(anim.track_get_path(t))
			if p.contains("骨骼.001") or p.contains("骨骼.002") or p.contains("骨骼.005"):
				for i in anim.track_get_key_count(t):
					var tm := anim.track_get_key_time(t, i)
					times[round(tm * 30)] = true
		if times.size() > 0:
			var keys := times.keys()
			keys.sort()
			print("  pose 軌關鍵幀(幀號): ", keys)
	quit()
