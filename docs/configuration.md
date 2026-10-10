# 配置说明

Aether 只接受标准 WireGuard 数据字段，不执行配置内的命令。导入会规范化字段、空白和数字；注释不会保留。

## 支持字段

| Section | 字段 | 说明 |
| --- | --- | --- |
| Interface | `PrivateKey` | 必填，32 字节标准 Base64 |
| Interface | `Address` | 必填，IPv4/IPv6 CIDR，多个值逗号分隔 |
| Interface | `DNS` | 可选，IP 或搜索域列表 |
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
