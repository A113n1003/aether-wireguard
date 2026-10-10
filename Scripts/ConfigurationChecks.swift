import Foundation
import AetherCore
struct Failure: Error {}
func check(_ value: @autoclosure () throws -> Bool) throws {
    if try !value() { throw Failure() }
}
func rejects(_ text: String) throws {
    do { _ = try WGConfiguration(text: text) } catch { return }
    throw Failure()
}
let valid = WGConfiguration.exampleText
var cases: [(String, () throws -> Void)] = []
cases.append(("canonical round trip", {
    let config = try WGConfiguration(text: valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: "DNS = 1.1.1.1, fd00::53, corp.example\nMTU = 1420\nListenPort = 51821"))
    try check(WGConfiguration(text: config.canonicalText).canonicalText == config.canonicalText)
    try check(config.dns.count == 3)
    try check(config.canonicalText.contains("MTU = 1420"))
}))
cases.append(("reject command fields and injection", {
    for line in ["PostUp = touch /tmp/injected", "PreDown = $(id)", "Table = auto", "SaveConfig = true", "Unknown = anything"] {
        try rejects(valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: line))
    }
    for host in ["vpn.example.com:51820;id", "$(id):51820"] {
        try rejects(valid.replacingOccurrences(of: "vpn.example.com:51820", with: host))
    }
}))
cases.append(("reject duplicates and invalid keys", {
    try rejects(valid + "\nPersistentKeepalive = 30")
    try rejects(valid.replacingOccurrences(of: "[Peer]", with: "[Interface]\n[Peer]"))
    for key in ["AAAA", "not-base64"] {
        try rejects(valid.replacingOccurrences(of: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", with: key))
    }
}))
cases.append(("multiple peers and endpoint warning", {
    let key = Data(repeating: 2, count: 32).base64EncodedString()
    let config = try WGConfiguration(text: valid + "\n[Peer]\nPublicKey = \(key)\nAllowedIPs = 192.168.50.0/24\n")
    try check(config.peers.count == 2)
    try check(config.warnings.count == 1)
    try check(config.peers[1].endpoint == nil)
}))
cases.append(("secret masking", {
    let key = Data(repeating: 3, count: 32).base64EncodedString()
    let config = try WGConfiguration(text: valid + "\nPresharedKey = \(key)")
    try check(!config.maskedText.contains(key))
    try check(!config.maskedText.contains("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
    try check(config.maskedText.contains(config.peers[0].publicKey))
    try check(config.canonicalText.contains(key))
}))
cases.append(("IPv6 endpoints and prefix boundaries", {
    let source = valid.replacingOccurrences(of: "vpn.example.com:51820", with: "[2001:db8::1]:65535")
    try check(WGConfiguration(text: source).peers[0].endpoint == "[2001:db8::1]:65535")
    for value in ["[2001:db8:::1]:51820", "2001:db8::1:51820", "[2001:db8::1]:0", "[2001:db8::1]:65536", "[2001:db8::1]:"] {
        try rejects(valid.replacingOccurrences(of: "vpn.example.com:51820", with: value))
    }
    for value in ["fd00:8::2/129", "fd00:8:::2/128", "10.8.0.2/33", "999.8.0.2/32"] {
        try rejects(valid.replacingOccurrences(of: "10.8.0.2/32, fd00:8::2/128", with: value))
    }
    _ = try WGConfiguration(text: valid.replacingOccurrences(of: "10.8.0.0/24, fd00:8::/64", with: "0.0.0.0/0, ::/0"))
}))
cases.append(("empty lists and invalid numbers", {
    try rejects(valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: "DNS = 1.1.1.1,"))
    try rejects(valid.replacingOccurrences(of: "PersistentKeepalive = 25", with: "PersistentKeepalive = -1"))
    try rejects(valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: "MTU = 575"))
}))
cases.append(("error descriptions do not leak secret", {
    let secret = "sensitive-invalid-key-material"
    do {
        _ = try WGConfiguration(text: valid.replacingOccurrences(of: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", with: secret))
        throw Failure()
    } catch {
        try check(!error.localizedDescription.contains(secret))
    }
}))
var failures = 0
for (name, run) in cases {
    do { try run(); print("PASS: \(name)") }
    catch { failures += 1; print("FAIL: \(name)") }
}
print("\(cases.count - failures)/\(cases.count) cases passed")
exit(failures == 0 ? 0 : 1)
