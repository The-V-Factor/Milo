# Milo AppIcon

使用内置 imagegen 生成，原始画面为透明背景的机器人应用图标。项目中的 1024 × 1024 主图为 `Milo/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`；其余尺寸由同一生成图使用 macOS `sips` 缩放，保留透明通道。

Xcode 的 Debug / Release 均使用 `AppIcon`，由 Asset Catalog 编译为应用图标。菜单栏继续使用适合单色显示的 CPU 符号。

## 生成提示词

Use case: logo-brand. Asset type: production macOS application icon for Milo, a quiet CPU and memory monitor. Create one square 1024x1024 icon, no mockup. A friendly original miniature robot head, front facing, a softly rounded ivory ceramic shell, dark charcoal glass face with two bright mint-green vertical rounded eyes, tiny subtle ear details. Simple bold silhouette, tasteful soft 3D depth, extremely readable at 32 pixels, no fine circuitry or text. Robot centered and large on a deep midnight teal rounded-square macOS icon tile with soft bevel and restrained lighting. Tile occupies about 88 percent of canvas with equal transparent padding around it and rounded corners; genuinely transparent outside the tile, preserve alpha. Calm, polished native desktop utility aesthetic, charming but minimal. No letters, no watermark, no extra objects, no border frame around canvas. Use mint to match Milo's existing UI. Entire tile visible with comfortable margin.
