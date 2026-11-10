import Foundation

/// A dotted-quad IPv4 address stored as one big-endian integer.
struct IPv4Address: Equatable, Comparable, CustomStringConvertible, Sendable {
    let value: UInt32

    init(_ value: UInt32) {
        self.value = value
    }

    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part), !part.isEmpty else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        self.value = result
    }

    static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.value < rhs.value
    }

    var description: String {
        [
            String((value >> 24) & 0xff),
            String((value >> 16) & 0xff),
            String((value >> 8) & 0xff),
            String(value & 0xff),
        ].joined(separator: ".")
    }
}

struct SubnetInfo: Equatable, Sendable {
    let network: IPv4Address
    let broadcast: IPv4Address
    let netmask: IPv4Address
    let prefixLength: Int
    let firstUsable: IPv4Address?
    let lastUsable: IPv4Address?
    let totalAddresses: Int64
    let usableHosts: Int64

    var wildcard: IPv4Address {
        IPv4Address(~netmask.value)
    }

    var cidr: String {
        "\(network)/\(prefixLength)"
    }
}

enum SubnetCalculator {
    /// Parses `192.168.1.10/24` (a host address plus prefix) and returns the
    /// subnet it belongs to.
    static func parseCIDR(_ raw: String) -> SubnetInfo? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let address = IPv4Address(String(parts[0])),
            let prefix = Int(parts[1]),
            (0...32).contains(prefix)
        else { return nil }
        return subnet(address: address, prefixLength: prefix)
    }

    static func subnet(address: IPv4Address, prefixLength: Int) -> SubnetInfo? {
        guard (0...32).contains(prefixLength) else { return nil }

        let mask: UInt32 = prefixLength == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefixLength)
        let networkValue = address.value & mask
        let broadcastValue = networkValue | ~mask
        let total = Int64(1) << Int64(32 - prefixLength)

        let first: IPv4Address?
        let last: IPv4Address?
        let usable: Int64
        switch prefixLength {
        case 32:
            first = IPv4Address(networkValue)
            last = IPv4Address(networkValue)
            usable = 1
        case 31:
            first = IPv4Address(networkValue)
            last = IPv4Address(broadcastValue)
            usable = 2
        default:
            first = IPv4Address(networkValue + 1)
            last = IPv4Address(broadcastValue - 1)
            usable = total - 2
        }

        return SubnetInfo(
            network: IPv4Address(networkValue),
            broadcast: IPv4Address(broadcastValue),
            netmask: IPv4Address(mask),
            prefixLength: prefixLength,
            firstUsable: first,
            lastUsable: last,
            totalAddresses: total,
            usableHosts: usable
        )
    }
}
