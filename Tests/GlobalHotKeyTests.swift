import AppKit
import XCTest

final class GlobalHotKeyTests: XCTestCase {
    func testDisplayOrderAndGlyphs() {
        let flags = GlobalHotKey.command | GlobalHotKey.option | GlobalHotKey.shift
        XCTAssertEqual(GlobalHotKey.displayString(carbonModifiers: flags, key: "K"), "⌥⇧⌘K")
        XCTAssertEqual(
            GlobalHotKey.displayString(
                carbonModifiers: GlobalHotKey.control | GlobalHotKey.command, key: "C"), "⌃⌘C")
    }

    func testModifierConversion() {
        XCTAssertEqual(
            GlobalHotKey.modifiers(from: [.control, .option, .command]),
            GlobalHotKey.control | GlobalHotKey.option | GlobalHotKey.command)
        XCTAssertEqual(GlobalHotKey.modifiers(from: []), 0)
    }

    func testShortcutNeedsARealModifier() {
        if case .failure(let error) = GlobalHotKey.validate(carbonModifiers: 0, key: "C") {
            XCTAssertEqual(error, .needsModifier)
        } else {
            XCTFail("a bare key must not be accepted")
        }
        // Shift alone only types a capital letter.
        if case .failure(let error) = GlobalHotKey.validate(
            carbonModifiers: GlobalHotKey.shift, key: "C")
        {
            XCTAssertEqual(error, .needsModifier)
        } else {
            XCTFail("shift alone must not be accepted")
        }
        XCTAssertNoThrow(
            try GlobalHotKey.validate(
                carbonModifiers: GlobalHotKey.control, key: "C"
            ).get())
    }

    func testReservedCombinationsAreRefusedByName() {
        for display in ["⌘Q", "⌘W", "⌘TAB", "⌘SPACE", "⌃⌘Q", "⌘K"] {
            XCTAssertTrue(GlobalHotKey.reserved(display), "\(display) should be reserved")
        }
        XCTAssertFalse(GlobalHotKey.reserved("⌃⌥C"))

        let result = GlobalHotKey.validate(
            carbonModifiers: GlobalHotKey.command, key: "Q")
        guard case .failure(.reserved(let display)) = result else {
            return XCTFail("⌘Q must be refused")
        }
        XCTAssertEqual(display, "⌘Q")
    }

    func testRecordFromARealKeyEvent() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.control, .option],
                timestamp: 0, windowNumber: 0, context: nil, characters: "c",
                charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        let hotKey = try GlobalHotKey.record(from: event).get()
        XCTAssertEqual(hotKey.display, "⌃⌥C")
        XCTAssertEqual(hotKey.keyCode, 8)
    }

    func testRecordRefusesAReservedCombination() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q",
                isARepeat: false, keyCode: 12))
        guard case .failure(.reserved) = GlobalHotKey.record(from: event) else {
            return XCTFail("⌘Q must be refused while recording")
        }
    }

    func testSpaceReadsAsAWordNotASpace() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0,
                windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ",
                isARepeat: false, keyCode: 49))
        XCTAssertEqual(try GlobalHotKey.record(from: event).get().display, "⌃⌥SPACE")
    }

    func testStoreRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LanFi.HotKeyTests"))
        defer { defaults.removePersistentDomain(forName: "LanFi.HotKeyTests") }
        XCTAssertNil(GlobalHotKeyStore.load(from: defaults))

        let hotKey = GlobalHotKey(
            keyCode: 8, carbonModifiers: GlobalHotKey.control | GlobalHotKey.option,
            display: "⌃⌥C")
        GlobalHotKeyStore.save(hotKey, to: defaults)
        XCTAssertEqual(GlobalHotKeyStore.load(from: defaults), hotKey)

        GlobalHotKeyStore.save(nil, to: defaults)
        XCTAssertNil(GlobalHotKeyStore.load(from: defaults))
    }

    /// Registers with the real system API and puts the previous shortcut back,
    /// so the registration path is exercised rather than only the formatting.
    @MainActor
    func testSystemRegistrationRoundTrip() throws {
        let center = GlobalHotKeyCenter.shared
        let previous = center.hotKey
        defer { center.set(previous) }

        let hotKey = GlobalHotKey(
            keyCode: 8, carbonModifiers: GlobalHotKey.control | GlobalHotKey.option,
            display: "⌃⌥C")
        center.set(hotKey)
        XCTAssertEqual(center.hotKey, hotKey)
        XCTAssertNil(center.lastError, "registration failed: \(center.lastError ?? "")")

        center.set(nil)
        XCTAssertNil(center.hotKey)
    }
}
