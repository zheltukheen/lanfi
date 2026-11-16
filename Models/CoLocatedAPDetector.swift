import Foundation

/// Infers that two or more BSSIDs belong to one physical access point when the
/// AP does not advertise an AP name.
///
/// Radios of a single chassis share vendor, model (WPS/model IE) and an
/// information-element fingerprint. Merging is deliberately conservative: an
/// unnamed radio only joins a group when the same fingerprint appears on more
/// than one band with exactly one radio per band. Two identical APs in the same
/// room are indistinguishable from one scan, and a wrong merge hides a real
/// network, so those stay separate.
enum CoLocatedAPDetector {
    /// Group key per `NetworkModel.id`. Keys are stable across scans and safe to
    /// use as table group ids.
    static func groupKeys(for networks: [NetworkModel]) -> [String: String] {
        var keys: [String: String] = [:]
        var candidates: [String: [NetworkModel]] = [:]

        for network in networks {
            if let name = advertisedName(network) {
                keys[network.id] = "name:\(name)"
                continue
            }
            guard let fingerprint = sharedFingerprint(network) else {
                keys[network.id] = separateKey(network)
                continue
            }
            candidates[fingerprint, default: []].append(network)
        }

        for (fingerprint, members) in candidates {
            var radiosPerBand: [WiFiBand: Int] = [:]
            for member in members {
                radiosPerBand[member.band, default: 0] += 1
            }
            let oneRadioPerBand = radiosPerBand.values.allSatisfy { $0 == 1 }
            if radiosPerBand.count > 1 && oneRadioPerBand {
                for member in members {
                    keys[member.id] = "model:\(fingerprint)"
                }
            } else {
                for member in members {
                    keys[member.id] = separateKey(member)
                }
            }
        }

        return keys
    }

    /// Other radios of the same physical access point, inferred from the shared
    /// model/IE fingerprint. Empty when the AP advertises a name (grouping by
    /// name already covers that) or when the merge would not be safe.
    static func coLocatedSiblings(
        of network: NetworkModel, in networks: [NetworkModel]
    ) -> [NetworkModel] {
        let keys = groupKeys(for: networks)
        guard let key = keys[network.id], key.hasPrefix("model:") else { return [] }
        return
            networks
            .filter { $0.id != network.id && keys[$0.id] == key }
            .sorted { $0.band.sortOrder < $1.band.sortOrder }
    }

    private static func advertisedName(_ network: NetworkModel) -> String? {
        guard let name = network.apName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return nil }
        return name
    }

    /// Vendor + model + IE layout. The IE layout keeps two different products
    /// from the same vendor with the same model string apart.
    private static func sharedFingerprint(_ network: NetworkModel) -> String? {
        guard let model = network.routerModel?.trimmingCharacters(in: .whitespacesAndNewlines),
            !model.isEmpty
        else { return nil }
        let vendor = network.vendor == "-" ? "" : network.vendor
        let layout = network.informationElements
            .map { "\($0.elementId):\($0.length)" }
            .sorted()
            .joined(separator: ",")
        return "\(vendor)|\(model)|\(layout)"
    }

    private static func separateKey(_ network: NetworkModel) -> String {
        network.bssid.isEmpty ? "id:\(network.id)" : "bssid:\(network.bssid)"
    }
}
