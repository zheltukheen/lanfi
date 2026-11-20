import Foundation

/// A UDP endpoint as reported by a STUN server.
struct STUNEndpoint: Equatable, Hashable, Sendable {
    let address: String
    let port: UInt16

    var label: String { "\(address):\(port)" }
}

/// How the router builds the public mapping for this client.
///
/// Only the mapping half is measured in this build: two servers answer from
/// one socket, so "same mapping everywhere" and "new mapping per destination"
/// are directly observable, while filtering needs a peer that sends back.
enum NATMappingBehaviour: String, Sendable {
    case endpointIndependent
    case addressDependent
    case unknown

    var label: String {
        switch self {
        case .endpointIndependent: return String(localized: "Endpoint independent")
        case .addressDependent: return String(localized: "Per destination")
        case .unknown: return String(localized: "Unknown")
        }
    }
}

enum NATFilteringBehaviour: String, Sendable {
    case endpointIndependent
    case addressDependent
    case unknown

    var label: String {
        switch self {
        case .endpointIndependent: return String(localized: "Endpoint independent")
        case .addressDependent: return String(localized: "Per destination")
        case .unknown: return String(localized: "Not probed")
        }
    }
}

/// What the mapping behaviour means for reachability.
enum NATVerdict: String, Sendable {
    case direct
    case cone
    case symmetric
    case blocked
    case unknown

    var title: String {
        switch self {
        case .direct: return String(localized: "No NAT")
        case .cone: return String(localized: "Cone NAT")
        case .symmetric: return String(localized: "Symmetric NAT")
        case .blocked: return String(localized: "No answer")
        case .unknown: return String(localized: "Unknown")
        }
    }

    var detail: String {
        switch self {
        case .direct:
            return String(localized: "The public address is the one this Mac already has.")
        case .cone:
            return String(
                localized:
                    "One mapping is reused for every destination, so a forwarded port can stay open.")
        case .symmetric:
            return String(
                localized:
                    "Every destination gets its own mapping; port forwarding and peer-to-peer need a relay.")
        case .blocked:
            return String(localized: "No STUN server answered. UDP may be blocked entirely.")
        case .unknown:
            return String(localized: "Not enough answers to classify the router.")
        }
    }
}

struct NATProbe: Identifiable, Equatable, Sendable {
    let id: String
    let server: STUNEndpoint
    let mapped: STUNEndpoint?
    let milliseconds: Int?
    let failure: String?

    var answerText: String {
        if let failure { return failure }
        return mapped?.label ?? String(localized: "No mapping")
    }
}

/// The result of one STUN session. Pure data, so the classification can be
/// tested with recorded answers.
struct NATReport: Equatable, Sendable {
    let localEndpoint: STUNEndpoint
    let probes: [NATProbe]
    let mapping: NATMappingBehaviour
    let filtering: NATFilteringBehaviour

    var answeredProbes: [NATProbe] { probes.filter { $0.mapped != nil } }
    var externalEndpoint: STUNEndpoint? { answeredProbes.first?.mapped }

    /// True when the router kept the source port (a forwarded port still lines
    /// up with the local service).
    var portPreserved: Bool {
        guard let externalEndpoint else { return false }
        return externalEndpoint.port == localEndpoint.port
    }

    var verdict: NATVerdict {
        let answered = answeredProbes
        guard !answered.isEmpty else { return .blocked }
        if let first = answered.first?.mapped, first == localEndpoint, answered.count == probes.count {
            return .direct
        }
        switch mapping {
        case .endpointIndependent: return .cone
        case .addressDependent: return .symmetric
        case .unknown: return .unknown
        }
    }

    /// Classifies mapping behaviour from the answers: the same public endpoint
    /// from different destinations means the mapping is independent of them.
    static func mapping(for probes: [NATProbe]) -> NATMappingBehaviour {
        let mappings = Set(probes.compactMap(\.mapped))
        guard mappings.count > 0 else { return .unknown }
        guard probes.filter({ $0.mapped != nil }).count >= 2 else { return .unknown }
        return mappings.count == 1 ? .endpointIndependent : .addressDependent
    }
}
