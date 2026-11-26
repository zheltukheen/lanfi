import XCTest

final class SurveyValidationTests: XCTestCase {
    private func sample(
        _ x: Double, _ y: Double, rssi: Int, download: Double? = nil, latency: Double? = nil
    ) -> SurveySample {
        SurveySample(
            id: UUID(), x: x, y: y, rssi: rssi, ssid: "Corp", bssid: "AA:BB:CC:DD:EE:01",
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000), downloadMbps: download,
            latencyMilliseconds: latency)
    }

    private var requirement: SurveyRequirement {
        SurveyRequirement(
            isEnabled: true, minRSSI: -67, minThroughputMbps: 50, maxLatencyMilliseconds: 100)
    }

    func testDisabledRequirementProducesNoVerdict() {
        XCTAssertNil(
            SurveyValidator.evaluate(
                samples: [sample(0.2, 0.2, rssi: -90)], requirement: .off))
        XCTAssertFalse(SurveyRequirement.off.isEnabled)
        XCTAssertFalse(SurveyProject.new().requirement.isEnabled)
    }

    func testAllPointsAboveThresholdsPass() {
        let samples = [
            sample(0.2, 0.2, rssi: -55, download: 120, latency: 20),
            sample(0.5, 0.5, rssi: -60, download: 80, latency: 30),
        ]
        let report = SurveyValidator.evaluate(samples: samples, requirement: requirement)
        XCTAssertEqual(report?.evaluated, 2)
        XCTAssertEqual(report?.passed, 2)
        XCTAssertEqual(report?.passPercentage, 100)
        XCTAssertEqual(report?.isPassing, true)
        XCTAssertEqual(report?.failures.isEmpty, true)
        XCTAssertNil(report?.worstRegion)
        XCTAssertEqual(report?.verdict.contains("PASS"), true)
    }

    func testMixedFloorReportsPercentageFailuresAndWorstRegion() {
        let failingA = sample(0.9, 0.9, rssi: -80, download: 100, latency: 20)
        let failingB = sample(0.85, 0.8, rssi: -75, download: 100, latency: 20)
        let samples = [
            sample(0.1, 0.1, rssi: -55, download: 100, latency: 20),
            sample(0.3, 0.2, rssi: -60, download: 100, latency: 20),
            failingA,
            failingB,
        ]
        let report = SurveyValidator.evaluate(samples: samples, requirement: requirement)
        XCTAssertEqual(report?.evaluated, 4)
        XCTAssertEqual(report?.passed, 2)
        XCTAssertEqual(report?.passPercentage, 50)
        XCTAssertEqual(report?.failures.map(\.sampleID), [failingA.id, failingB.id])
        XCTAssertEqual(report?.worstRegion, "south-east area")
        XCTAssertEqual(report?.verdict, "FAIL · 50% · 2 of 4 points fail")
        XCTAssertEqual(report?.reportLine.contains("worst: south-east area"), true)
    }

    func testThroughputAndLatencyThresholds() {
        let slow = sample(0.2, 0.2, rssi: -50, download: 10, latency: 250)
        let report = SurveyValidator.evaluate(samples: [slow], requirement: requirement)
        let reasons = report?.failures.first?.reasons ?? []
        XCTAssertEqual(reasons.count, 2)
        XCTAssertTrue(reasons.contains { $0.contains("10 < 50 Mbps") })
        XCTAssertTrue(reasons.contains { $0.contains("250 > 100 ms") })
    }

    func testUnmeasuredPointsAreNotFailedOnThroughput() {
        let unmeasured = sample(0.2, 0.2, rssi: -50)
        let report = SurveyValidator.evaluate(samples: [unmeasured], requirement: requirement)
        XCTAssertEqual(report?.failures.isEmpty, true)
        XCTAssertEqual(report?.unmeasuredThroughput, 1)
        XCTAssertEqual(report?.unmeasuredLatency, 1)
        XCTAssertEqual(report?.isPassing, true)
        XCTAssertEqual(report?.reportLine.contains("without throughput/latency"), true)
    }

    func testEmptyFloorHasNoPercentage() {
        let report = SurveyValidator.evaluate(samples: [], requirement: requirement)
        XCTAssertEqual(report?.evaluated, 0)
        XCTAssertEqual(report?.passPercentage, 0)
        XCTAssertEqual(report?.isPassing, false)
    }

    func testRequirementRoundTripsWithTheProject() throws {
        var project = SurveyProject.new()
        project.requirement = requirement
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(SurveyProject.self, from: data)
        XCTAssertEqual(decoded.requirement.minRSSI, -67)
        XCTAssertEqual(decoded.requirement.minThroughputMbps, 50)
        XCTAssertTrue(decoded.requirement.isEnabled)
    }

    func testOldProjectWithoutRequirementDecodesAsOff() throws {
        let project = SurveyProject.new()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(project)) as? [String: Any])
        object.removeValue(forKey: "requirement")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(SurveyProject.self, from: data)
        XCTAssertEqual(decoded.requirement, .off)
        XCTAssertFalse(decoded.requirement.isEnabled)
    }
}
