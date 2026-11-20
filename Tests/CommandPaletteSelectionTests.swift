import XCTest

final class CommandPaletteSelectionTests: XCTestCase {
    private func items(_ count: Int) -> [CommandItem] {
        (0..<count).map { index in
            CommandItem(
                id: "item.\(index)", title: "Item \(index)", subtitle: "", category: "Test",
                keywords: [], destination: .wifiTab(index))
        }
    }

    func testResetHighlightsTheFirstResult() {
        var selection = CommandPaletteSelection()
        selection.reset(to: items(3))
        XCTAssertEqual(selection.id, "item.0")
        XCTAssertNotNil(selection.item(in: items(3)))
    }

    func testResetKeepsAnExistingRow() {
        var selection = CommandPaletteSelection(id: "item.2")
        selection.reset(to: items(3))
        XCTAssertEqual(selection.id, "item.2")
    }

    func testResetFallsBackWhenTheRowDisappears() {
        var selection = CommandPaletteSelection(id: "item.9")
        selection.reset(to: items(3))
        XCTAssertEqual(selection.id, "item.0")
    }

    func testMoveDownAndUp() {
        var selection = CommandPaletteSelection(id: "item.0")
        selection.move(by: 1, in: items(3))
        XCTAssertEqual(selection.id, "item.1")
        selection.move(by: -1, in: items(3))
        XCTAssertEqual(selection.id, "item.0")
    }

    func testMoveWrapsAtBothEnds() {
        var selection = CommandPaletteSelection(id: "item.2")
        selection.move(by: 1, in: items(3))
        XCTAssertEqual(selection.id, "item.0", "past the last row wraps to the first")
        selection.move(by: -1, in: items(3))
        XCTAssertEqual(selection.id, "item.2", "above the first row wraps to the last")
    }

    func testMoveFromNoSelectionLandsOnAnEnd() {
        var down = CommandPaletteSelection()
        down.move(by: 1, in: items(3))
        XCTAssertEqual(down.id, "item.0")

        var up = CommandPaletteSelection()
        up.move(by: -1, in: items(3))
        XCTAssertEqual(up.id, "item.2")
    }

    func testMoveInAnEmptyListClearsTheSelection() {
        var selection = CommandPaletteSelection(id: "item.0")
        selection.move(by: 1, in: [])
        XCTAssertNil(selection.id)
    }

    func testSelectedItemResolves() {
        let selection = CommandPaletteSelection(id: "item.1")
        XCTAssertEqual(selection.item(in: items(3))?.title, "Item 1")
    }
}
