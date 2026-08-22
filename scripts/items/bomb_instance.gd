## 職責：炸彈實例 —— 繼承 PhysicalProp 拋出物理體，引信秒數後範圍爆炸。
## 爆炸對半徑內所有玩家施加：灰頭土臉貼花 + 積分懲罰（累加到 PlayerController.score_penalty）。
## 與 trap 系統無關：AOE 用球形距離檢測，非踩踏觸發。

class_name BombInstance
extends PhysicalProp

var _fuse: float = 1.2
var _radius: float = 3.0
var _gray_duration: float = 6.0
var _score_penalty: int = 15
var _thrower: PlayerController
var _exploded: bool = false

## 由 ThrowBombEffect 調用：配置參數並拋出
func setup_bomb(p: Dictionary, thrower: PlayerController) -> void:
	_fuse          = float(p.get("fuse", 1.2))
	_radius        = float(p.get("radius", 3.0))
	_gray_duration = float(p.get("gray_duration", 6.0))
	_score_penalty = int(p.get("score_penalty", 15))
	_thrower       = thrower
	prop_mass      = 2.0
	prop_bounce    = 0.3
	prop_linear_damp = 0.4

func _ready() -> void:
	super._ready()
	# 引信計時後引爆
	var timer := get_tree().create_timer(_fuse)
	timer.timeout.connect(_explode)

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_spawn_flash()
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as PlayerController
		if player == null:
			continue
		if global_position.distance_to(player.global_position) > _radius:
			continue
		if player.character_effects:
			player.character_effects.apply_dirt_decal(_gray_duration)
		player.score_penalty += _score_penalty
	queue_free()

## 爆炸視覺占位：快速膨脹後消失的橙色球（無需美術資源）
func _spawn_flash() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	scene.add_child(flash)
	flash.global_position = global_position
	var tw := flash.create_tween()
	tw.parallel().tween_property(flash, "scale", Vector3.ONE * (_radius * 2.0), 0.25)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(flash.queue_free)
