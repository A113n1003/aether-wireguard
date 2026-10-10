import Foundation
import Darwin

public struct WGPeer: Sendable {
    public let publicKey: String
    public let endpoint: String?
    public let allowedIPs: [String]
    public let presharedKey: String?
    public let persistentKeepalive: UInt16?
}

public enum WGConfigurationError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// 只接受 WireGuard 数据字段。配置中的任何命令或扩展字段都不会被执行。
public struct WGConfiguration: Sendable {
    public let canonicalText: String
    public let addresses: [String]
    public let dns: [String]
    public let peers: [WGPeer]

    public var addressSummary: String { addresses.joined(separator: ", ") }
    public var endpointSummary: String {
        peers.compactMap(\.endpoint).joined(separator: ", ").nonempty ?? "未设置 Endpoint"
    }
    public var routeSummary: String {
        let routes = peers.flatMap(\.allowedIPs)
        return routes.contains("0.0.0.0/0") || routes.contains("::/0")
            ? "包含默认路由 · \(routes.count) 条路由" : "分流 · \(routes.count) 条路由"
    }
    public var maskedText: String {
        canonicalText.components(separatedBy: "\n").map { line in
            if line.hasPrefix("PrivateKey =") { return "PrivateKey = <已隐藏>" }
            if line.hasPrefix("PresharedKey =") { return "PresharedKey = <已隐藏>" }
            return line
        }.joined(separator: "\n")
    }
    public var warnings: [String] {
        peers.enumerated().compactMap { index, peer in
            peer.endpoint == nil ? "Peer \(index + 1) 未设置 Endpoint；只有在对端先联系本机后才能建立连接。" : nil
        }
    }

    public init(text: String) throws {
        guard text.utf8.count <= 65_536 else { throw WGConfigurationError.invalid("配置超过 64 KB。") }
        let interfaceKeys = Set(["PrivateKey", "Address", "DNS", "MTU", "ListenPort"])
        let peerKeys = Set(["PublicKey", "PresharedKey", "Endpoint", "AllowedIPs", "PersistentKeepalive"])
        var interface: [String: String] = [:]
        var peerFields: [[String: String]] = []
        var section: Int? = nil // -1 为 Interface，其余为 Peer 索引。
        var hasInterface = false
        for (offset, original) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = String(original.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard line.utf8.count <= 4096 else { throw WGConfigurationError.invalid("第 \(lineNumber) 行过长。") }
            if line == "[Interface]" {
                guard !hasInterface, peerFields.isEmpty else { throw WGConfigurationError.invalid("只能有一个 Interface，且必须放在 Peer 之前。") }
                hasInterface = true
                section = -1
                continue
            }
            if line == "[Peer]" {
                guard hasInterface else { throw WGConfigurationError.invalid("请先添加 [Interface]。") }
                peerFields.append([:])
                section = peerFields.count - 1
                continue
            }
            guard let section, let equal = line.firstIndex(of: "=") else {
                throw WGConfigurationError.invalid("第 \(lineNumber) 行格式无效，应为字段 = 值。")
            }
            let key = line[..<equal].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { throw WGConfigurationError.invalid("第 \(lineNumber) 行字段不能为空。") }
            guard (section == -1 ? interfaceKeys : peerKeys).contains(key) else {
                throw WGConfigurationError.invalid("第 \(lineNumber) 行包含不支持的字段；仅允许标准 WireGuard 数据字段，不支持命令或 hooks。")
            }
            guard (section == -1 ? interface[key] : peerFields[section][key]) == nil else {
                throw WGConfigurationError.invalid("第 \(lineNumber) 行字段 \(key) 重复；多个值请使用逗号分隔。")
            }
            if section == -1 { interface[key] = value } else { peerFields[section][key] = value }
        }
        guard hasInterface, let privateKey = interface["PrivateKey"] else {
            throw WGConfigurationError.invalid("Interface 缺少 PrivateKey。")
        }
        try Self.validateKey(privateKey, field: "PrivateKey")
        guard let addressValue = interface["Address"] else { throw WGConfigurationError.invalid("Interface 缺少 Address。") }
        addresses = try Self.list(addressValue, field: "Address")
        for address in addresses { try Self.validateCIDR(address, field: "Address") }
        dns = try interface["DNS"].map { try Self.list($0, field: "DNS") } ?? []
        for entry in dns {
            guard Self.ipFamily(entry) != nil || Self.isHostname(entry) else {
                throw WGConfigurationError.invalid("DNS 必须是有效 IP 地址或搜索域。")
            }
        }
        if let value = interface["MTU"] { try Self.validateNumber(value, range: 576...65_535, field: "MTU") }
        if let value = interface["ListenPort"] { try Self.validateNumber(value, range: 0...65_535, field: "ListenPort") }
        guard !peerFields.isEmpty else { throw WGConfigurationError.invalid("请至少添加一个 Peer。") }
        var parsedPeers: [WGPeer] = []
        var publicKeys = Set<String>()
        for (index, fields) in peerFields.enumerated() {
            guard let publicKey = fields["PublicKey"] else { throw WGConfigurationError.invalid("Peer \(index + 1) 缺少 PublicKey。") }
            try Self.validateKey(publicKey, field: "PublicKey")
            guard publicKeys.insert(publicKey).inserted else { throw WGConfigurationError.invalid("多个 Peer 使用了相同的 PublicKey。") }
            if let key = fields["PresharedKey"] { try Self.validateKey(key, field: "PresharedKey") }
            guard let allowedValue = fields["AllowedIPs"] else { throw WGConfigurationError.invalid("Peer \(index + 1) 缺少 AllowedIPs。") }
            let allowed = try Self.list(allowedValue, field: "AllowedIPs")
            for route in allowed { try Self.validateCIDR(route, field: "AllowedIPs") }
            if let endpoint = fields["Endpoint"] { try Self.validateEndpoint(endpoint) }
            let keepalive: UInt16?
            if let value = fields["PersistentKeepalive"] {
                try Self.validateNumber(value, range: 0...65_535, field: "PersistentKeepalive")
                keepalive = UInt16(value)
            } else { keepalive = nil }
            parsedPeers.append(WGPeer(publicKey: publicKey, endpoint: fields["Endpoint"], allowedIPs: allowed,
                                      presharedKey: fields["PresharedKey"], persistentKeepalive: keepalive))
        }
        peers = parsedPeers
        var lines = ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(addresses.joined(separator: ", "))"]
        if !dns.isEmpty { lines.append("DNS = \(dns.joined(separator: ", "))") }
        for key in ["MTU", "ListenPort"] { if let value = interface[key] { lines.append("\(key) = \(Int(value)!)") } }
        for peer in peers {
            lines += ["", "[Peer]", "PublicKey = \(peer.publicKey)"]
            if let value = peer.presharedKey { lines.append("PresharedKey = \(value)") }
            if let value = peer.endpoint { lines.append("Endpoint = \(value)") }
            lines.append("AllowedIPs = \(peer.allowedIPs.joined(separator: ", "))")
            if let value = peer.persistentKeepalive { lines.append("PersistentKeepalive = \(value)") }
        }
        canonicalText = lines.joined(separator: "\n") + "\n"
    }

