## 职责：HUD，显示阶段名 + 倒计时（取景框内）+ 取景框 RT 绑定
## 玩家面板/气泡/出屏指示由 PlayerHUD 负责

class_name HUD
extends CanvasLayer

@onready var _stage_label: Label = $TopBar/StageLabel
@onready var _timer_label: Label = $CameraViewfinder/TimerLabel
@onready var _photo_rect: TextureRect = $CameraViewfinder/PhotoRect
@onready var _photo_panel: TextureRect = $CameraViewfinder/PhotoRect

func _ready() -> void:
	EventBus.stage_changed.connect(_on_stage_changed)
	EventBus.stage_timer_updated.connect(_on_timer_updated)
	_bind_photo_panel()

func _bind_photo_panel() -> void:
	# 通过 group 查找 PhotoCameraRig（策划可任意命名节点）
	var rig: Node = null
	var rigs := get_tree().get_nodes_in_group("photo_camera_rig")
	if not rigs.is_empty():
		rig = rigs[0]
	if not rig:
		# 兜底：旧结构 PhotoViewport
		var viewport := get_parent().get_node_or_null("PhotoViewport") as SubViewport
		if viewport and _photo_rect:
			_photo_rect.texture = viewport.get_texture()
		return
	var viewport: Viewport = rig.get_render_viewport()
	if viewport and _photo_rect:
		_photo_rect.texture = viewport.get_texture()

func _on_timer_updated(seconds: float) -> void:
	_timer_label.text = "%.0f" % ceilf(seconds)

func _on_stage_changed(stage: int) -> void:
	match stage:
		GameManager.GameStage.MAIN_MENU:
			_stage_label.text = ""
			_timer_label.text = ""
		GameManager.GameStage.THEME_ANNOUNCE:
			_stage_label.text = "主题公布"
		GameManager.GameStage.GRAB_CLOTHES:
			_stage_label.text = "抢衣服！"
		GameManager.GameStage.BATTLE:
			_stage_label.text = "抢镜头！"
		GameManager.GameStage.SCORING:
			_stage_label.text = ""
			_timer_label.text = ""
