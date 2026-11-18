#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug-only window snapshot for design review: launches with
    /// `--snapshot-toolkit <path> [--tool <id>] [--bottom-tab <index>] [--run]
    /// [--demo] [--window-size 1180x760]`,
    /// opens the toolkit, captures its content view (no Screen Recording
    /// permission needed) and exits. Never compiled into Release.
    ///
    /// `--snapshot-survey`, `--snapshot-map` and `--snapshot-settings-page`
    /// render one screen off-screen instead; all three share `capture`.
    @MainActor
    enum ToolkitSnapshot {
        private static var didSchedule = false

        static func captureIfRequested(
            toolkit: ToolkitViewModel,
            analyzer: AnalyzerViewModel,
            survey: SurveyViewModel,
            uptime: UptimeMonitor
        ) {
            guard !didSchedule else { return }
            let arguments = ProcessInfo.processInfo.arguments
            Self.log("entry args=\(arguments.joined(separator: " "))")

            if let value = argument("--appearance", in: arguments) {
                NSApp.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
            }

            // Seeded fixtures keep documentation images deterministic: no
            // Location prompt, no dependency on the current radio, and nothing
            // written to the reviewer's stores (see `DemoData`).
            let isDemo = arguments.contains("--demo")
            if isDemo {
                analyzer.seedDemoData()
                survey.loadDemoProject()
                uptime.loadDemoSnapshot()
            }

            if let path = argument("--snapshot-survey", in: arguments) {
                let demoAnalyzer = AnalyzerViewModel()
                let demoSurvey = SurveyViewModel()
                if isDemo {
                    demoAnalyzer.seedDemoData()
                    demoSurvey.loadDemoProject()
                }
                capture(
                    SurveyView(analyzer: demoAnalyzer, survey: demoSurvey),
                    size: NSSize(width: 1300, height: 820), to: path, label: "survey")
                return
            }

            if let path = argument("--snapshot-map", in: arguments) {
                capture(
                    SurveyMapPreview(), size: NSSize(width: 900, height: 520), to: path,
                    label: "map")
                return
            }

            // Settings is a separate scene, so render its page directly instead
            // of relying on the Settings window being open.
            if let path = argument("--snapshot-settings-page", in: arguments) {
                capture(
                    GeneralSettingsPage().environmentObject(UpdaterController()),
                    size: NSSize(width: 900, height: 820), to: path, delay: 1,
                    label: "settings page")
                return
            }

            guard let path = argument("--snapshot-toolkit", in: arguments) else { return }
            let requestedTool = argument("--tool", in: arguments).flatMap(ToolboxTool.init(rawValue:))

            // The stored selection is restored when the view appears, so apply
            // the requested tool now (before `--run` picks the model) and again
            // after launch.
            if let requestedTool {
                toolkit.select(requestedTool)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    toolkit.select(requestedTool)
                }
            }

            if let tab = argument("--bottom-tab", in: arguments).flatMap(Int.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NotificationCenter.default.post(
                        name: .lanfiSelectBottomTab, object: nil, userInfo: ["tab": tab])
                }
            }

            if arguments.contains("--run") {
                run(toolkit.selection, toolkit: toolkit, demo: isDemo)
            }

            let delay = argument("--delay", in: arguments).flatMap(TimeInterval.init) ?? 7
            didSchedule = true

            Self.log("scheduling capture in \(delay)s (tool=\(toolkit.selection.rawValue))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let visible = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
                Self.log("capturing tool=\(toolkit.selection.rawValue)")
                guard
                    let window =
                        visible.first(where: { $0.identifier?.rawValue == "main" })
                        ?? visible.first(where: { $0.title == "LanFi" })
                        ?? visible.max(by: {
                            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
                        })
                else {
                    FileHandle.standardError.write(Data("snapshot: main window not found\n".utf8))
                    exit(2)
                }
                window.makeKeyAndOrderFront(nil)
                if let raw = argument("--window-size", in: arguments), let size = Self.size(raw) {
                    window.setContentSize(size)
                }
                window.contentView?.layoutSubtreeIfNeeded()
                guard let view = window.contentView, view.bounds.width > 100 else {
                    FileHandle.standardError.write(Data("snapshot: no bitmap\n".utf8))
                    exit(3)
                }
                writePNG(of: view, to: path)
                Self.log("wrote \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                exit(0)
            }
        }

        /// Value of `flag` when the next argument exists.
        private static func argument(_ flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                arguments.index(after: index) < arguments.endIndex
            else { return nil }
            return arguments[arguments.index(after: index)]
        }

        /// "1180x760" in points. The screenshot is captured at the backing
        /// scale, so a Retina Mac writes 2360×1520 pixels for `1180x760`.
        private static func size(_ raw: String) -> NSSize? {
            let parts = raw.lowercased().split(separator: "x")
            guard parts.count == 2,
                let width = Double(parts[0]), let height = Double(parts[1]),
                width >= 640, height >= 480
            else { return nil }
            return NSSize(width: width, height: height)
        }

        /// One off-screen window, one capture, one exit.
        private static func capture<Content: View>(
            _ rootView: Content,
            size: NSSize,
            to path: String,
            delay: TimeInterval = 4,
            label: String
        ) {
            didSchedule = true
            let host = NSHostingView(rootView: rootView)
            host.appearance = NSApp.appearance
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                host.layoutSubtreeIfNeeded()
                writePNG(of: host, to: path)
                Self.log("wrote \(label) \(path)")
                exit(0)
            }
        }

        private static func writePNG(of view: NSView, to path: String) {
            guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                exit(3)
            }
            view.cacheDisplay(in: view.bounds, to: representation)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                exit(4)
            }
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
                exit(5)
            }
        }

        private static func log(_ message: String) {
            let url = URL(fileURLWithPath: "/tmp/lanfi-snapshot.log")
            let line = "[\(Date())] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
                let handle = try? FileHandle(forWritingTo: url)
            {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }

        private static func run(
            _ tool: ToolboxTool, toolkit: ToolkitViewModel, demo: Bool
        ) {
            switch tool {
            case .ping: toolkit.ping.run()
            case .dnsLookup: toolkit.dns.run()
            case .dnsPropagation: toolkit.dnsPropagation.run()
            case .whois: toolkit.whois.run()
            case .geoIP:
                toolkit.geoIP.query = "1.1.1.1"
                toolkit.geoIP.run()
            case .visualTraceroute:
                toolkit.visualTraceroute.maxHops = 8
                toolkit.visualTraceroute.run()
            case .portScan:
                // example.com is behind a transparent proxy on many corporate
                // networks, which makes every port look open. 1.1.1.1 shows a
                // realistic mix of open, closed and filtered ports.
                if demo { toolkit.portScan.host = "1.1.1.1" }
                toolkit.portScan.run()
            case .traceroute: toolkit.traceroute.run()
            case .sslCertificate: toolkit.ssl.run()
            case .pathCheck: toolkit.pathCheck.run()
            case .subnetCalculator: toolkit.subnet.calculate()
            case .speedTest: toolkit.speedTest.run()
            case .mtr:
                toolkit.mtr.maxHops = 6
                toolkit.mtr.rounds = 3
                toolkit.mtr.run()
            case .lanScanner: toolkit.lanScanner.scan()
            case .iperf3: toolkit.iperf3.run()
            default: break
            }
        }
    }
#endif
