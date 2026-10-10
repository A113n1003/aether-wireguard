# 安全政策

## 支持范围

当前仅维护最新的 `0.1.x` 预发布版本。Aether 尚未接受独立安全审计，暂不承诺适合生产或高风险网络环境。

## 私下报告漏洞

请通过 [GitHub 私密漏洞报告](https://github.com/A113n1003/aether-wireguard/security/advisories/new) 提交。

请写明受影响的版本、前置条件、最小复现与影响范围。不要在公开 Issue 中附带 PrivateKey、PresharedKey、完整配置、管理员密码或未脱敏日志。普通界面和文档问题可走 Issue。

维护者会在可用时确认并跟进报告；当前没有固定响应 SLA。修复与发布说明会尽量说明影响版本、根因和验证范围。

## 当前信任边界

- 连接和断开需要 macOS 管理员授权；应用不接收或保存管理员密码。
- 开发版通过应用内 `AetherBridge` 调用本机 Homebrew 工具。授权意味着信任该 `.app` 和这些本地工具；当前没有已签名的安装级 privileged helper。
- 配置保存在本机 Keychain；helper 操作期间会使用权限 `0600` 的配置文件。
- 不执行 WireGuard 配置中的 shell hooks；拒绝 `SaveConfig`、`Table` 等未支持扩展。
- 统计读取 `transfer` 和 `latest-handshakes`，不使用会包含秘密的 `dump`。
- “隧道已建立”仅表示曾观测到握手，当前不按握手年龄降级，也不验证持续端到端可达性。
- DNS 由 `wg-quick` 更改网络服务级配置；没有 DNS 防泄漏或 Kill Switch 保证。
- Release 目前使用 ad hoc 签名，未经过 Developer ID 签名和 notarization。

数据流、临时文件与会话边界见 [架构文档](docs/architecture.md)。上述设计约束不是完整安全审计结论。
