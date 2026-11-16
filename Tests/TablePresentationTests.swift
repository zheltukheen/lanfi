import XCTest

final class TablePresentationTests: XCTestCase {
    // MARK: - Density

    func testDensityResolutionFallsBackToStandard() {
        XCTAssertEqual(TableDensity.resolve(rowHeight: 0), .regular)
        XCTAssertEqual(TableDensity.resolve(rowHeight: 24), .compact)
        XCTAssertEqual(TableDensity.resolve(rowHeight: 26), .compact)
        XCTAssertEqual(TableDensity.resolve(rowHeight: 30.4), .regular)
        XCTAssertEqual(TableDensity.resolve(rowHeight: 37), .comfortable)
        XCTAssertEqual(TableDensity.allCases.map(\.rowHeight), [24, 30, 38])
        XCTAssertEqual(TableDensity.regular.rowHeight, 30)
        XCTAssertEqual(TableDensity.regular.fontSize, 13)
        XCTAssertLessThan(TableDensity.compact.fontSize, TableDensity.comfortable.fontSize)
    }

    // MARK: - Micro visuals

    func testSignalBarFractionsAndTints() {
        let strong = TableMicroVisualFactory.visual(
            for: .signal, network: makeNetwork(signal: -40), qualityScore: nil)
        XCTAssertEqual(strong?.tint, .ok)
        assertBar(strong, equals: 55.0 / 65.0)

        let weak = TableMicroVisualFactory.visual(
            for: .signal, network: makeNetwork(signal: -100), qualityScore: nil)
        XCTAssertEqual(weak?.tint, .danger)
        assertBar(weak, equals: 0)

        let middling = TableMicroVisualFactory.visual(
            for: .signal, network: makeNetwork(signal: -70), qualityScore: nil)
        XCTAssertEqual(middling?.tint, .warning)
    }

    func testQualityBarUsesTheQualityGrade() {
        XCTAssertNil(
            TableMicroVisualFactory.visual(for: .quality, network: makeNetwork(), qualityScore: nil))
        XCTAssertEqual(
            TableMicroVisualFactory.visual(for: .quality, network: makeNetwork(), qualityScore: 90)?
                .tint, .ok
        )
        XCTAssertEqual(
            TableMicroVisualFactory.visual(for: .quality, network: makeNetwork(), qualityScore: 50)?
                .tint, .warning
        )
        XCTAssertEqual(
            TableMicroVisualFactory.visual(for: .quality, network: makeNetwork(), qualityScore: 20)?
                .tint, .danger
        )
        assertBar(
            TableMicroVisualFactory.visual(
                for: .quality, network: makeNetwork(), qualityScore: 150), equals: 1)
    }

    /// Product rule: in-cell visuals exist for Signal and Quality only. Band,
    /// Security and every other column must stay text-only.
    func testOnlySignalAndQualityColumnsHaveMicroVisuals() {
        let network = makeNetwork(band: .band6, security: "WPA3 Personal")
        for column in ColumnId.allCases {
            let visual = TableMicroVisualFactory.visual(
                for: column, network: network, qualityScore: 70)
            switch column {
            case .signal, .quality:
                XCTAssertNotNil(visual, "Missing visual for \(column.rawValue)")
                if case .bar? = visual?.shape {
                } else {
                    XCTFail("Expected a bar for \(column.rawValue)")
                }
            case .band, .security, .vendor, .bssid, .channel, .snr, .maxRate, .networkName:
                XCTAssertNil(visual, "Unexpected visual for \(column.rawValue)")
            default:
                XCTAssertNil(visual, "Unexpected visual for \(column.rawValue)")
            }
        }
    }

    // MARK: - Column metadata

    func testIdentityColumnsAreNotSortOptions() {
        XCTAssertFalse(ColumnId.networkName.isSortableOption)
        XCTAssertFalse(ColumnId.bssid.isSortableOption)
        XCTAssertFalse(ColumnId.apName.isSortableOption)
        XCTAssertFalse(ColumnId.annotations.isSortableOption)
        XCTAssertTrue(ColumnId.signal.isSortableOption)
        XCTAssertTrue(ColumnId.security.isSortableOption)
        XCTAssertTrue(ColumnId.lastSeen.isSortableOption)
        XCTAssertEqual(
            ColumnId.allCases.filter(\.isSortableOption).count,
            ColumnId.allCases.count - 4)
    }

    // MARK: - Header decoration

