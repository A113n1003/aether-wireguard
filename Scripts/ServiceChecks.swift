import Foundation
import Darwin
import AetherCore

func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError(description) }
    print("PASS: \(description)")
}
let hash = Data(repeating: 0xab, count: 20)
let pin = try ServiceIdentity.requirement(hash: hash, identifier: "io.aether.wireguard")
check(pin == "identifier \"io.aether.wireguard\" and cdhash H\"\(String(repeating: "ab", count: 20))\"", "pin uses complete exact cdhash")
for (bytes, identifier) in [(Data(), "io.aether.wireguard"), (Data(repeating: 1, count: 32), "io.aether.wireguard"), (hash, "io.aether.wireguard\" or true")] {
    do { _ = try ServiceIdentity.requirement(hash: bytes, identifier: identifier); fatalError("invalid signing identity accepted") } catch {}
}
check(true, "malformed hash and requirement injection rejected")
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AetherServiceChecks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: folder) }
let file = folder.appendingPathComponent("file"), link = folder.appendingPathComponent("link")
try Data("inert".utf8).write(to: file)
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/ls"))
for path in [file, link] {
    do { try ServiceIdentity.checkRootOwnership(path); fatalError("unsafe installed path accepted") } catch {}
}
check(true, "user-owned and symlink installed paths rejected")
let own = URL(fileURLWithPath: CommandLine.arguments[0])
do { _ = try ServiceIdentity.requirement(for: own, identifier: "io.aether.wireguard"); fatalError("foreign client accepted") } catch {}
check(true, "unsigned or foreign executable cannot impersonate client")
if CommandLine.arguments.count == 3 {
    for (path, identifier) in [(CommandLine.arguments[1], "io.aether.wireguard"), (CommandLine.arguments[2], PrivilegedServiceLocation.name)] {
        let requirement = try ServiceIdentity.requirement(for: URL(fileURLWithPath: path), identifier: identifier)
        check(requirement.hasPrefix("identifier \"\(identifier)\" and cdhash H\""), "built hardened identity validates: \(identifier)")
    }
}
