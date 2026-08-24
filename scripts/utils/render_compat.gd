class_name RenderCompat
## Web 导出使用 gl_compatibility (WebGL2) 渲染器：LDR、无 HDR。
## 发光值 >1.0 会被 clamp 成纯白，glow 在 LDR 空间计算导致炫光爆亮。
## PC 走 Forward+ (HDR) 无此问题。发光效果统一经由此处降参。

## Web (LDR、无 HDR) 下按比例缩放发光/灯光强度。
## PC (Forward+、HDR) 保持原值。比例可在此统一调。
const LDR_SCALE := 0.35

static func is_compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

## 无 HDR 时把发光/灯光强度等比压低，保留相对亮度层级。
static func emission_energy(value: float) -> float:
	return value * (LDR_SCALE if is_compat() else 1.0)

## 关卡 WorldEnvironment 的后处理补偿。
## Compatibility(WebGL2) 无 HDR 浮点缓冲：glow_hdr_threshold 失效导致全屏泛白爆 bloom，
## 且 SSAO / 体积雾 不渲染使画面失去暗部。这里对该实例的 Environment 副本降 glow、
## 补回暗部曝光。PC(Forward+) 直接返回，保持 .tres 原设定。
static func apply_environment(world_env: WorldEnvironment) -> void:
	if world_env == null or world_env.environment == null:
		return
	if not is_compat():
		return
	var env: Environment = world_env.environment.duplicate()
	# 换 AgX 色调映射：Compat 逐片元 tonemap 是唯一有效的 HDR->LDR 介入点。
	# AgX 平滑滚降高光 + 保色相，替代 Filmic 的爆白（屏幕后处理无法救已 clamp 的像素）。
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	# AgX 已压住高光，glow 保留但收小：去 bloom（全屏泛白主因）、降 intensity/strength
	env.glow_bloom = 0.0
	env.glow_intensity = minf(env.glow_intensity, 0.5)
	env.glow_strength = minf(env.glow_strength, 0.5)
	# 少了 SSAO / 体积雾 的压暗，降曝光与环境光补回暗部
	env.tonemap_exposure = env.tonemap_exposure * 0.75
	env.ambient_light_energy = env.ambient_light_energy * 0.75
	world_env.environment = env