    /// AppKit draws the sort indicator from the table's sort descriptor; the
    /// header text must not add a second arrow.
    func testHeaderOnlyAddsTheGroupingMarker() {
        XCTAssertEqual(TableHeaderDecoration.title(base: "Signal", isGrouped: false), "Signal")
        XCTAssertEqual(
            TableHeaderDecoration.title(base: "Network Name", isGrouped: true),
            "Network Name · grouped")
        XCTAssertFalse(TableHeaderDecoration.title(base: "Signal", isGrouped: false).contains("▲"))
    }

    // MARK: - Relative time

    func testSeenTimeIsRelativeUnderADayAndAbsoluteAfter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = NetworkColumnFormatter.formatSeen(
            now.addingTimeInterval(-120), now: now, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(recent.lowercased().contains("minute"), recent)

        let older = NetworkColumnFormatter.formatSeen(
            now.addingTimeInterval(-2 * 24 * 60 * 60), now: now, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(older.contains(":"), older)
        XCTAssertFalse(older.lowercased().contains("ago"), older)

        XCTAssertEqual(NetworkColumnFormatter.formatSeen(nil), "-")
    }

    // MARK: - Throughput values

    func testRateUsesCounterDeltaAndInterval() {
        let start = Date(timeIntervalSince1970: 1_000)
        let sample = ThroughputRate.sample(
            previous: InterfaceCounters(receivedBytes: 1_000, sentBytes: 500),
            previousAt: start,
            current: InterfaceCounters(receivedBytes: 1_001_000, sentBytes: 500),
            now: start.addingTimeInterval(10)
        )
        XCTAssertEqual(sample?.receivedBytesPerSecond ?? -1, 100_000, accuracy: 0.5)
        XCTAssertEqual(sample?.sentBytesPerSecond ?? -1, 0, accuracy: 0.5)
        XCTAssertNil(
            ThroughputRate.sample(
                previous: InterfaceCounters(receivedBytes: 1, sentBytes: 1), previousAt: start,
                current: InterfaceCounters(receivedBytes: 2, sentBytes: 2), now: start))
    }

    func testCounterResetContributesZeroInsteadOfASpike() {
        let start = Date(timeIntervalSince1970: 1_000)
        let sample = ThroughputRate.sample(
            previous: InterfaceCounters(receivedBytes: 5_000, sentBytes: 5_000),
            previousAt: start,
            current: InterfaceCounters(receivedBytes: 100, sentBytes: 200),
            now: start.addingTimeInterval(2)
        )
        XCTAssertEqual(sample?.receivedBytesPerSecond, 0)
        XCTAssertEqual(sample?.sentBytesPerSecond, 0)
    }

    func testSmootherEasesTowardsTheNewSample() {
        var smoother = ThroughputSmoother(alpha: 0.5)
        let start = Date(timeIntervalSince1970: 1_000)
        let first = smoother.add(
            ThroughputSample(
                at: start, receivedBytesPerSecond: 100, sentBytesPerSecond: 0))
        XCTAssertEqual(first.receivedBytesPerSecond, 100, accuracy: 0.01)

        let second = smoother.add(
            ThroughputSample(
                at: start.addingTimeInterval(2), receivedBytesPerSecond: 200,
                sentBytesPerSecond: 100))
        XCTAssertEqual(second.receivedBytesPerSecond, 150, accuracy: 0.01)
        XCTAssertEqual(second.sentBytesPerSecond, 50, accuracy: 0.01)
    }

    func testThroughputFormattingScalesBitsAndBytes() {
        XCTAssertEqual(ThroughputFormatter.rate(0, unit: .bits), "0 bit/s")
        XCTAssertEqual(ThroughputFormatter.rate(1_250_000, unit: .bits), "10 Mbit/s")
        XCTAssertEqual(ThroughputFormatter.rate(1_500_000, unit: .bytes), "1.5 MB/s")
        XCTAssertEqual(ThroughputFormatter.compact(1_250_000, unit: .bits), "10M")
        XCTAssertEqual(ThroughputFormatter.compact(1_500_000, unit: .bytes), "1.5M")
        XCTAssertEqual(ThroughputFormatter.compact(0, unit: .bits), "0")
    }

    // MARK: - Helpers

    private func assertBar(
        _ visual: TableMicroVisual?, equals expected: Double, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let visual, case .bar(let fraction) = visual.shape else {
            XCTFail("Expected a bar visual", file: file, line: line)
            return
        }
        XCTAssertEqual(fraction, expected, accuracy: 0.001, file: file, line: line)
    }
}
