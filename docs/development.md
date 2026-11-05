# 开发与发布

Milo 使用 SwiftUI + AppKit，无第三方依赖。[返回首页](../README.md)。

## 本地运行

1. 使用 Xcode 16 或更新版本打开 `Milo.xcodeproj`。
2. 选择 **Milo → My Mac**，按 **⌘R**。
3. 菜单栏出现 `CPU …% · MEM …%`。应用没有主窗口，也不占 Dock。

最低支持 macOS 14，兼容 Apple Silicon 与 Intel。工程使用本机 ad-hoc 签名，无需配置开发者账号。

## 验证

```sh
rtk proxy xcodebuild -project Milo.xcodeproj -scheme Milo -configuration Debug -derivedDataPath .build build
rtk proxy xcodebuild -project Milo.xcodeproj -scheme Milo -configuration Debug -derivedDataPath .build test
```

自动化测试覆盖 CPU 差值、计数器回绕、4K / 16K 内存页、缓存去重、Swap 双向速率与实际间隔换算、60 秒窗口加权 / 裁剪、10 / 50 MiB/s 阈值边界、采样中断 / 重置、不可用状态，以及真实本机采样。图形界面还应检查悬停、点击固定、外部点击 / Esc 关闭、透明度拖动、日间 / 夜间切换、小屏滚动和睡眠唤醒。自动化构建与测试不替代 GUI、Intel 与多系统版本的实机验收。

新增应用 / 磁盘测试覆盖辅助进程归组、PID 复用、部分可读数据、独立 Top 5 排序、CPU 时钟单位、多磁盘差值、热插拔、计数回退及容量边界。离屏布局检查包含长应用名、满额排行榜及小屏高度上限；真实菜单栏切页、滚动和睡眠唤醒交互仍需手动检查。

## 发布

采用免费的 ad-hoc 签名，不进行 Developer ID 签名或 Apple 公证。安装者需自行决定是否信任应用，首次打开的操作说明见各版本 Release。

更新工程的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，在 `docs/releases/<版本>.md` 写好发布说明，提交并推送后，在该提交上创建并推送 `v<版本>` 标签。GitHub Actions 会运行测试、构建 Intel / Apple Silicon 通用应用、生成含 Applications 快捷方式的 DMG 和 SHA-256 文件，并创建 GitHub Release。标签版本必须与应用版本一致。

发布工作流使用仓库自带的 `GITHUB_TOKEN`，无需个人 Token 或 Apple 证书。附件上传完毕后才公开 Release；失败时请检查 Actions 日志，若留下草稿，可在草稿中继续处理。
