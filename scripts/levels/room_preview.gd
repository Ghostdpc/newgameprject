## 职责：房间缩放预览（@tool）—— 编辑器里改 room_scale 实时缩放模型
## 挂到 Stage/Room（glb 实例）节点上；运行时同样生效，无需额外代码
@tool
extends Node3D

## 房间目标最长边（米），编辑器 Inspector 里改此值，模型实时缩放
@export var room_scale: float = 8.0:
	set(v):
		room_scale = v
		if is_node_ready():
			_apply_scale()

## glb 原始最长边（实测，米）
const RAW_LONGEST := 10.585779

func _ready() -> void:
	_apply_scale()

func _apply_scale() -> void:
	var factor := room_scale / RAW_LONGEST if room_scale > 0.0 else 1.0
	scale = Vector3.ONE * factor
