import Foundation

/// One value read by an SNMP walk, kept in the package so the bridge-table
/// decoder can be tested against recorded responses without a socket.
public enum SNMPRawValue: Equatable, Sendable {
    case integer(Int64)
    case counter(UInt64)
    case text(String)
    case octets([UInt8])
    case null

    public var integerValue: Int64? {
        switch self {
        case .integer(let value): return value
        case .counter(let value): return Int64(clamping: value)
        default: return nil
        }
    }

    /// Only a decoded string counts as text. An octet string stays bytes so a
    /// MAC or a bit mask is never rendered as mojibake in a port name.
    public var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

public struct SNMPVarBind: Equatable, Sendable {
    public let oid: String
    public let value: SNMPRawValue

    public init(oid: String, value: SNMPRawValue) {
        self.oid = oid
        self.value = value
    }
}

/// One forwarding-table row: which switch port a MAC was learned on.
public struct SwitchPortEntry: Equatable, Identifiable, Sendable {
    public let mac: String
    public let bridgePort: Int
    /// VLAN from Q-BRIDGE; nil when the switch only answered BRIDGE-MIB.
    public let vlan: Int?
    public let interfaceIndex: Int?
    public let portName: String?

    public init(
        mac: String, bridgePort: Int, vlan: Int? = nil, interfaceIndex: Int? = nil,
        portName: String? = nil
    ) {
        self.mac = mac
        self.bridgePort = bridgePort
        self.vlan = vlan
        self.interfaceIndex = interfaceIndex
        self.portName = portName
    }

    public var id: String { vlan.map { "\($0)/\(mac)" } ?? mac }

    /// Either the interface description the switch publishes or the bridge
    /// port number it learned the MAC on.
    public var portLabel: String {
        if let portName, !portName.isEmpty { return portName }
        if let interfaceIndex { return "if\(interfaceIndex)" }
        return "port \(bridgePort)"
    }
}

public struct BridgeTable: Equatable, Sendable {
    public let ports: [SwitchPortEntry]
    public let vlanNames: [Int: String]
    /// False when the switch answered other OIDs but had no dot1dTpFdbTable —
    /// a VLAN-only or non-bridging device.
    public let hasForwardingTable: Bool

    public init(
        ports: [SwitchPortEntry], vlanNames: [Int: String], hasForwardingTable: Bool
    ) {
        self.ports = ports
        self.vlanNames = vlanNames
        self.hasForwardingTable = hasForwardingTable
    }

    public static let empty = BridgeTable(ports: [], vlanNames: [:], hasForwardingTable: false)

    public func vlanName(_ vlan: Int) -> String? {
        let name = vlanNames[vlan]
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// The entry that answers "where was this device learned". A VLAN-aware
    /// row wins over a plain BRIDGE-MIB row for the same MAC.
    public func port(forMAC mac: String) -> SwitchPortEntry? {
        guard let key = BridgeMIB.normalizedMAC(mac) else { return nil }
        let matches = ports.filter { $0.mac == key }
        return matches.first(where: { $0.vlan != nil }) ?? matches.first
    }

    public func ports(inVLAN vlan: Int) -> [SwitchPortEntry] {
        ports.filter { $0.vlan == vlan }
    }
}

/// Decodes the OIDs an SNMP walk returned for BRIDGE-MIB and Q-BRIDGE into a
/// MAC → port → VLAN table.
///
/// Only what the switch actually answered is reported: a missing VLAN table
/// leaves `vlan` nil instead of assuming VLAN 1, and a bridge port without an
/// `ifIndex` keeps `interfaceIndex` nil instead of inventing a name.
public enum BridgeMIB {
    public static let dot1dTpFdbPort = "1.3.6.1.2.1.17.4.3.1.2"
    public static let dot1dBasePortIfIndex = "1.3.6.1.2.1.17.1.4.1.2"
    public static let ifDescr = "1.3.6.1.2.1.2.2.1.2"
    public static let ifName = "1.3.6.1.2.1.31.1.1.1.1"
    public static let dot1qTpFdbPort = "1.3.6.1.2.1.17.7.1.2.2.1.2"
    public static let dot1qVlanFdbId = "1.3.6.1.2.1.17.7.1.4.2.1.10"
    public static let dot1qVlanStaticName = "1.3.6.1.2.1.17.7.1.4.2.1.3"

