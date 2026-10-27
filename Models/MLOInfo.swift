import Foundation

struct MLOLinkInfo: Identifiable, Equatable {
    var id: Int { linkID }
    let linkID: Int
    let bssid: String?
}

struct MLOInfo: Equatable {
    let apMLD: String?
    let links: [MLOLinkInfo]
    let is320MHz: Bool

    static func parse(elements: [InformationElement], widthMHz: Int) -> MLOInfo? {
        var apMLD: String?
        var links: [Int: String] = [:]
        var linkIDs: Set<Int> = []
        for element in elements where element.name.lowercased().contains("multi-link") {
            for line in element.detailLines {
                if line.hasPrefix("AP MLD address: ") {
                    apMLD = String(line.dropFirst("AP MLD address: ".count))
                } else if line.hasPrefix("Link "), let range = line.range(of: " BSSID: ") {
                    let idText = line.dropFirst("Link ".count).prefix { $0.isNumber }
                    if let id = Int(idText) {
                        linkIDs.insert(id)
                        links[id] = String(line[range.upperBound...])
                    }
                } else if line.hasPrefix("Per-STA profile link IDs: ") {
                    let ids = line.dropFirst("Per-STA profile link IDs: ".count)
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    linkIDs.formUnion(ids)
                }
            }
        }
        guard apMLD != nil || !linkIDs.isEmpty else { return nil }
        return MLOInfo(
            apMLD: apMLD,
            links: linkIDs.sorted().map { MLOLinkInfo(linkID: $0, bssid: links[$0]) },
            is320MHz: widthMHz >= 320 || elements.contains { $0.summary.contains("320 MHz") }
        )
    }
}
