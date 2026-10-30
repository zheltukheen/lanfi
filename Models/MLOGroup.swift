import Foundation

/// One affiliated link of a Multi-Link Operation group assembled from a capture.
struct MLOGroupLink: Identifiable, Equatable {
    /// Advertised link ID, or nil when no per-STA profile referenced this BSSID.
    let linkID: Int?
    let bssid: String?
    let channel: Int?
    let rssi: Int?
    /// True when a beacon/probe response from this BSSID is present in the capture.
    let seenInCapture: Bool

    var id: String { bssid ?? "link-\(linkID ?? -1)" }
}

/// All links of one AP MLD seen across an entire capture. A single beacon only
/// advertises the *other* affiliated APs, so the complete set emerges only
/// after merging every beacon that shares the AP MLD address.
struct MLOGroup: Identifiable, Equatable {
    let apMLD: String
    let ssid: String
    let links: [MLOGroupLink]

    var id: String { apMLD }

    var capturedLinkCount: Int { links.filter(\.seenInCapture).count }
}

enum MLOGroupAssembler {
    static func assemble(beacons: [CapturedBeacon]) -> [MLOGroup] {
        var linkBSSIDs: [String: [Int: String]] = [:]  // MLD -> linkID -> BSSID
        var members: [String: [CapturedBeacon]] = [:]
        var order: [String] = []

        for beacon in beacons {
            guard let info = MLOInfo.parse(elements: beacon.informationElements, widthMHz: 0),
                let mld = info.apMLD
            else { continue }
            if members[mld] == nil {
                members[mld] = []
                linkBSSIDs[mld] = [:]
                order.append(mld)
            }
            members[mld]?.append(beacon)
            for link in info.links {
                if let bssid = link.bssid, linkBSSIDs[mld]?[link.linkID] == nil {
                    linkBSSIDs[mld]?[link.linkID] = bssid
                }
            }
        }

        return order.map { mld in
            let groupBeacons = members[mld] ?? []
            let byBSSID = Dictionary(uniqueKeysWithValues: groupBeacons.map { ($0.bssid, $0) })
            var links: [MLOGroupLink] = []
            var claimed: Set<String> = []

            for (linkID, bssid) in (linkBSSIDs[mld] ?? [:]).sorted(by: { $0.key < $1.key }) {
                let seen = byBSSID[bssid]
                claimed.insert(bssid)
                links.append(
                    MLOGroupLink(
                        linkID: linkID, bssid: bssid,
                        channel: seen?.channel, rssi: seen?.rssi,
                        seenInCapture: seen != nil
                    )
                )
            }
            // Reporting APs never advertise their own link ID; attach the ones
            // no profile claimed as captured links with unknown link ID.
            for beacon in groupBeacons where !claimed.contains(beacon.bssid) {
                claimed.insert(beacon.bssid)
                links.append(
                    MLOGroupLink(
                        linkID: nil, bssid: beacon.bssid,
                        channel: beacon.channel, rssi: beacon.rssi,
                        seenInCapture: true
                    )
                )
            }

            return MLOGroup(
                apMLD: mld,
                ssid: groupBeacons.first?.ssid ?? "",
                links: links
            )
        }
    }
}
