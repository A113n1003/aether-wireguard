# 第三方依赖与致谢

Aether 原创源码与图标采用 [MIT](LICENSE)。本仓库和 `.app` 不打包外部 WireGuard/Bash 可执行文件，运行时由用户通过 Homebrew 安装。

| 组件 | 用途 | 上游许可证 / 来源 |
| --- | --- | --- |
| wireguard-tools | `wg` 统计、`wg-quick` 配置隧道、路由与 DNS | [GPL-2.0](https://git.zx2c4.com/wireguard-tools/tree/COPYING) |
| wireguard-go | Darwin 用户态 WireGuard 实现 | [MIT](https://github.com/WireGuard/wireguard-go/blob/master/LICENSE) |
| GNU Bash | 运行 Darwin `wg-quick` | [GNU 项目](https://www.gnu.org/software/bash/)；以实际安装版本的许可证为准 |
| SwiftUI / AppKit / Security | 原生界面、应用生命周期、Keychain | Apple SDK，自行安装开发工具；本仓库不再分发 SDK |
| SF Symbols | 系统符号 | 通过系统 API 显示；本仓库不打包符号素材 |

WireGuard 是其权利人的商标。Aether 是独立社区客户端，与 WireGuard 官方没有隶属或背书关系。MIT 许可不改变上游组件的许可证或商标权利。
