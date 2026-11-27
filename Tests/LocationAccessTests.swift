import CoreLocation
import XCTest

@MainActor
final class LocationAccessTests: XCTestCase {
    func testAuthorizationStatesCollapseToThree() {
        XCTAssertEqual(LocationAccessCenter.state(for: .authorized), .granted)
        XCTAssertEqual(LocationAccessCenter.state(for: .authorizedAlways), .granted)
        XCTAssertEqual(LocationAccessCenter.state(for: .denied), .denied)
        XCTAssertEqual(LocationAccessCenter.state(for: .restricted), .denied)
        XCTAssertEqual(LocationAccessCenter.state(for: .notDetermined), .undecided)
    }

    func testGrantedIsTheOnlyAuthorizedState() {
        XCTAssertTrue(LocationAccessCenter.AccessState.granted.isGranted)
        XCTAssertFalse(LocationAccessCenter.AccessState.denied.isGranted)
        XCTAssertFalse(LocationAccessCenter.AccessState.undecided.isGranted)
    }

    func testPromptCanBeOpenedAndDismissedFromAnyScreen() {
        let center = LocationAccessCenter.shared
        center.dismissPrompt()
        XCTAssertFalse(center.isPromptPresented)

        center.presentPrompt()
        XCTAssertTrue(center.isPromptPresented)

        center.dismissPrompt()
        XCTAssertFalse(center.isPromptPresented)
    }
}
