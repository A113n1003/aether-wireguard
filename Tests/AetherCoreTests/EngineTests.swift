import XCTest
@testable import AetherCore

final class EngineTests: XCTestCase {
    func testLogicalInterfaceIsStableAndWithinDarwinLimit() {
        let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        XCTAssertEqual(EngineUtilities.logicalName(for: id), "aeabcdef0123")
        XCTAssertLessThanOrEqual(EngineUtilities.logicalName(for: id).count, 15)
    }
    func testStatisticsAggregatePeersAndUseNewestHandshake() {
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let result = EngineUtilities.parseStatistics(interfaceName: "utun42", transfers: "peer1\t100\t20\npeer2\t300\t40\n", handshakes: "peer1\t0\npeer2\t1700000000\n", now: now)
        XCTAssertEqual(result.rxBytes, 400)
        XCTAssertEqual(result.txBytes, 60)
        XCTAssertEqual(result.latestHandshake, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(result.updatedAt, now)
        XCTAssertTrue(result.alive)
    }
    func testInterfaceWithoutHandshakeIsNotFabricatedAsConnected() {
        let result = EngineUtilities.parseStatistics(interfaceName: "utun1", transfers: "peer\t0\t0", handshakes: "peer\t0")
        XCTAssertNil(result.latestHandshake)
        XCTAssertEqual(result.rxBytes, 0)
    }
    func testMalformedSamplesAndCounterOverflowAreSafe() {
        let result = EngineUtilities.parseStatistics(interfaceName: "utun1", transfers: "peer\t18446744073709551615\t2\npeer2\t1\t3\nbad\t-1\t4", handshakes: "bad\tnan\ninvalid\t-8")
        XCTAssertEqual(result.rxBytes, UInt64.max)
        XCTAssertEqual(result.txBytes, 5)
        XCTAssertNil(result.latestHandshake)
    }
    func testSessionCannotClaimForeignInterfaceName() {
        let id = UUID(), profile = UUID()
        XCTAssertFalse(EngineUtilities.valid(TunnelSession(id: id, profileID: profile, logicalName: "wg0", interfaceName: "utun7")))
        XCTAssertFalse(EngineUtilities.valid(TunnelSession(id: id, profileID: profile, logicalName: EngineUtilities.logicalName(for: id), interfaceName: "utun7; whoami")))
        XCTAssertTrue(EngineUtilities.valid(TunnelSession(id: id, profileID: profile, logicalName: EngineUtilities.logicalName(for: id), interfaceName: "utun7")))
    }
    func testShellQuotingDoesNotInterpretConfigPath() throws {
        let input = "a 'quoted' path\n$(whoami) `id`; \\\""
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' " + EngineUtilities.shellQuote(input)]
        process.standardOutput = pipe
        try process.run()
        let actual = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: actual, as: UTF8.self), input)
    }
    func testAppleScriptEscapesIndependentOfShellQuoting() {
        XCTAssertEqual(EngineUtilities.appleScriptQuote("a\"b\\c\nd"), "\"a\\\"b\\\\c\\nd\"")
    }
    func testLegacySessionDecodesAndPartialStartupSurvivesEncoding() throws {
        let id = UUID(), profile = UUID()
        let old = "{\"id\":\"\(id.uuidString)\",\"profileID\":\"\(profile.uuidString)\",\"logicalName\":\"\(EngineUtilities.logicalName(for: id))\",\"interfaceName\":\"utun1\"}"
        XCTAssertFalse(try JSONDecoder().decode(TunnelSession.self, from: Data(old.utf8)).startupIncomplete)
        let partial = TunnelSession(id: id, profileID: profile, logicalName: EngineUtilities.logicalName(for: id), interfaceName: "utun1", startupIncomplete: true)
        XCTAssertEqual(try JSONDecoder().decode(TunnelSession.self, from: JSONEncoder().encode(partial)), partial)
    }
}
