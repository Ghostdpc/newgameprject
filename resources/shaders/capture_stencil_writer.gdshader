// 职责：玩家隐形「模板写入」代理。透明不可见，只在玩家可见处写 stencil=1，
// 供取景区域光圈读取 → 实现「只有玩家遮挡光圈」。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// 深度测试通过处（玩家未被场景挡住）写入 stencil 参考值 1
stencil_mode write, compare_always, 1;

void fragment() {
	ALPHA = 0.0;
}
