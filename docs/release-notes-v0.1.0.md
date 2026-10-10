Aether v0.1.0 是首个公开开发预发布版本，为 macOS 提供 SwiftUI/AppKit WireGuard 主窗口与菜单栏连接面板。

### 已包含

- 文件、粘贴与表单配置录入，Keychain 存储，多 Peer 原文保留。
- Homebrew WireGuard 后端、系统授权、握手与真实流量统计、会话恢复。
- 配置切换、连接/取消/断开、脱敏诊断、快捷键和界面偏好设置。
- 原生菜单栏弹窗与小型自定义关闭按钮。

### 下载与安装

下载 `Aether-v0.1.0-macos-arm64.zip` 与 `SHA256SUMS`，在同一目录运行 `shasum -a 256 -c SHA256SUMS`，解压后将 `Aether.app` 拷贝到 Applications。

要求 Apple Silicon / macOS 14+。连接前安装依赖：

```bash
brew install bash wireguard-tools wireguard-go
```

仅使用自己有权管理的有效 WireGuard 配置。安装步骤、故障排查和快捷键见仓库 README。

### 当前边界

开发预发布版使用 ad hoc 签名，未做 Developer ID 签名或 notarization；运行时依赖 `/opt/homebrew/bin` 的 Homebrew 工具。连接和断开均需要系统管理员授权，路由与 DNS 由 `wg-quick` 管理。

已验证本地构建、签名、配置/统计解析和原生界面。真实服务器握手、路由与 DNS 恢复、长期重连尚未完成端到端验收。不包含 Kill Switch、自动连接、按应用分流或独立 NetworkExtension。

`.app` 只包含 Aether 和 AetherBridge，不包含 WireGuard/Bash 可执行文件。完整源码与 MIT 许可证随仓库提供，第三方工具使用各自上游许可证。
