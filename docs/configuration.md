# 配置说明

Aether 只接受标准 WireGuard 数据字段，不执行配置内的命令。导入会规范化字段、空白和数字；注释不会保留。

## 支持字段

| Section | 字段 | 说明 |
| --- | --- | --- |
| Interface | `PrivateKey` | 必填，32 字节标准 Base64 |
| Interface | `Address` | 必填，IPv4/IPv6 CIDR，多个值逗号分隔 |
| Interface | `DNS` | 可选，IP 或搜索域列表；需在偏好设置开启「使用隧道 DNS」才会应用 |
| Interface | `MTU` | 可选，576–65535 |
| Interface | `ListenPort` | 可选，0–65535 |
| Peer | `PublicKey` | 必填，32 字节标准 Base64，各 Peer 不可重复 |
| Peer | `PresharedKey` | 可选，32 字节标准 Base64 |
| Peer | `Endpoint` | 可选，`主机:端口`；IPv6 用 `[地址]:端口` |
| Peer | `AllowedIPs` | 必填，IPv4/IPv6 CIDR 列表 |
| Peer | `PersistentKeepalive` | 可选，0–65535 |

只允许一个 Interface 且必须在 Peer 之前，至少一个 Peer。配置上限为 64 KB，单行上限为 4096 字节；同一 section 不允许重复字段。多值使用逗号列表。

`AllowedIPs = 0.0.0.0/0, ::/0` 表示包含 IPv4 与 IPv6 默认路由；只写特定网段则交给 `wg-quick` 建立对应路由。最终选路还受系统其他接口与路由影响，Aether 当前没有按应用规则。

## 示例结构

以下占位符不可直接保存或用于连接；应替换为自己的有效配置：

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 192.0.2.2/32
DNS = 192.0.2.1

[Peer]
PublicKey = <server-public-key>
Endpoint = vpn.example.com:51820
AllowedIPs = 192.0.2.0/24
PersistentKeepalive = 25
```

应用内「查看格式示例」使用虚构密钥和保留域名，仅用于预览。真实模式拒绝直接保存内置示例。

## 编辑行为

基本表单仅适合单 Peer 的基础字段。导入多 Peer、MTU、ListenPort、PersistentKeepalive 或其他不能安全回填的字段时，使用原文编辑，避免字段丢失。

配置原文默认隐藏秘密；「显示密钥并编辑」会展示完整内容，请在本机私密环境使用。截图、Issue 和日志附件不得包含 PrivateKey 或 PresharedKey。

以下扩展被明确拒绝：`PreUp`、`PostUp`、`PreDown`、`PostDown`、`SaveConfig`、`Table`，以及所有未知字段。

## 已创建接口，但无法访问

接口创建、WireGuard 握手、目标地址可达是三个不同的检查。WireGuard 在有待发送流量时才主动握手；没有流量且未设 `PersistentKeepalive` 时，暂时没有握手不能直接判定密钥或服务器有误。需要 NAT 保活时可按用途设置 `PersistentKeepalive = 25`，它不会修复路由覆盖。

多个 VPN 并存时，`AllowedIPs = 0.0.0.0/0` 不保证所有 IPv4 流量实际进入本隧道。系统已有的更具体网段或主机路由可能优先；DNS 地址也可能被现有主机路由送往物理网卡。使用诊断面板确认 Aether 的实际 `utunN`，然后在本机查看选路：

```bash
route -n get <目标 IP>
route -n get <配置中的 DNS IP>
route -n get <Endpoint 解析后的 IP>
```

业务地址和隧道 DNS 应进入期望接口；Endpoint 的外层 UDP 应有可达的隧道外路径。不要将 UDP `nc` 发送成功当作服务器回应。

绑定 Aether 接口探测可区分隧道能力与普通选路，例如 `ping -b utunN -c 3 <隧道内地址>`。若绑定探测获得握手和响应、普通访问失败，应检查路由覆盖或 DNS，而不是重新生成密钥。绑定探测成功不代表默认路由已修复。

修复取决于用途：只访问远端 LAN 时，明确目标网段后使用分流配置；要求全局连接时，协调其他 VPN 的路由策略。Aether 不应自动删除其他 VPN 的路由或退出其他客户端。

## 控制隧道 DNS

当前源码版本在「偏好设置 → 使用隧道 DNS」提供全局开关，默认关闭。关闭时，连接用的配置副本会移除 `DNS` 字段，`wg-quick` 不会据此更改 macOS DNS 服务器或搜索域；导入及钥匙串中保存的原配置保持完整。开启后才使用配置中的 DNS。切换设置不影响活动连接，重新连接后生效。

此设置不更改 `AllowedIPs`，也不阻止其他 VPN、DHCP 或系统服务修改 DNS。公开旧 Release 不一定包含该入口。
