<p align="center">
  <img src="docs/assets/icon.png" width="88" alt="Aether 图标">
</p>
<h1 align="center">Aether</h1>
<p align="center">macOS 原生 WireGuard 客户端</p>
<p align="center">
  <a href="https://github.com/A113n1003/aether-wireguard/actions/workflows/ci.yml"><img src="https://github.com/A113n1003/aether-wireguard/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/A113n1003/aether-wireguard/releases"><img src="https://img.shields.io/github/v/release/A113n1003/aether-wireguard?include_prereleases" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111720" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-70e7f5" alt="MIT"></a>
</p>
<p align="center"><a href="README.en.md">English</a> · <a href="https://github.com/A113n1003/aether-wireguard/releases">下载</a> · <a href="docs/architecture.md">架构</a> · <a href="CONTRIBUTING.md">参与贡献</a></p>

Aether 使用 SwiftUI + AppKit，直接导入已有 WireGuard 配置，为主窗口和菜单栏连接面板提供一致的连接状态、隧道切换和流量信息。无需账号或订阅；本应用没有分析遥测或云端配置服务。

> **v0.1.0 为开发预发布。** 安装包仅支持 Apple Silicon / macOS 14+，依赖 Homebrew WireGuard 工具；使用 ad hoc 签名，尚未做 Developer ID 签名或公证。真实网络端到端验收仍待完成。当前发行边界见下文与 [安全政策](SECURITY.md)。

## 界面预览

以下图片由实际 SwiftUI 组件在 `--demo` 下离屏渲染，使用虚构配置与模拟流量，不代表真实网络已连接。

![Aether 主窗口](docs/assets/main-window.png)

<p align="center">
  <img src="docs/assets/menu-bar.png" width="288" alt="菜单栏连接面板">
  <img src="docs/assets/preferences.png" width="448" alt="偏好设置">
</p>

## 已实现

- **主窗口与菜单栏面板**：原生 `NSPopover`，连接光环、状态、实时流量和隧道列表共享同一数据源。
- **三种配置入口**：导入 `.conf`、粘贴原文、单 Peer 表单。多 Peer / 高级字段使用原文编辑，避免表单丢字段。
- **系统 Keychain**：完整配置存于本机钥匙串，磁盘索引仅含名称、UUID 和创建日期；密钥默认隐藏。
- **隧道生命周期**：系统管理员授权、连接 / 取消 / 断开、配置切换确认、应用重启后的已登记会话恢复。
- **连接信息**：真实 WireGuard 收发计数、握手时间、接口 / 路由 / DNS 摘要、最近 60 秒流量图与脱敏事件日志。
- **桌面交互**：背景拖动、自定义关闭按钮、键盘快捷键；关闭主窗口后保留菜单栏。

当前一次管理一个活动隧道。Aether 是独立社区项目，与 WireGuard 官方没有隶属关系。

## 安装

### 运行要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 14 或更新版本 |
| 发行架构 | Apple Silicon (`arm64`) |
| WireGuard 运行时 | Homebrew `bash`、`wireguard-tools`、`wireguard-go` |
| 工具路径 | `/opt/homebrew/bin`；当前 Intel Homebrew 路径不受支持 |
| 服务端 | 自己有权使用的有效 WireGuard 配置；Aether 不提供 VPN 服务 |

