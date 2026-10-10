# 安全政策

## 支持范围

当前仅维护最新的 `0.1.x` 预发布版本。Aether 尚未接受独立安全审计，暂不承诺适合生产或高风险网络环境。

## 私下报告漏洞

请通过 [GitHub 私密漏洞报告](https://github.com/A113n1003/aether-wireguard/security/advisories/new) 提交。

请写明受影响的版本、前置条件、最小复现与影响范围。不要在公开 Issue 中附带 PrivateKey、PresharedKey、完整配置、管理员密码或未脱敏日志。普通界面和文档问题可走 Issue。

维护者会在可用时确认并跟进报告；当前没有固定响应 SLA。修复与发布说明会尽量说明影响版本、根因和验证范围。

## 当前信任边界

- `main` 分支首次设置需系统管理员授权安装受限 LaunchDaemon；日常连接与断开使用 NSXPC，不保存密码、不配置 `NOPASSWD`。此变更尚未发布到 v0.1.0，本机安装、免密码开关、重启恢复及未授权客户端拒绝已验证；见 [验证记录](docs/validation.md)。
- 服务只接受安装时绑定的本机 UID 与精确客户端 cdhash，客户端也验证 root 管理的服务 cdhash。接口仅开放 `ping` / `start` / `stop`，不接受任意 shell 命令或可执行路径。
- 服务、Bridge、策略及冻结工具位于 root 管理的固定目录，不能由普通用户替换。首次设置仍需信任应用包与本机 Homebrew 工具来源；ad hoc 签名提供具体代码版本绑定，不提供 Developer ID 来源认证。
- 更新或重新构建客户端后需重新管理员授权设置；安装或卸载前须断开 Aether 隧道。冻结工具不会随 Homebrew 自动升级，更新工具需重新设置。旧 AppleScript 授权仅保留用于断开旧会话。
- 配置保存在本机 Keychain；helper 操作期间会使用权限 `0600` 的配置文件。
- 不执行 WireGuard 配置中的 shell hooks；拒绝 `SaveConfig`、`Table` 等未支持扩展。
- 统计读取 `transfer` 和 `latest-handshakes`，不使用会包含秘密的 `dump`。
- “隧道已建立”仅表示曾观测到握手，当前不按握手年龄降级，也不验证持续端到端可达性。
- DNS 由 `wg-quick` 更改网络服务级配置；没有 DNS 防泄漏或 Kill Switch 保证。
- Release 目前使用 ad hoc 签名，未经过 Developer ID 签名和 notarization。

数据流、临时文件与会话边界见 [架构文档](docs/architecture.md)。上述设计约束不是完整安全审计结论。
