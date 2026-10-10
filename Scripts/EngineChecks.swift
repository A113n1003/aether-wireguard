import Foundation
import Carbon
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
MainActor.assumeIsolated {
    // Compiling the privileged handler does not execute it or request authorization.
    let fixedScript = NSAppleScript(source: EngineUtilities.authorizationScriptSource)!
    var error: NSDictionary?
    check(fixedScript.compileAndReturnError(&error), "fixed authorization handler compiles without execution")
    let echo = NSAppleScript(source: "on authorize_command(commandText)\nreturn commandText\nend authorize_command")!
    for command in ["'Bridge path' 'start' '--config' 'a.conf'", "'Bridge path' 'stop'\n\" & do shell script \"id\" & \"\\中文"] {
        error = nil
        let event = EngineUtilities.authorizationEvent(command: command)
        check(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.atIndex(1)?.stringValue == command, "authorization arguments remain AppleEvent data")
        check(echo.executeAppleEvent(event, error: &error).stringValue == command && error == nil, "unchanged handler receives varying inert commands")
    }
    let cancelled = NSAppleScript(source: "on authorize_command(commandText)\nerror \"cancelled\" number -128\nend authorize_command")!
    error = nil
    _ = cancelled.executeAppleEvent(EngineUtilities.authorizationEvent(command: "inert"), error: &error)
    let number = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
    if case .authorizationCancelled = EngineUtilities.authorizationError(number: number) {
        check(number == -128, "structured cancellation maps to authorization cancellation")
    } else { fatalError("structured cancellation mapping") }
}
for number: Int? in [nil, 1, -600] {
    if case .operationFailed = EngineUtilities.authorizationError(number: number) {} else { fatalError("generic authorization failure mapping") }
}
check(EngineUtilities.authorizationError(number: 1).errorDescription == EngineError.operationFailed.errorDescription, "authorization errors expose only redacted message")
