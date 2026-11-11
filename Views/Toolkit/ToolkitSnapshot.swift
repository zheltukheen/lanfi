#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug-only window snapshot for design review: launches with
    /// `--snapshot-toolkit <path> [--tool <id>] [--run]`, opens the toolkit,
    /// captures its content view (no Screen Recording permission needed) and
    /// exits. Never compiled into Release.
    @MainActor
    enum ToolkitSnapshot {
        static func captureIfRequested(
            toolkit: ToolkitViewModel,
            uptime: UptimeMonitor,
            openWindow: OpenWindowAction
        ) {
            let arguments = ProcessInfo.processInfo.arguments
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

            if let hostFlag = arguments.firstIndex(of: "--host"),
                arguments.index(after: hostFlag) < arguments.endIndex
            {
                let host = arguments[arguments.index(after: hostFlag)]
                toolkit.ping.host = host
                toolkit.dns.host = host
                toolkit.portScan.host = host
                toolkit.traceroute.host = host
                toolkit.ssl.host = host
                toolkit.pathCheck.target = "\(host):443"
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

            openWindow(id: "toolkit")

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

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard
                    let window = NSApp.windows.first(where: {
                        $0.title == "Network Toolkit" || $0.identifier?.rawValue == "toolkit"
                    })
                else {
                    FileHandle.standardError.write(Data("snapshot: toolkit window not found\n".utf8))
                    exit(2)
                }
                window.makeKeyAndOrderFront(nil)
                guard let view = window.contentView,
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
                    print("snapshot: wrote \(path) (\(Int(view.bounds.width))×\(Int(view.bounds.height)))")
                } catch {
                    FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
                    exit(5)
                }
                exit(0)
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
