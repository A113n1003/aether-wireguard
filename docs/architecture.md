# WireGuard 后端实现

当前版本使用原生 Swift 应用和独立 `AetherBridge`，调用 Apple Silicon Mac 安装在 `/opt/homebrew/bin` 的 Homebrew `wg`、`wireguard-go`、`wg-quick` 和 Bash 4+。它具有真实隧道操作接口；没有有效配置时不会自动连接。构建不要求完整 Xcode 或 Network Extension entitlement。

## 权限与数据

连接、断开由系统 `do shell script … with administrator privileges` 授权。系统密码只交给 macOS，应用不保存密码。每个操作只允许 `start`、`stop` 或内部 `monitor`；参数分别进行 shell quoting 与 AppleScript 字符串转义，私钥不进入参数或日志。

应用将配置写入权限 `0600` 的临时输入文件。helper 再解析一次标准 WireGuard 字段，拒绝 hooks、`SaveConfig` 等扩展，复制到 root-owned `/var/run/aether-<UID>/<session UUID>/ae<短ID>.conf`。目录 `0711`，配置和会话记录 `0600`。helper 只断开此处注册的会话，不扫描、接管或关闭其他 VPN。

创建后使用 `wg-quick` 的 `/var/run/wireguard/<logicalName>.name` 读取实际 `utunN`。monitor 每秒读取 `latest-handshakes` 和 `transfer`，输出不含密钥的 `stats.json`，文件权限 `0600` 且 owner 为调用用户。不会改变 WireGuard UAPI socket 权限，不调用会暴露私钥的 `wg … dump`。`wg-quick` 的原始 stderr 无条件丢弃，对外只反馈脱敏错误。

主应用使用本地权限 `0600` 会话注册文件恢复状态；helper 另外发布不含密钥、权限 `0600` 的 `current.json` 所有权摘要，应用本地写盘失败也可以恢复。接口消失后 monitor 发布终止样本并清理 root 活动记录，应用读到终止样本会解除当前会话。单次采样失败会重试，避免接口删除与采样竞态留下永久过期状态。

授权和命令通过后台 Task 执行，不阻塞主线程。接口创建成功与远端握手成功是不同状态；速率应由真实计数差分计算，握手为零表示等待握手。启动部分成功且自动回滚未完成时，会话标记 `startupIncomplete`，保留真实所有权、持续监控与断开入口，界面应显示“启动未完成，请断开”。

## 状态语义

“隧道已建立”仅表示观测到非零握手时间戳，当前没有按握手年龄自动降级，也没有持续端到端可达性检测。旧握手仍可能显示此状态；诊断应结合握手时间、采样时效与实际流量。

断开时 helper 等待已登记接口消失；DNS 恢复委托给 `wg-quick` 的系统服务监控，Aether 当前不验证恢复完成。不能将断开成功当作 DNS 防泄漏证明。

## 使用限制

- 本版依赖 `/opt/homebrew/bin/`，适用于当前 Apple Silicon Mac；不是完全自包含的分发包。
- Bash 必须使用 Homebrew 版本，macOS `/bin/bash` 3.2 不满足 `wg-quick` 要求。
- `wg-quick` 根据 `AllowedIPs` 配置系统路由，通过 `networksetup` 设置并恢复网络服务 DNS；这不是 Network Extension 的接口作用域 DNS。
- 应用及 Homebrew 工具位于用户可修改位置；管理员授权的信任边界包含这些文件的完整性，当前没有安装级已签名 privileged helper。
- 一次仅管理一个 Aether 隧道。多 peer 配置可导入，统计显示 peer 合计。
- 普通界面测试、单元测试和构建不执行提权操作。真实服务器握手、路由和 DNS 恢复需要有效 WG 配置与用户触发连接后验证。
- 正式独立分发可以封装已签名依赖，或迁移为 WireGuardKit + Packet Tunnel Extension；后者需要匹配的 Apple 签名及 Network Extension 配置。

参考：[WireGuard Darwin 脚本](https://git.zx2c4.com/wireguard-tools/tree/src/wg-quick/darwin.bash)、[wg 命令格式](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8)、[WireGuardKit](https://github.com/WireGuard/wireguard-apple)、[Apple Network Extension entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)。
