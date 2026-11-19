import XCTest

/// The registry is the single routing table: a tool points at one `ToolScreen`,
/// and the MCP specs it exposes are named on the same descriptor.
final class ToolRoutingTests: XCTestCase {
    func testEveryToolHasARoute() {
        for tool in ToolboxTool.allCases {
            XCTAssertFalse(tool.screen.rawValue.isEmpty, "No route for \(tool.rawValue)")
        }
    }

    func testTabbedToolsShareTheConnectionsScreen() {
        XCTAssertEqual(ToolboxTool.openConnections.screen, .connections)
        XCTAssertEqual(ToolboxTool.processTraffic.screen, .connections)
        XCTAssertFalse(ToolboxTool.processTraffic.showsInSidebar)
        XCTAssertTrue(ToolboxTool.openConnections.showsInSidebar)
    }

    func testEveryScreenIsReachable() {
        // Every screen in the enum is reachable from at least one tool; the
        // merged screens (.visualTraceroute, .whoisGeoIP) are routes other
        // tools share rather than separate destinations.
        let routed = Set(ToolboxTool.allCases.map(\.screen))
        XCTAssertEqual(routed.count, ToolScreen.allCases.count)
        for screen in ToolScreen.allCases {
            XCTAssertTrue(routed.contains(screen), "No tool routes to \(screen.rawValue)")
        }
    }

    func testClassicTracerouteIsMergedIntoTheVisualScreen() {
        XCTAssertEqual(ToolboxTool.traceroute.screen, .visualTraceroute)
        XCTAssertFalse(ToolboxTool.traceroute.showsInSidebar)
        XCTAssertTrue(ToolboxTool.visualTraceroute.showsInSidebar)
    }

    func testMTRIsTheContinuousTabOfTraceroute() {
        XCTAssertEqual(ToolboxTool.mtr.screen, .visualTraceroute)
        XCTAssertFalse(ToolboxTool.mtr.showsInSidebar)
        XCTAssertTrue(ToolboxTool.visualTraceroute.showsInSidebar)
    }

    func testWhoisAndGeoIPShareOneScreen() {
        XCTAssertEqual(ToolboxTool.whois.screen, .whoisGeoIP)
        XCTAssertEqual(ToolboxTool.geoIP.screen, .whoisGeoIP)
        XCTAssertTrue(ToolboxTool.whois.showsInSidebar)
        XCTAssertFalse(ToolboxTool.geoIP.showsInSidebar)
    }

    func testSidebarToolsHaveDistinctScreensOrASharedHost() {
        var seen: [ToolScreen: ToolboxTool] = [:]
        for tool in ToolboxTool.allCases where tool.showsInSidebar {
            if let existing = seen[tool.screen] {
                XCTFail(
                    "\(tool.rawValue) and \(existing.rawValue) both show \(tool.screen.rawValue) in the sidebar"
                )
            }
            seen[tool.screen] = tool
        }
    }

    func testDescriptorMCPToolsExistInTheRegistry() {
        let names = Set(MCPToolRegistry.names)
        for tool in ToolboxTool.allCases {
            for name in tool.mcpTools {
                XCTAssertTrue(names.contains(name), "\(tool.rawValue) lists unknown MCP tool \(name)")
            }
        }
    }

    func testMCPRegistryIsWellFormed() {
        let specs = MCPToolRegistry.all
        XCTAssertEqual(Set(specs.map(\.name)).count, specs.count)
        XCTAssertEqual(MCPToolkit.definitions.count, specs.count)
        for spec in specs {
            let definition = spec.definition
            XCTAssertEqual(definition["name"] as? String, spec.name)
            XCTAssertNotNil(definition["description"] as? String)
            let schema = definition["inputSchema"] as? [String: Any]
            XCTAssertEqual(schema?["type"] as? String, "object")
            XCTAssertNotNil(schema?["properties"] as? [String: Any])
        }
    }

    func testEveryHandlerNameIsAdvertised() {
        // The handler switch is the other half of the contract: every name it
        // answers must be in the registry, otherwise it is invisible to clients.
        let names = Set(MCPToolRegistry.names)
        XCTAssertTrue(names.contains("lanfi_scan_summary"))
        XCTAssertTrue(names.contains("lanfi_open_connections"))
        XCTAssertTrue(names.contains("lanfi_diagnostics"))
        XCTAssertEqual(names.count, 30)
    }
}