    private static func list(_ value: String, field: String) throws -> [String] {
        let values = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else { throw WGConfigurationError.invalid("\(field) 的逗号列表包含空值。") }
        return values
    }
    private static func validateKey(_ value: String, field: String) throws {
        guard let data = Data(base64Encoded: value), data.count == 32, data.base64EncodedString() == value else {
            throw WGConfigurationError.invalid("\(field) 必须是标准 Base64 编码的 32 字节密钥。")
        }
    }
    private static func validateNumber(_ value: String, range: ClosedRange<Int>, field: String) throws {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(value), range.contains(number) else {
            throw WGConfigurationError.invalid("\(field) 必须是 \(range.lowerBound)–\(range.upperBound) 范围内的整数。")
        }
    }
    private static func ipFamily(_ value: String) -> Int? {
        var v4 = in_addr()
        var v6 = in6_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return 4 }
        if value.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 { return 6 }
        return nil
    }
    private static func validateCIDR(_ value: String, field: String) throws {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let family = ipFamily(String(parts[0])) else {
            throw WGConfigurationError.invalid("\(field) 必须包含有效 IP 地址和 CIDR 前缀。")
        }
        try validateNumber(String(parts[1]), range: 0...(family == 4 ? 32 : 128), field: field + " CIDR")
    }
    private static func isHostname(_ value: String) -> Bool {
        let name = value.hasSuffix(".") ? String(value.dropLast()) : value
        guard !name.isEmpty, name.utf8.count <= 253, !name.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else { return false }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard (1...63).contains(label.utf8.count), label.first != "-", label.last != "-" else { return false }
            return label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
    }
    private static func validateEndpoint(_ value: String) throws {
        let host: String
        let port: String
        if value.hasPrefix("[") {
            guard let end = value.firstIndex(of: "]"), value[value.index(after: end)...].hasPrefix(":"),
                  ipFamily(String(value[value.index(after: value.startIndex)..<end])) == 6 else {
                throw WGConfigurationError.invalid("IPv6 Endpoint 应为 [IPv6地址]:端口。")
            }
            host = String(value[value.index(after: value.startIndex)..<end])
            port = String(value[value.index(end, offsetBy: 2)...])
        } else {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw WGConfigurationError.invalid("Endpoint 应为主机:端口；IPv6 地址需使用方括号。") }
            host = String(parts[0]); port = String(parts[1])
            guard ipFamily(host) == 4 || isHostname(host) else { throw WGConfigurationError.invalid("Endpoint 主机名或 IP 地址无效。") }
        }
        guard !host.isEmpty else { throw WGConfigurationError.invalid("Endpoint 缺少主机。") }
        try validateNumber(port, range: 1...65_535, field: "Endpoint 端口")
    }

    /// 仅供格式预览，示例密钥和地址不能连接真实 VPN。
    public static let exampleText = """
    [Interface]
    PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
    Address = 10.8.0.2/32, fd00:8::2/128
    DNS = 1.1.1.1

    [Peer]
    PublicKey = AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 10.8.0.0/24, fd00:8::/64
    PersistentKeepalive = 25
    """
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
