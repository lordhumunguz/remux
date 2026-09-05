import Foundation

struct TailscalePeer: Equatable, Sendable {
    let hostName: String
    /// MagicDNS name with any trailing dot removed; empty when the peer has none.
    let dnsName: String
    let os: String?
    let online: Bool
    /// First `100.x` address, when the peer advertises one.
    let tailscaleIP: String?
    /// Tailscale login resolved through the top-level `User` map, when present.
    let userLoginName: String?
}

enum TailscaleStatusParseError: Error, Equatable, LocalizedError {
    case invalidStatus

    var errorDescription: String? {
        "Tailscale returned an unreadable status."
    }
}

/// Parses `tailscale status --json` output. The `Peer` field is an object
/// keyed by node key rather than an array; ordering here is normalized by
/// host name for deterministic presentation.
enum TailscaleStatusParser {
    static func parse(data: Data) throws -> [TailscalePeer] {
        let status: Status
        do {
            status = try JSONDecoder().decode(Status.self, from: data)
        } catch {
            throw TailscaleStatusParseError.invalidStatus
        }
        let users = status.user ?? [:]
        return (status.peer ?? [:]).values
            .map { node in
                TailscalePeer(
                    hostName: node.hostName ?? "",
                    dnsName: trimmingTrailingDot(node.dnsName ?? ""),
                    os: node.os,
                    online: node.online ?? false,
                    tailscaleIP: node.tailscaleIPs?.first { $0.hasPrefix("100.") },
                    userLoginName: node.userID.flatMap { users[String($0)]?.loginName }
                )
            }
            .sorted {
                $0.hostName.localizedStandardCompare($1.hostName) == .orderedAscending
            }
    }

    private static func trimmingTrailingDot(_ name: String) -> String {
        name.hasSuffix(".") ? String(name.dropLast()) : name
    }

    private struct Status: Decodable {
        let peer: [String: PeerNode]?
        let user: [String: User]?

        enum CodingKeys: String, CodingKey {
            case peer = "Peer"
            case user = "User"
        }
    }

    private struct PeerNode: Decodable {
        let hostName: String?
        let dnsName: String?
        let os: String?
        let online: Bool?
        let tailscaleIPs: [String]?
        let userID: UInt64?

        enum CodingKeys: String, CodingKey {
            case hostName = "HostName"
            case dnsName = "DNSName"
            case os = "OS"
            case online = "Online"
            case tailscaleIPs = "TailscaleIPs"
            case userID = "UserID"
        }
    }

    private struct User: Decodable {
        let loginName: String?

        enum CodingKeys: String, CodingKey {
            case loginName = "LoginName"
        }
    }
}
