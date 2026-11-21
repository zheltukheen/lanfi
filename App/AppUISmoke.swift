#if DEBUG
    import AppKit
    import SwiftUI

    /// Headless UI smoke test: builds the real toolkit view, selects every
    /// screen that ships and forces AppKit to lay it out. It runs before the
    /// app's run loop, so it needs no WindowServer session and is safe in CI.
    /// A crash, a missing environment object or a view that refuses to size
    /// itself exits non-zero.
    @MainActor
    enum AppUISmoke {
        static func run() -> Never {
            _ = NSApplication.shared

            var checks: [(String, Bool)] = []
            let toolkit = ToolkitViewModel()
            let host = NSHostingView(
                rootView:
                    NetworkToolkitView(toolkit: toolkit)
                    .environmentObject(DiagnosticsViewModel())
                    .environmentObject(InterfacesViewModel())
                    .environmentObject(UptimeMonitor())
                    .environmentObject(AnalyzerViewModel())
                    .environmentObject(SurveyViewModel())
                    .environmentObject(AppUIState())
            )
            host.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
            host.layoutSubtreeIfNeeded()

            for tool in ToolboxTool.allCases where tool.isAvailable {
                toolkit.select(tool)
                host.layoutSubtreeIfNeeded()
                let size = host.fittingSize
                checks.append(
                    (
                        "tool:\(tool.rawValue)",
                        size.width > 0 && size.height > 0
                    ))
            }

            let meter = MenuBarMeterModel.shared
            let analyzer = AnalyzerViewModel()
            let diagnostics = DiagnosticsViewModel()
            let uptime = UptimeMonitor()
            let popover = NSHostingView(
                rootView:
                    MenuBarView(
                        viewModel: analyzer, diagnostics: diagnostics, uptime: uptime,
                        meter: meter, connectivity: ConnectivityWatchdog.shared,
                        route: RouteMonitor.shared
                    )
                    .environmentObject(AppUIState())
                    .environmentObject(ToolkitViewModel())
            )
            popover.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
            popover.layoutSubtreeIfNeeded()
            checks.append(("menu-bar-popover", popover.fittingSize.height > 0))

            let label = NSHostingView(
                rootView: MenuBarLabel(
                    meter: meter, viewModel: analyzer, diagnostics: diagnostics,
                    uptime: uptime, connectivity: ConnectivityWatchdog.shared,
                    route: RouteMonitor.shared))
            label.layoutSubtreeIfNeeded()
            checks.append(("menu-bar-label", label.fittingSize.width > 0))

            let failures = checks.filter { !$0.1 }
            let payload: [String: Any] = [
                "checks": checks.map { ["name": $0.0, "passed": $0.1] },
                "ok": failures.isEmpty,
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
                let text = String(data: data, encoding: .utf8)
            {
                print(text)
            }
            exit(failures.isEmpty ? 0 : 1)
        }
    }
#endif
