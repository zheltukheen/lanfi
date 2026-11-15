import XCTest

final class ToolDescriptorTests: XCTestCase {
    func testEveryToolHasExactlyOneDescriptor() {
        XCTAssertEqual(ToolRegistry.all.count, ToolboxTool.allCases.count)
        XCTAssertEqual(Set(ToolRegistry.all.map(\.tool)).count, ToolboxTool.allCases.count)

        for tool in ToolboxTool.allCases {
            let descriptor = ToolRegistry.descriptor(for: tool)
            XCTAssertEqual(descriptor.tool, tool)
            XCTAssertFalse(descriptor.title.isEmpty)
            XCTAssertFalse(descriptor.icon.isEmpty)
        }
    }

    func testToolMetadataDelegatesToCatalog() {
        for tool in ToolboxTool.allCases {
            let descriptor = ToolRegistry.descriptor(for: tool)
            XCTAssertEqual(tool.title, descriptor.title)
            XCTAssertEqual(tool.icon, descriptor.icon)
            XCTAssertEqual(tool.section, descriptor.section)
            XCTAssertEqual(tool.isAvailable, descriptor.isAvailable)
            XCTAssertEqual(tool.plannedDetail, descriptor.plannedDetail)
        }
    }
}
