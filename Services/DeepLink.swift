import Foundation

enum DeepLink: Equatable {
    case tab(Int)
    case search(String)
    case runDiagnostics
    case interfaces
    case toolkit(ToolboxTool)

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "lanfi" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "tab":
            guard let name = path.first?.lowercased() else { return nil }
            switch name {
            case "insights": return .tab(0)
            case "spectrum": return .tab(4)
            case "history": return .tab(5)
            case "protocols", "profile": return .tab(1)
            case "interfaces": return .interfaces
            case "raw": return .tab(3)
            case "diagnostics": return .tab(6)
            default: return nil
            }
        case "search":
            let query =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            return query.isEmpty ? nil : .search(query)
        case "diagnostics":
            return path.first?.lowercased() == "run" ? .runDiagnostics : nil
        case "interfaces":
            return .interfaces
        case "toolkit":
            guard let raw = path.first,
                let tool = ToolboxTool(rawValue: raw.lowercased())
            else { return .toolkit(.internetCheck) }
            return .toolkit(tool)
        default:
            return nil
        }
    }
}