    /// Walk roots in the order the switch is asked for them. `ifName` is read
    /// before `ifDescr` so the operator's port label wins over the driver's.
    public static let walkRoots = [
        dot1dBasePortIfIndex, dot1dTpFdbPort, dot1qTpFdbPort, dot1qVlanFdbId,
        dot1qVlanStaticName, ifName, ifDescr,
    ]

    public static func decode(_ varBinds: [SNMPVarBind]) -> BridgeTable {
        var portToIndex: [Int: Int] = [:]
        var ifNames: [Int: String] = [:]
        var fdbToVLAN: [Int: Int] = [:]
        var vlanNames: [Int: String] = [:]
        var bridgeEntries: [String: SwitchPortEntry] = [:]
        var vlanRows: [(fdbID: Int, mac: String, port: Int)] = []
        var hasForwardingTable = false

        for bind in varBinds {
            if let components = suffix(bind.oid, after: dot1dBasePortIfIndex), components.count == 1,
                let index = bind.value.integerValue
            {
                portToIndex[components[0]] = Int(index)
                continue
            }
            if let components = suffix(bind.oid, after: dot1dTpFdbPort), components.count == 6,
                let mac = macString(components), let port = bind.value.integerValue
            {
                hasForwardingTable = true
                bridgeEntries[mac] = SwitchPortEntry(mac: mac, bridgePort: Int(port))
                continue
            }
            if let components = suffix(bind.oid, after: dot1qTpFdbPort), components.count == 7,
                let mac = macString(Array(components.suffix(6))),
                let port = bind.value.integerValue
            {
                hasForwardingTable = true
                vlanRows.append((components[0], mac, Int(port)))
                continue
            }
            if let components = suffix(bind.oid, after: dot1qVlanFdbId), components.count == 1,
                let fdbID = bind.value.integerValue
            {
                fdbToVLAN[Int(fdbID)] = components[0]
                continue
            }
            if let components = suffix(bind.oid, after: dot1qVlanStaticName), components.count == 1,
                let name = bind.value.textValue, !name.isEmpty
            {
                vlanNames[components[0]] = name
                continue
            }
            if let components = suffix(bind.oid, after: ifName), components.count == 1,
                let name = bind.value.textValue, !name.isEmpty
            {
                ifNames[components[0]] = name
                continue
            }
            if let components = suffix(bind.oid, after: ifDescr), components.count == 1,
                let name = bind.value.textValue, !name.isEmpty
            {
                // A walk of both roots can arrive out of order, so the driver
                // description only fills a gap the operator label left.
                if ifNames[components[0]] == nil { ifNames[components[0]] = name }
                continue
            }
        }

        // A dot1q row carries the VLAN, so it replaces the plain BRIDGE-MIB row
        // for the same MAC. The reverse never happens. The VLAN table can be
        // walked after the forwarding table, so the mapping is applied here
        // rather than while reading the rows.
        for row in vlanRows {
            bridgeEntries[row.mac] = SwitchPortEntry(
                mac: row.mac, bridgePort: row.port, vlan: fdbToVLAN[row.fdbID])
        }

        let ports = bridgeEntries.values.map { entry in
            let index = portToIndex[entry.bridgePort]
            return SwitchPortEntry(
                mac: entry.mac,
                bridgePort: entry.bridgePort,
                vlan: entry.vlan,
                interfaceIndex: index,
                portName: index.flatMap { ifNames[$0] }
            )
        }.sorted { lhs, rhs in
            let leftVLAN = lhs.vlan ?? Int.max
            let rightVLAN = rhs.vlan ?? Int.max
            if leftVLAN != rightVLAN { return leftVLAN < rightVLAN }
            if lhs.bridgePort != rhs.bridgePort { return lhs.bridgePort < rhs.bridgePort }
            return lhs.mac < rhs.mac
        }

        return BridgeTable(ports: ports, vlanNames: vlanNames, hasForwardingTable: hasForwardingTable)
    }

