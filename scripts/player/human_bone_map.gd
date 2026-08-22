## 職責：Human.fbx 骨骼部位映射 —— 把語義部位名映射到 Blender 無語義編號骨（骨骼.00x）
## 供 ragdoll / outfit / 身材缩放等需要按部位取骨名的系統在 Human 上使用。
## 骨骼編號基於 rest 姿態世界坐標推斷（A-pose：雙臂沿 Z 水平、雙腿沿 Y 落地、躯干沿 Y）。
## 若模型改動導致映射失效，重新運行 tools/probe_bones.gd 校正。
class_name HumanBoneMap

## 語義部位 -> 實際骨名（Blender 骨骼.00x）
const BONES: Dictionary = {
	"hips": "骨骼.001",
	"spine": "骨骼.002",
	"chest": "骨骼.004",
	"neck": "骨骼.005",
	"head": "骨骼.005_end_end_end_end",
	# 左臂（+Z 側）
	"upperarm.l": "骨骼.011",
	"lowerarm.l": "骨骼.012",
	"hand.l": "骨骼.015",
	"handslot.l": "骨骼.015",
	# 右臂（-Z 側）
	"upperarm.r": "骨骼.013",
	"lowerarm.r": "骨骼.014",
	"hand.r": "骨骼.016",
	"handslot.r": "骨骼.016",
	# 左腿
	"upperleg.l": "骨骼.006",
	"lowerleg.l": "骨骼.009",
	# 右腿
	"upperleg.r": "骨骼.007",
	"lowerleg.r": "骨骼.010",
}

## 依骨名映射到 human 實際骨名；非 human 或無映射直接回傳原名
static func resolve(bone_name: String, is_human: bool) -> String:
	if not is_human:
		return bone_name
	return BONES.get(bone_name, bone_name)
