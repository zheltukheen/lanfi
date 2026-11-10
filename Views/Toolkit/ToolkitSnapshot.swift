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

            openWindow(id: "toolkit")

            if arguments.contains("--run") {
                run(toolkit.selection, toolkit: toolkit)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
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
            case .portScan: toolkit.portScan.run()
            case .traceroute: toolkit.traceroute.run()
            case .sslCertificate: toolkit.ssl.run()
            case .pathCheck: toolkit.pathCheck.run()
            case .subnetCalculator: toolkit.subnet.calculate()
            case .speedTest: toolkit.speedTest.run()
            default: break
            }
        }
    }
#endif
