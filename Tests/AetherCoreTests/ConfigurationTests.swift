import XCTest
@testable import AetherCore

final class ConfigurationTests: XCTestCase {
    private let valid = WGConfiguration.exampleText

    func testCanonicalRoundTripPreservesSupportedFields() throws {
        let source = valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: "DNS = 1.1.1.1, fd00::53, corp.example\nMTU = 1420\nListenPort = 51821")
        let config = try WGConfiguration(text: source)
        let repeated = try WGConfiguration(text: config.canonicalText)
        XCTAssertEqual(config.canonicalText, repeated.canonicalText)
        XCTAssertEqual(config.addresses, ["10.8.0.2/32", "fd00:8::2/128"])
        XCTAssertEqual(config.dns.count, 3)
        XCTAssertTrue(config.canonicalText.contains("MTU = 1420"))
        XCTAssertTrue(config.canonicalText.contains("ListenPort = 51821"))
    }

    func testRejectsCommandAndUnknownFields() {
        for line in ["PostUp = touch /tmp/injected", "PreDown = $(id)", "Table = auto", "SaveConfig = true", "Unknown = anything"] {
            XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: line)))
        }
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "vpn.example.com:51820", with: "vpn.example.com:51820;id")))
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "vpn.example.com:51820", with: "$(id):51820")))
    }

    func testRejectsDuplicatesAndBadKeys() {
        XCTAssertThrowsError(try WGConfiguration(text: valid + "\nPersistentKeepalive = 30"))
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "[Peer]", with: "[Interface]\n[Peer]")))
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", with: "not-base64")))
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", with: "AAAA")))
    }

    func testMultiplePeersAndMissingEndpointWarning() throws {
        let secondKey = Data(repeating: 2, count: 32).base64EncodedString()
        let config = try WGConfiguration(text: valid + "\n[Peer]\nPublicKey = \(secondKey)\nAllowedIPs = 192.168.50.0/24\n")
        XCTAssertEqual(config.peers.count, 2)
        XCTAssertEqual(config.warnings.count, 1)
        XCTAssertNil(config.peers[1].endpoint)
        XCTAssertTrue(config.canonicalText.contains(secondKey))
    }

    func testMasksOnlySecretKeys() throws {
        let psk = Data(repeating: 3, count: 32).base64EncodedString()
        let config = try WGConfiguration(text: valid + "\nPresharedKey = \(psk)")
        XCTAssertFalse(config.maskedText.contains("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
        XCTAssertFalse(config.maskedText.contains(psk))
        XCTAssertTrue(config.maskedText.contains(config.peers[0].publicKey))
        XCTAssertTrue(config.canonicalText.contains(psk))
    }

    func testIPv6EndpointAndPrefixBoundaries() throws {
        let v6 = valid.replacingOccurrences(of: "vpn.example.com:51820", with: "[2001:db8::1]:65535")
        XCTAssertEqual(try WGConfiguration(text: v6).peers[0].endpoint, "[2001:db8::1]:65535")
        for malformed in ["[2001:db8:::1]:51820", "2001:db8::1:51820", "[2001:db8::1]:0", "[2001:db8::1]:65536", "[2001:db8::1]:"] {
            XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "vpn.example.com:51820", with: malformed)))
        }
        for malformed in ["fd00:8::2/129", "fd00:8:::2/128", "10.8.0.2/33", "999.8.0.2/32"] {
            XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "10.8.0.2/32, fd00:8::2/128", with: malformed)))
        }
        XCTAssertNoThrow(try WGConfiguration(text: valid.replacingOccurrences(of: "10.8.0.0/24, fd00:8::/64", with: "0.0.0.0/0, ::/0")))
    }

    func testRejectsEmptyListsAndNumbers() {
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: "DNS = 1.1.1.1,")))
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "PersistentKeepalive = 25", with: "PersistentKeepalive = -1")))
        XCTAssertThrowsError(try WGConfiguration(text: valid.replacingOccurrences(of: "DNS = 1.1.1.1", with: "MTU = 575")))
    }

    func testErrorDescriptionsNeverContainPrivateKey() {
        let key = "sensitive-invalid-key-material"
        do {
            _ = try WGConfiguration(text: valid.replacingOccurrences(of: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", with: key))
            XCTFail("Invalid key must fail")
        } catch { XCTAssertFalse(error.localizedDescription.contains(key)) }
    }
}
