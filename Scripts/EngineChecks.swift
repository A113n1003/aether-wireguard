import Foundation
import AetherCore

func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError(description) }
    print("PASS: \(description)")
}
let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
check(EngineUtilities.logicalName(for: id) == "aeabcdef0123", "stable Darwin interface name")
let result = EngineUtilities.parseStatistics(interfaceName: "utun42", transfers: "peer1\t100\t20\npeer2\t300\t40", handshakes: "peer1\t0\npeer2\t1700000000", now: Date(timeIntervalSince1970: 1_700_000_010))
check(result.rxBytes == 400 && result.txBytes == 60, "aggregate peer counters")
check(result.latestHandshake == Date(timeIntervalSince1970: 1_700_000_000), "latest real handshake")
let waiting = EngineUtilities.parseStatistics(interfaceName: "utun1", transfers: "peer\t0\t0", handshakes: "peer\t0")
check(waiting.latestHandshake == nil, "no fabricated handshake")
let overflow = EngineUtilities.parseStatistics(interfaceName: "utun1", transfers: "peer\t18446744073709551615\t2\npeer2\t1\t3\nbad\t-1\t4", handshakes: "bad\tnan\ninvalid\t-8")
check(overflow.rxBytes == UInt64.max && overflow.txBytes == 5 && overflow.latestHandshake == nil, "malformed and overflow samples")
check(!EngineUtilities.valid(TunnelSession(id: id, profileID: UUID(), logicalName: "wg0", interfaceName: "utun7")), "foreign interface rejected")
let input = "a 'quoted' path\n$(whoami) `id`; \\\""
let process = Process(), pipe = Pipe()
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", "printf '%s' " + EngineUtilities.shellQuote(input)]
process.standardOutput = pipe
try process.run()
let actual = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
check(process.terminationStatus == 0 && String(decoding: actual, as: UTF8.self) == input, "shell quoting preserves inert input")
check(EngineUtilities.appleScriptQuote("a\"b\\c\nd") == "\"a\\\"b\\\\c\\nd\"", "independent AppleScript escaping")
let legacyData = Data("{\"id\":\"\(id.uuidString)\",\"profileID\":\"\(id.uuidString)\",\"logicalName\":\"aeabcdef0123\",\"interfaceName\":\"utun42\"}".utf8)
let legacy = try JSONDecoder().decode(TunnelSession.self, from: legacyData)
check(!legacy.startupIncomplete, "legacy session defaults to complete startup")
let partial = TunnelSession(id: id, profileID: id, logicalName: "aeabcdef0123", interfaceName: "utun42", startupIncomplete: true)
let decoded = try JSONDecoder().decode(TunnelSession.self, from: JSONEncoder().encode(partial))
check(decoded.startupIncomplete, "partial startup survives session recovery")