    /// `arp` and pcap both print MACs without separators or with dashes; the
    /// forwarding table always uses six colon-separated uppercase octets.
    public static func normalizedMAC(_ value: String) -> String? {
        let parts = value.split(whereSeparator: { $0 == ":" || $0 == "-" || $0 == "." })
        if parts.count == 6 {
            var octets: [String] = []
            for part in parts {
                guard (1...2).contains(part.count), let byte = UInt8(part, radix: 16) else {
                    return nil
                }
                octets.append(String(format: "%02X", byte))
            }
            return octets.joined(separator: ":")
        }
        let hex = value.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var octets: [String] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            octets.append(String(hex[index..<next]))
            index = next
        }
        return octets.joined(separator: ":")
    }

    private static func macString(_ components: [Int]) -> String? {
        guard components.count == 6, components.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }
        return components.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func suffix(_ oid: String, after prefix: String) -> [Int]? {
        guard oid.hasPrefix(prefix + ".") else { return nil }
        let tail = oid.dropFirst(prefix.count + 1)
        var components: [Int] = []
        for part in tail.split(separator: ".") {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        return components
    }
}

/// One LLDP neighbour: which port on this switch leads to which other device.
public struct LLDPNeighbour: Equatable, Sendable {
    /// `lldpRemLocalPortNum`, the same bridge/ifIndex space the forwarding
    /// table reports a MAC on.
    public let localPort: Int
    public let systemName: String?
    public let portDescription: String?

    public init(localPort: Int, systemName: String? = nil, portDescription: String? = nil) {
        self.localPort = localPort
        self.systemName = systemName
        self.portDescription = portDescription
    }

    public var id: String { "\(localPort)" }

    public var label: String {
        var parts: [String] = []
        if let systemName, !systemName.isEmpty { parts.append(systemName) }
        if let portDescription, !portDescription.isEmpty { parts.append(portDescription) }
        return parts.joined(separator: " · ")
    }
}

/// Decodes `LLDP-MIB`'s `lldpRemTable` rows into one neighbour per local port.
public enum LLDP {
    public static let remSystemName = "1.0.8802.1.1.2.1.4.1.1.9"
    public static let remPortDesc = "1.0.8802.1.1.2.1.4.1.1.8"
    public static let walkRoots = [remSystemName, remPortDesc]

    public static func decode(_ varBinds: [SNMPVarBind]) -> [LLDPNeighbour] {
        var names: [Int: String] = [:]
        var ports: [Int: String] = [:]
        for bind in varBinds {
            let components: [Int]?
            if bind.oid.hasPrefix(remSystemName + ".") {
                components = suffix(bind.oid, after: remSystemName)
                if let components, components.count == 3, let name = bind.value.textValue,
                    !name.isEmpty
                {
                    let port = components[1]
                    if names[port] == nil { names[port] = name }
                }
            } else if bind.oid.hasPrefix(remPortDesc + ".") {
                components = suffix(bind.oid, after: remPortDesc)
                if let components, components.count == 3, let description = bind.value.textValue,
                    !description.isEmpty
                {
                    let port = components[1]
                    if ports[port] == nil { ports[port] = description }
                }
            }
        }
        let localPorts = Set(names.keys).union(ports.keys).sorted()
        return localPorts.map {
            LLDPNeighbour(localPort: $0, systemName: names[$0], portDescription: ports[$0])
        }
    }

    private static func suffix(_ oid: String, after prefix: String) -> [Int]? {
        guard oid.hasPrefix(prefix + ".") else { return nil }
        var components: [Int] = []
        for part in oid.dropFirst(prefix.count + 1).split(separator: ".") {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        return components
    }
}

/// One read-only answer from a switch: the forwarding table plus the LLDP
/// neighbours that explain where an uplink port goes.
public struct SwitchInventory: Equatable, Sendable {
    public let bridge: BridgeTable
    public let neighbours: [LLDPNeighbour]

    public init(bridge: BridgeTable, neighbours: [LLDPNeighbour] = []) {
        self.bridge = bridge
        self.neighbours = neighbours
    }

    public static let empty = SwitchInventory(bridge: .empty)

    public func neighbour(forLocalPort port: Int) -> LLDPNeighbour? {
        neighbours.first { $0.localPort == port }
    }

    /// "core-sw-1 · Gi1/0/24" when LLDP named the far end of the port.
    public func uplinkDescription(for entry: SwitchPortEntry) -> String? {
        let port = entry.interfaceIndex ?? entry.bridgePort
        guard let neighbour = neighbour(forLocalPort: port), !neighbour.label.isEmpty else {
            return nil
        }
        return neighbour.label
    }
}
