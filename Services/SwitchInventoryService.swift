import Foundation
import LanFiCore

enum SwitchInventoryError: LocalizedError, Equatable {
    case noAnswer
    case noForwardingTable

    var errorDescription: String? {
        switch self {
        case .noAnswer:
            return "The switch did not answer SNMP. Check the address and the community."
        case .noForwardingTable:
            return
                "The switch answered but exposed no forwarding table. Bridge MIB access may be disabled, or the community may not be allowed to read it."
        }
    }
}

/// G15: reads a switch's BRIDGE-MIB/Q-BRIDGE forwarding table plus its LLDP
/// neighbours, so a MAC from the LAN scan can be placed on a port and a VLAN.
///
/// Read-only and bounded: every table is a GETNEXT walk capped at `maxRows`,
/// the community is used for this read only, and nothing is written to the
/// switch.
struct SwitchInventoryService {
    var maxRows = 500
    var timeout: TimeInterval = 2

    func read(host: String, community: String) async throws -> SwitchInventory {
        var varBinds: [SNMPVarBind] = []
        var answeredTables = 0

        for root in BridgeMIB.walkRoots + LLDP.walkRoots {
            let rows = try? await SNMPClient.walk(
                host: host, community: community, root: root, maxRows: maxRows,
                timeout: timeout)
            guard let rows, !rows.isEmpty else { continue }
            answeredTables += 1
            varBinds.append(
                contentsOf: rows.map { SNMPVarBind(oid: $0.oid, value: Self.rawValue($0.value)) })
        }

        guard answeredTables > 0 else { throw SwitchInventoryError.noAnswer }
        let bridge = BridgeMIB.decode(varBinds)
        guard bridge.hasForwardingTable else { throw SwitchInventoryError.noForwardingTable }
        return SwitchInventory(bridge: bridge, neighbours: LLDP.decode(varBinds))
    }

    static func rawValue(_ value: SNMPValue) -> SNMPRawValue {
        switch value {
        case .integer(let value): return .integer(value)
        case .counter(let value): return .counter(value)
        case .string(let value): return .text(value)
        case .bytes(let value): return .octets(value)
        case .null, .endOfMibView: return .null
        }
    }
}
