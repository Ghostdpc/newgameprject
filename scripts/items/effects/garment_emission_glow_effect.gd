## 职责：garment_emission_glow 效果 —— 穿上时角色全身自发光，脱下还原
## 原理：对 CharacterEffects 管理的所有 MeshInstance3D 叠加 emission_energy

class_name GarmentEmissionGlowEffect
extends ItemEffect

## 保存修改过的 mesh 列表，用于 revert
var _modified_meshes: Array[MeshInstance3D] = []
var _halo_fx: Node = null

func apply(ctx: ItemContext) -> void:
	if ctx.source_player == null:
		return
	_modified_meshes.clear()
	var strength: float = float(params.get("strength", 0.6))
	var root: Node3D = ctx.source_player
	# 光環（halo）：用專用的彩虹流光+脈衝+粒子光暈效果，替代全身統一發光
	if ctx.item_id == "halo" and root.outfit_manager:
		var hat: Node3D = root.outfit_manager.get_item("hat_slot")
		if hat:
			var fx := Node.new()
			fx.set_script(load("res://scripts/items/effects/halo_dynamic_fx.gd"))
			hat.add_child(fx)
			fx.call("setup", hat)
			fx.call("setup_aura", ctx.source_player)
			_halo_fx = fx
			return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var src: Material = mi.get_active_material(0)
		var mat: StandardMaterial3D
		if src is StandardMaterial3D:
			mat = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission = mat.albedo_color if mat.albedo_color != Color.BLACK else Color.WHITE
		mat.emission_energy_multiplier = strength
		mi.material_override = mat
		_modified_meshes.append(mi)

func revert(ctx: ItemContext) -> void:
	if _halo_fx and is_instance_valid(_halo_fx):
		_halo_fx.queue_free()
		_halo_fx = null
	for mi in _modified_meshes:
		if is_instance_valid(mi):
			mi.material_override = null
	_modified_meshes.clear()
