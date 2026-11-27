import XCTest

@testable import LanFiCore

/// G10: a clean day, a flapping day and a sparse day must produce high, low
/// and "not enough data" verdicts, deterministically.
final class ReliabilityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func samples(count: Int, every: TimeInterval, rssi: (Int) -> Int) -> [ReliabilitySample] {
        (0..<count).map {
            ReliabilitySample(at: start.addingTimeInterval(Double($0) * every), rssi: rssi($0))
        }
    }

    private func signals(_ pairs: [(ReliabilitySignal, TimeInterval)]) -> [ReliabilitySignalRecord] {
        pairs.map { ReliabilitySignalRecord(signal: $0.0, at: start.addingTimeInterval($0.1)) }
    }

    func testCleanDayScoresGood() {
        let assessment = ReliabilityAssessor.assess(
            samples: samples(count: 120, every: 60) { _ in -55 },
            signals: signals([(.channelChanged, 1_800)]))

        XCTAssertEqual(assessment.grade, .good)
        XCTAssertEqual(assessment.score, 99)
        XCTAssertEqual(assessment.sampleCount, 120)
        XCTAssertEqual(assessment.averageRSSI, -55)
        XCTAssertEqual(assessment.weakSampleShare, 0)
        XCTAssertEqual(assessment.problems.map(\.signal), [.channelChanged])
        XCTAssertEqual(assessment.observedSeconds, 119 * 60)
    }

    func testFlappingDayScoresPoor() {
        let samples = samples(count: 180, every: 60) { index in index % 10 == 0 ? -84 : -72 }
        let signals = signals([
            (.disconnected, 600), (.disconnected, 2_400), (.disconnected, 6_000),
            (.roamingFailure, 1_200), (.roamingFailure, 4_800),
            (.deauthBurst, 3_000), (.weakSignal, 3_600), (.gatewayChanged, 7_200),
        ])

        let assessment = ReliabilityAssessor.assess(samples: samples, signals: signals)

        XCTAssertEqual(assessment.grade, .poor)
        let score = assessment.score ?? 100
        XCTAssertLessThan(score, 60)
        // Three disconnects cost 36; six more signals and the weak share pile on.
        XCTAssertLessThanOrEqual(score, 64)
        XCTAssertGreaterThan(assessment.weakSampleShare, 0)
        XCTAssertEqual(assessment.problems.first?.signal, .disconnected)
        XCTAssertEqual(assessment.problems.first?.count, 3)
    }

    func testSparseHistoryIsInsufficientNotBad() {
        let assessment = ReliabilityAssessor.assess(
            samples: samples(count: 4, every: 60) { _ in -50 },
            signals: signals([(.disconnected, 60)]))

        XCTAssertTrue(assessment.isInsufficient)
        XCTAssertNil(assessment.score)
        XCTAssertEqual(assessment.grade, .insufficient)
        // The problems are still reported: they happened, they just cannot be
        // turned into a verdict yet.
        XCTAssertEqual(assessment.problems.count, 1)

        let shortWindow = ReliabilityAssessor.assess(
            samples: samples(count: 30, every: 1) { _ in -50 }, signals: [])
        XCTAssertTrue(shortWindow.isInsufficient)
    }

    func testEmptyHistoryIsEmpty() {
        XCTAssertEqual(ReliabilityAssessor.assess(samples: [], signals: []), .empty)
    }

    func testScoreIsDeterministicAndClamped() {
        let samples = samples(count: 60, every: 60) { _ in -90 }
        let signals = signals(Array(repeating: (.disconnected, 300.0), count: 12))
        let first = ReliabilityAssessor.assess(samples: samples, signals: signals)
        let second = ReliabilityAssessor.assess(samples: samples, signals: signals)

        XCTAssertEqual(first, second)
        // 100 − 40 (disconnects capped) − 25 (every sample weak) = 35.
        XCTAssertEqual(first.score, 35)
    }

    func testSignalOrderIsByCostThenName() {
        let problems = ReliabilityAssessor.problemList(
            signals([
                (.channelChanged, 10), (.channelChanged, 20), (.channelChanged, 30),
                (.vpnLeak, 40), (.disconnected, 50),
            ]))
        XCTAssertEqual(problems.map(\.signal), [.disconnected, .vpnLeak, .channelChanged])
        XCTAssertEqual(problems[2].count, 3)
        XCTAssertEqual(problems[2].firstAt, start.addingTimeInterval(10))
        XCTAssertEqual(problems[2].lastAt, start.addingTimeInterval(30))
    }
}
