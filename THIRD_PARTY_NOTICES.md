# 第三方依赖与致谢

Aether 原创源码与图标采用 [MIT](LICENSE)。公共仓库和 Release `.app` 不打包外部 WireGuard/Bash 可执行文件或其动态库。用户通过 Homebrew 安装运行时；源码版首次设置连接服务时，将本机工具及必要库复制到 root 管理的目录，避免后续以管理员权限执行用户可替换的 Homebrew 文件。

| 组件 | 用途 | 上游许可证 / 来源 |
| --- | --- | --- |
| wireguard-tools | `wg` 统计、`wg-quick` 配置隧道、路由与 DNS | [GPL-2.0](https://git.zx2c4.com/wireguard-tools/tree/COPYING) |
| wireguard-go | Darwin 用户态 WireGuard 实现 | [MIT](https://github.com/WireGuard/wireguard-go/blob/master/LICENSE) |
| GNU Bash | 运行 Darwin `wg-quick` | [GNU Bash](https://www.gnu.org/software/bash/)；以本机实际版本许可证为准 |
| GNU Readline | Bash 的 readline / history 动态库 | [GNU Readline](https://www.gnu.org/software/readline/)；以本机实际版本许可证为准 |
| ncurses | Bash / Readline 的终端动态库 | [ncurses 许可证](https://invisible-island.net/ncurses/ncurses-license.html) |
| GNU gettext | Bash 所需 gettext 动态库 | [GNU gettext](https://www.gnu.org/software/gettext/)；以具体库和本机版本许可证为准 |
| SwiftUI / AppKit / Security | 原生界面、生命周期、Keychain 与代码签名校验 | Apple SDK，自行安装开发工具；本仓库不再分发 SDK |
| SF Symbols | 系统符号 | 通过系统 API 显示；本仓库不打包符号素材 |

本机冻结过程修改 `wg-quick` 的工具路径及配置搜索行为，并修正 Bash 动态库的加载路径；这些副本仍适用各自上游许可证。若另行分发冻结的 Tools 或包含这些工具的安装包，须单独履行各组件的版权、许可证及对应源码提供义务，不能仅使用 Aether 的 MIT 许可。当前发布脚本不分发 Tools。

WireGuard 是其权利人的商标。Aether 是独立社区客户端，与 WireGuard 官方没有隶属或背书关系。MIT 许可不改变上游组件的许可证或商标权利。
