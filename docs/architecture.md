# WireGuard 后端实现

`main` 分支采用 SwiftUI / AppKit 客户端、受限 `AetherService` LaunchDaemon 和独立 `AetherBridge`。后台服务调用安装时冻结的 `wg`、`wireguard-go`、`wg-quick` 与 Bash 4+，配置 utun、路由和网络服务 DNS。构建本身不提权、不修改网络，也不要求完整 Xcode 或 Network Extension entitlement。

连接服务改动尚未发布到 v0.1.0，本机安装与基本网络实测已完成，覆盖范围见 [验证记录](validation.md)。v0.1.0 使用每次操作的 AppleScript 管理员授权，不能依赖其短期缓存实现长期免密码。

## 一次设置与日常操作

首次设置需要 Apple CLT 的 `/usr/bin/python3` 和 `/opt/homebrew/bin` 中的 Homebrew 工具。应用先在用户目录构建安装内容，复制 `bash`、`wg`、`wg-quick`、`wireguard-go` 及必要的 readline / ncurses / gettext 动态库，修正库路径并生成 SHA-256 清单。系统管理员授权后，安装器将服务、Bridge、工具与策略复制到 root 管理的固定目录：

| 路径 | 用途 |
| --- | --- |
| `/Library/PrivilegedHelperTools/io.aether.wireguard/AetherService` | 受限后台服务 |
| `/Library/PrivilegedHelperTools/io.aether.wireguard/AetherBridge` | 固定隧道操作程序 |
| `/Library/PrivilegedHelperTools/io.aether.wireguard/Tools` | 冻结的工具、动态库与哈希清单 |
| `/Library/PrivilegedHelperTools/io.aether.wireguard/policy.json` | 绑定的 `allowedUID` 与 `clientRequirement` |
| `/Library/LaunchDaemons/io.aether.wireguard.service.plist` | 系统 LaunchDaemon 注册 |

日常操作使用 Mach service `io.aether.wireguard.service` 的 NSXPC 接口，仅开放 `ping`、`start`、`stop`，不接受任意 shell 命令或可执行路径。服务验证连接的实际 UID 和策略中的精确客户端 cdhash；客户端验证 root 管理的服务及其 cdhash。服务串行执行固定安装路径的 Bridge，配置输入只能来自已绑定用户的固定 runtime 目录。UUID、配置所有权与权限还会再次校验。

应用和服务使用启用 Hardened Runtime 的 ad hoc 签名。cdhash 固定一个具体版本，防止其他程序直接借用接口；它不提供 Developer ID 发布者认证，也不代表经过公证。更新或重新构建应用会改变 cdhash，需要管理员重新设置策略。安装器拒绝在 Aether 隧道或后台操作仍活动时更新；首次迁移需先断开旧 Aether 会话。旧 AppleScript 授权仅用于断开旧会话。

密码只交给 macOS，应用不保存密码；设置不写入 `NOPASSWD` 规则。冻结后的工具由 root 管理，后续 Homebrew 升级不会自动替换服务使用的版本；更新冻结工具需重新设置。公共 `.app` 不包含这些外部程序，复制在本机首次设置时完成。

## 配置、会话与统计

完整配置保存在 Keychain 的 `io.aether.wireguard` service；`~/Library/Application Support/Aether/profiles.json` 只记录名称、UUID 和创建日期。连接时将配置写入权限 `0600` 的 `~/Library/Application Support/Aether/runtime/<session UUID>.conf`，私钥不进入命令参数或日志。

Bridge 重新解析标准 WireGuard 字段，拒绝 hooks、`SaveConfig`、`Table` 等未支持扩展。它将配置复制到 root-owned `/var/run/aether-<UID>/<session UUID>/ae<短ID>.conf`，目录明确设为 `0711`，避免 launchd 的 `077` umask 阻止用户读取自己的统计；配置和 root 会话记录保持 `0600`。只允许断开已登记、属于该用户的会话；不扫描、接管或关闭其他 VPN。

创建后，通过 `wg-quick` 的 `/var/run/wireguard/<logicalName>.name` 获取实际 `utunN`。后台 monitor 每秒读取 `latest-handshakes` 和 `transfer`，输出不含密钥的 `stats.json`，权限 `0600`、owner 为调用用户。不会改变 WireGuard UAPI socket 权限，也不调用会暴露私钥的 `wg … dump`。`wg-quick` 的原始 stderr 丢弃，对外只反馈脱敏错误。

应用使用本地 `0600` 会话注册文件恢复状态；Bridge 还发布不含密钥的 `current.json` 所有权摘要，使应用本地写盘失败后仍可恢复。接口消失后 monitor 发布终止样本并清理 root 活动记录。采样失败会重试，避免删除接口与采样的竞态留下过期状态。启动部分成功且回滚未完成时，会话标记 `startupIncomplete`，保留所有权、监控和断开入口。

## 状态与网络边界

“隧道已建立”仅表示曾观测到非零握手时间戳；当前没有按握手年龄自动降级，也没有持续端到端可达性检测。诊断应结合最近握手、采样时效与实际流量。

`AllowedIPs` 决定目标路由。与其他 VPN 并存时，系统更具体的路由仍可能改变选路；Aether 不提供按应用分流。DNS 由 `wg-quick` 调整网络服务配置，不是 Network Extension 的接口作用域 DNS。断开会等待登记接口消失，DNS 恢复仍委托给 `wg-quick`，Aether 不验证恢复完成，也不提供 DNS 防泄漏或 Kill Switch 保证。

一次仅管理一个 Aether 隧道；多 Peer 可导入，统计显示 Peer 合计。当前首次设置支持 Apple Silicon 的 Homebrew 路径，Intel 未验收。普通构建和测试不安装系统服务；真实握手、路由、DNS 恢复和长期重连需另行验收。

## 卸载

先断开 Aether 隧道，再执行应用资源中的 `uninstall-helper.sh`（需要管理员权限；具体命令见 [README](../README.md)）。脚本检查固定安装目录及服务身份，仅在没有活动 Aether 会话或 Bridge 操作时删除 LaunchDaemon 与冻结工具；保留用户配置。

参考：[NSXPC 代码签名要求](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))、[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)、[WireGuard Darwin 脚本](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash)、[wg 命令格式](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8)。
