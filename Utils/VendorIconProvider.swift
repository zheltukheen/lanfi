import Foundation

enum VendorIconProvider {
    static func symbol(for vendor: String?) -> String? {
        guard let vendor, !vendor.isEmpty else { return nil }
        let value = vendor.lowercased()
        let rules: [(String, String)] = [
            ("apple", "apple.logo"),
            ("cisco", "network"),
            ("meraki", "network"),
            ("ubiquiti", "wifi.router"),
            ("unifi", "wifi.router"),
            ("aruba", "network"),
            ("ruckus", "network"),
            ("netgear", "wifi.router"),
            ("tp-link", "wifi.router"),
            ("tplink", "wifi.router"),
            ("asus", "wifi.router"),
            ("linksys", "wifi.router"),
            ("d-link", "wifi.router"),
            ("huawei", "network"),
            ("samsung", "network"),
            ("intel", "cpu"),
            ("broadcom", "cpu"),
            ("qualcomm", "cpu"),
            ("mikrotik", "network"),
        ]
        return rules.first { value.contains($0.0) }?.1 ?? "network"
    }
}