已安装 [Homebrew](https://brew.sh/) 后，先安装运行时依赖：

```bash
brew install bash wireguard-tools wireguard-go
```

macOS 自带 Bash 3.2 不满足 Darwin `wg-quick` 的要求，因此使用 Homebrew Bash 4+。

### 下载 Release

1. 打开 [Releases](https://github.com/A113n1003/aether-wireguard/releases)，下载 `Aether-v0.1.0-macos-arm64.zip` 和 `SHA256SUMS`。
2. 将两个文件放在同一目录，校验：

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

3. 解压，将 `Aether.app` 拷贝到 `/Applications`，打开应用。
4. 点击「添加隧道」或「导入配置」，保存自己的配置，再点击连接。
5. 连接 / 断开时由 macOS 请求管理员授权。密码只交给系统，应用不保存密码。

当前安装包未公证，Gatekeeper 可能阻止打开。该发行版不提供通过安全来源验证的 Developer ID 签名；若不接受这一边界，可按下一节审阅并自行构建源码。不要全局关闭 Gatekeeper。

## 从源码构建

需要 Swift 6+、macOS SDK 和 Python 3；可以使用完整 Xcode，或提供相应 Swift/SDK 的 Command Line Tools。构建本身不要求 WireGuard 运行时，不安装依赖、不提权、不修改网络。

```bash
git clone https://github.com/A113n1003/aether-wireguard.git
cd aether-wireguard
./Scripts/check.sh
./Scripts/build.sh
open dist/Aether.app
```

`dist/Aether.app` 是本地 ad hoc 签名应用。版本来自 `VERSION`；`BUILD_NUMBER` 可设置 bundle build number。

```bash
# 生成带 SHA-256 的 Apple Silicon Release 包
./Scripts/release.sh

# 无网络副作用的交互演示，仅用于开发测试
dist/Aether.app/Contents/MacOS/Aether --demo
```

演示模式不创建网卡，不读写真实配置，显示明确演示标记。正常偏好设置只保留「菜单栏实时速率」「减少动态效果」两个开关，修改自动保存。

完整 Xcode 下还可运行：

```bash
swift test
```

若本机 CLT 缺少 XCTest 或 SwiftPM `BuildServerProtocol.framework`，使用 `Scripts/check.sh` 执行 18 项独立断言，覆盖配置解析 / 规范化 / 脱敏、命令转义、统计聚合、会话校验与兼容。独立检查不替代实际执行 XCTest；CI 在完整 Xcode 中同时运行两者。

## 使用与快捷键

`AllowedIPs` 决定进入隧道的目标网段；设置 `0.0.0.0/0` 或 `::/0` 会包含相应默认路由。Aether 不提供按应用分流。支持字段与示例见 [配置说明](docs/configuration.md)。

| 快捷键 | 操作 |
| --- | --- |
| `⌘O` | 导入配置 |
| `⌘D` | 连接 / 断开 |
| `⌘⇧M` | 打开菜单栏连接面板 |
| `⌘1` / `⌘W` | 打开 / 关闭主窗口 |
| `⌘L` | 连接诊断 |
| `⌘,` | 偏好设置 |
| `⌘Q` | 退出；活动隧道可选择断开或保留 |

“等待对端握手”表示接口已启动但未观测到握手。“隧道已建立”表示曾读取到握手时间，**不保证当前端到端可达性**；应结合最近握手时间和流量判断。

## 架构与数据

```mermaid
flowchart LR
    UI[SwiftUI 主窗口 / 菜单栏] --> Store[AppStore]
    Store --> Keychain[系统 Keychain]
    Store --> Engine[WireGuardEngine]
    Engine --> Auth[macOS 管理员授权]
    Auth --> Bridge[AetherBridge]
    Bridge --> Tools[wg-quick / wg / wireguard-go]
    Tools --> Network[utun / 系统路由 / DNS]
    Bridge --> Stats[脱敏统计文件]
    Stats --> Store
```

| 目录 | 内容 |
| --- | --- |
| `Sources/AetherApp` | SwiftUI / AppKit 界面、状态和生命周期 |
| `Sources/AetherCore` | 配置解析、Keychain、后端与统计 |
| `Sources/AetherBridge` | 授权后的会话操作与后台统计 |
| `Tests/AetherCoreTests` | XCTest 回归测试 |
| `Scripts` | 无第三方 Swift 包的构建、检查与打包工具 |
| `.github/workflows` | CI、tag 构建与预发布 |
| `docs` | 配置、架构、发布、路线图 |

完整配置保存在 Keychain 的 `io.aether.wireguard` service；用户索引位于 `~/Library/Application Support/Aether/profiles.json`。操作期间 helper 使用权限 `0600` 的配置文件。更多权限、运行目录和所有权约束见 [架构文档](docs/architecture.md)。

## 当前限制

- 未完成真实服务器握手、IPv4/IPv6 路由、DNS 恢复及长期重连的端到端验收。
- 路由与系统网络服务 DNS 委托给 `wg-quick`；Aether 不验证 DNS 恢复完成。
- 当前信任边界包含应用完整性和本机 Homebrew 工具；没有安装级已签名 privileged helper。
- 不包含 Kill Switch、自动连接、按应用分流、DNS 防泄漏保证或独立 NetworkExtension。
- 不执行配置 hooks，拒绝 `PreUp` / `PostUp` / `PreDown` / `PostDown` / `SaveConfig` / `Table` 等扩展。
- 当前只发布 `arm64`，未验收 Intel；没有自动更新器、App Store 发行或安装器。

## 排查问题

| 情况 | 下一步 |
| --- | --- |
| 缺少工具 | 检查 `brew install bash wireguard-tools wireguard-go` 与 `/opt/homebrew/bin` |
| 钥匙串不可访问 | 解锁登录钥匙串，查看系统提示后重试 |
| 等待握手 | 检查配置、服务器、UDP 连通和时间；接口启动不等于服务端响应 |
| 配置导入失败 | 查看就地错误；检查必填字段、32 字节 Base64 密钥、CIDR、IPv6 Endpoint 格式及不支持的 hooks |
| 断开未完成 | 查看「诊断与日志」，保留失败状态并重试；不要按接口号删除其他 VPN 的网卡 |
| 普通 Bug | 提交 [Issue](https://github.com/A113n1003/aether-wireguard/issues/new/choose)，只附脱敏信息 |
| 安全问题 | 按 [SECURITY.md](SECURITY.md) 私下报告 |

## 参与与许可证

请先阅读 [贡献指南](CONTRIBUTING.md) 与 [行为准则](CODE_OF_CONDUCT.md)。当前优先补齐真实网络验收、权限边界和发行签名；后续方向见 [路线图](docs/roadmap.md)。

原创源码和图标采用 [MIT](LICENSE)。外部 WireGuard/Bash 工具使用各自的许可证，Release 不打包这些程序；见 [第三方说明](THIRD_PARTY_NOTICES.md)。
