extends GutTest

func test_save_load_roundtrip() -> void:
	TuneConfig.hit_force = 12.34
	TuneConfig.ragdoll_angular_damp = 0.15
	TuneConfig._save()
	assert_true(FileAccess.file_exists(TuneConfig.CONFIG_PATH), "應生成 tune.json")
	# 改動後重讀應還原保存值
	TuneConfig.hit_force = 0.0
	TuneConfig.ragdoll_angular_damp = 0.0
	TuneConfig._load()
	assert_almost_eq(TuneConfig.hit_force, 12.34, 0.001, "hit_force 應從檔案還原")
	assert_almost_eq(TuneConfig.ragdoll_angular_damp, 0.15, 0.001, "damp 應還原")
