import XCTest
@testable import Remux

final class TailscaleStatusParserTests: XCTestCase {
    func testParsesPeersWithUserResolution() throws {
        let json = """
            {
              "Self": {
                "HostName": "this-mac",
                "DNSName": "this-mac.tail1234.ts.net.",
                "OS": "macOS",
                "Online": true,
                "TailscaleIPs": ["100.64.0.9"]
              },
              "Peer": {
                "nodekey:aaa": {
                  "HostName": "feis-macbook-pro",
                  "DNSName": "feis-macbook-pro.tail1234.ts.net.",
                  "OS": "macOS",
                  "Online": true,
                  "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
                  "UserID": 42
                },
                "nodekey:bbb": {
                  "HostName": "byrons-macbook-air",
                  "DNSName": "byrons-macbook-air.tail1234.ts.net.",
                  "OS": "macOS",
                  "Online": false,
                  "TailscaleIPs": ["100.64.0.2"],
                  "UserID": 43
                }
              },
              "User": {
                "42": { "ID": 42, "LoginName": "fei@github", "DisplayName": "Fei" },
                "43": { "ID": 43, "LoginName": "byron@github", "DisplayName": "Byron" }
              }
            }
            """

        let peers = try TailscaleStatusParser.parse(data: Data(json.utf8))

        XCTAssertEqual(peers.count, 2)
        XCTAssertEqual(peers.map(\.hostName), ["byrons-macbook-air", "feis-macbook-pro"])

        let pro = try XCTUnwrap(peers.first { $0.hostName == "feis-macbook-pro" })
        XCTAssertEqual(pro.dnsName, "feis-macbook-pro.tail1234.ts.net")
        XCTAssertEqual(pro.os, "macOS")
        XCTAssertTrue(pro.online)
        XCTAssertEqual(pro.tailscaleIP, "100.64.0.1")
        XCTAssertEqual(pro.userLoginName, "fei@github")

        let air = try XCTUnwrap(peers.first { $0.hostName == "byrons-macbook-air" })
        XCTAssertFalse(air.online)
    }

    func testPeerWithoutIPv4OrUserLeavesFieldsNil() throws {
        let json = """
            {
              "Peer": {
                "nodekey:aaa": {
                  "HostName": "linux-box",
                  "DNSName": "linux-box.tail1234.ts.net.",
                  "OS": "linux",
                  "Online": true,
                  "TailscaleIPs": ["fd7a:115c:a1e0::1"]
                }
              }
            }
            """

        let peers = try TailscaleStatusParser.parse(data: Data(json.utf8))

        XCTAssertEqual(peers.count, 1)
        let peer = peers[0]
        XCTAssertEqual(peer.dnsName, "linux-box.tail1234.ts.net")
        XCTAssertNil(peer.tailscaleIP)
        XCTAssertNil(peer.userLoginName)
    }

    func testMissingPeerMapParsesAsEmpty() throws {
        let peers = try TailscaleStatusParser.parse(data: Data("{}".utf8))
        XCTAssertEqual(peers, [])
    }

    func testPeerWithMissingOptionalFieldsDefaults() throws {
        let json = """
            {
              "Peer": {
                "nodekey:aaa": {}
              }
            }
            """

        let peers = try TailscaleStatusParser.parse(data: Data(json.utf8))

        XCTAssertEqual(peers.count, 1)
        let peer = peers[0]
        XCTAssertEqual(peer.hostName, "")
        XCTAssertEqual(peer.dnsName, "")
        XCTAssertNil(peer.os)
        XCTAssertFalse(peer.online)
        XCTAssertNil(peer.tailscaleIP)
        XCTAssertNil(peer.userLoginName)
    }

    func testMalformedStatusThrows() {
        XCTAssertThrowsError(try TailscaleStatusParser.parse(data: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? TailscaleStatusParseError, .invalidStatus)
        }
    }

    func testPeerMapKeyedByNodeKeyNotArray() throws {
        // `tailscale status --json` emits Peer as an object; ensure a JSON
        // array there fails loudly rather than silently importing nothing.
        let json = """
            { "Peer": [] }
            """

        XCTAssertThrowsError(try TailscaleStatusParser.parse(data: Data(json.utf8))) { error in
            XCTAssertEqual(error as? TailscaleStatusParseError, .invalidStatus)
        }
    }
}
