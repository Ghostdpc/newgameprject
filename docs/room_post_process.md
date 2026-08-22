# Room Test 后处理调参

场景使用两个可直接编辑的后处理资源：

- `resources/environments/room_post_process.tres`：整体色调、曝光、泛光、环境遮蔽。
- `resources/materials/room_cartoon_outline_post_process.tres`：屏幕空间卡通描边。

## 在 Godot 中打开

1. 打开 `scenes/levels/room_test.tscn`。
2. 在左侧 Scene 树选中 `WorldEnvironment`，在 Inspector 的 `Environment` 属性点击 `RoomPostProcess`。
3. 或直接在 FileSystem 双击以上两个资源文件；修改会立即影响 `room_test.tscn`。

## 建议参数

| 目标 | 参数 | 建议范围 |
| --- | --- | --- |
| 更明亮 | Tonemap > Exposure | 1.05–1.30 |
| 颜色更鲜艳 | Adjustments > Saturation | 1.05–1.20 |
| 更柔和的粉紫氛围 | Background Color / Ambient Light Color | 偏粉紫的浅色 |
| 发光更明显 | Glow > Intensity / Strength | 0.12–0.30 / 0.30–0.65 |
| 接触阴影更强 | SSAO > Intensity / Power | 0.80–1.50 / 1.00–1.80 |
| 描边更粗 | Outline Size | 1.2–2.0 |
| 描边更容易出现 | Edge Threshold | 0.04–0.08（越小越明显） |
| 描边更柔和 | Edge Softness | 0.04–0.10 |

过强的 SSAO、Glow 或过低的 Edge Threshold 都可能使画面脏或出现噪点；一次只调整一个参数并观察场景视口。
