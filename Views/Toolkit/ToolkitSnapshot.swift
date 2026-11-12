#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug-only window snapshot for design review: launches with
    /// `--snapshot-toolkit <path> [--tool <id>] [--bottom-tab <index>] [--run]`, opens the toolkit,
    /// captures its content view (no Screen Recording permission needed) and
    /// exits. Never compiled into Release.
    @MainActor
    enum ToolkitSnapshot {
        private static var didSchedule = false

        static func captureIfRequested(
            toolkit: ToolkitViewModel,
            uptime: UptimeMonitor
        ) {
            guard !didSchedule else { return }
            let arguments = ProcessInfo.processInfo.arguments
            Self.log("entry args=\(arguments.joined(separator: " "))")
            guard
                let flag = arguments.firstIndex(of: "--snapshot-toolkit"),
                arguments.index(after: flag) < arguments.endIndex
            else { return }
            let path = arguments[arguments.index(after: flag)]

            if let toolFlag = arguments.firstIndex(of: "--tool"),
                arguments.index(after: toolFlag) < arguments.endIndex,
                let tool = ToolboxTool(rawValue: arguments[arguments.index(after: toolFlag)])
            {
                toolkit.select(tool)
            }

            if let tabFlag = arguments.firstIndex(of: "--bottom-tab"),
                arguments.index(after: tabFlag) < arguments.endIndex,
                let tab = Int(arguments[arguments.index(after: tabFlag)])
            {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NotificationCenter.default.post(
                        name: .lanfiSelectBottomTab, object: nil, userInfo: ["tab": tab])
                }
            }

            if let hostFlag = arguments.firstIndex(of: "--host"),
                arguments.index(after: hostFlag) < arguments.endIndex
            {
                let host = arguments[arguments.index(after: hostFlag)]
                toolkit.ping.host = host
                toolkit.dns.host = host
                toolkit.portScan.host = host
                toolkit.traceroute.host = host
                toolkit.ssl.host = host
                toolkit.pathCheck.host = host
                toolkit.pathCheck.portsText = "443"
            }

            if arguments.contains("--uptime-demo") {
                if !uptime.targets.contains(where: {
                    $0.address.hasPrefix("https://example.com")
                }),
                    let target = UptimeTarget.make(
                        name: "API Server", address: "https://example.com", kind: .http,
                        intervalMinutes: 5)
                {
                    uptime.add(target, checkImmediately: false)
                    Task { await uptime.checkNow(target.id) }
                }
            }

            didSchedule = true

            if arguments.contains("--udp") {
                toolkit.portScan.includeUDP = true
            }

            if let tabFlag = arguments.firstIndex(of: "--dns-tab"),
                arguments.index(after: tabFlag) < arguments.endIndex,
                let tab = DNSLookupTab(rawValue: arguments[arguments.index(after: tabFlag)])
            {
                toolkit.dns.tab = tab
            }

            if arguments.contains("--run") {
                run(toolkit.selection, toolkit: toolkit)
            }

            let delay: TimeInterval
            if let delayFlag = arguments.firstIndex(of: "--delay"),
                arguments.index(after: delayFlag) < arguments.endIndex,
                let value = TimeInterval(arguments[arguments.index(after: delayFlag)])
            {
                delay = value
            } else {
                delay = 7
            }

            Self.log("scheduling capture in \(delay)s (tool=\(toolkit.selection.rawValue))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let visible = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
                Self.log("capturing tool=\(toolkit.selection.rawValue)")
                Self.log(
                    "windows "
                        + visible.map {
                            "\($0.title)|id=\($0.identifier?.rawValue ?? "-")|frame=\($0.frame)"
                        }.joined(separator: "; "))
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
                window.contentView?.layoutSubtreeIfNeeded()
                guard let view = window.contentView, view.bounds.width > 100,
                    let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else {
                    FileHandle.standardError.write(Data("snapshot: no bitmap\n".utf8))
                    exit(3)
                }
                view.cacheDisplay(in: view.bounds, to: representation)
                guard let data = representation.representation(using: .png, properties: [:]) else {
                    FileHandle.standardError.write(Data("snapshot: no PNG\n".utf8))
                    exit(4)
                }
                do {
                    try data.write(to: URL(fileURLWithPath: path))
                    Self.log("wrote \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                } catch {
                    FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
                    exit(5)
                }
                exit(0)
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

        private static func run(_ tool: ToolboxTool, toolkit: ToolkitViewModel) {
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
            case .portScan: toolkit.portScan.run()
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
